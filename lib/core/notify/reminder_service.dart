/// 每日提醒服务（SPEC 第 14 章）。
///
/// 职责三件：
///   1. Android 13+ 动态申请 POST_NOTIFICATIONS；拒绝不崩溃、不阻塞。
///   2. 用 WorkManager 注册每日周期任务，到点在后台算「还剩几条 / 预计几分钟」并推通知。
///   3. 每天最多一条、错过不补发（用 app_settings 里 last_notified_day 去重）。
///
/// 设计口径：
/// - 通知文案必须实时准确，不能在 App 前台预先算好存死；
///   因此选择 WorkManager 后台任务而不是 zonedSchedule 预排。
/// - 用户关掉提醒 / 拒绝权限时，任务照样注册但内部直接 return，避免反复申请打扰。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../constants.dart';
import '../date_utils.dart';
import '../../data/db/app_database.dart';
import '../../data/repo/concept_repo.dart';
import '../../data/repo/question_repo.dart';
import '../../data/repo/plan_repo.dart';
import '../../data/repo/settings_repo.dart';

/// WorkManager 里这条任务的唯一名字。改名会导致旧任务残留，别动。
const String kDailyReminderTask = 'study_tracker_daily_reminder';

/// 通知渠道 id。
const String kReminderChannelId = 'daily_reminder';

/// 通知 id（固定，保证同日只覆盖不叠加）。
const int kReminderNotificationId = 1001;

/// 通知点击后回到 App 的负载（目前只用于识别来源）。
const String kReminderPayload = 'open_today';

/// 顶层入口：WorkManager 后台 isolate 只能调顶层函数，不能是类方法。
/// 这里 new 一个独立的 AppDatabase，不复用 UI isolate 里的那个实例。
@pragma('vm:entry-point')
void reminderDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    try {
      await ReminderService().runDailyJob(AppDatabase());
    } catch (e) {
      // 后台任务抛异常会让系统认为失败并重试，这里吞掉，避免反复唤醒。
      if (kDebugMode) debugPrint('[REMINDER] job error: ' + e.toString());
    }
    return true;
  });
}

/// 提醒服务。UI 侧用 [init] / [schedule] / [cancel] / [requestPermission]。
class ReminderService {
  ReminderService();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inited = false;

  /// 初始化通知插件并注册后台分发器。
  /// 必须在 runApp 之前调用一次（main 里已调用）。
  Future<void> init() async {
    if (_inited) return;
    if (!Platform.isAndroid) {
      _inited = true;
      return;
    }
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings =
        InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);

    // 建渠道：低打扰、不响铃只提示（打卡提醒不需要强提醒）。
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      kReminderChannelId,
      '每日打卡提醒',
      description: '每天提醒一次今天还剩多少条没打卡',
      importance: Importance.defaultImportance,
    );
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);

    await Workmanager().initialize(reminderDispatcher);
    _inited = true;
  }

  /// Android 13+ 申请通知权限。返回是否已授权。
  /// 已授权或系统版本低于 13 直接返回 true。
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final bool? granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 当前是否已授权（用于设置页开关状态）。
  Future<bool> isPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final bool? enabled = await android?.areNotificationsEnabled();
    return enabled ?? false;
  }

  /// 注册每日提醒。[hour]/[minute] 为本地时间。
  /// 重复注册是安全的：同名任务会被替换，不会叠加。
  Future<void> schedule({required int hour, required int minute}) async {
    if (!Platform.isAndroid) return;
    await Workmanager().cancelByUniqueName(kDailyReminderTask);
    // 算到下一个目标时刻还要多久，作为首次延迟。
    final DateTime now = DateTime.now();
    DateTime next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    final Duration initialDelay = next.difference(now);
    await Workmanager().registerPeriodicTask(
      kDailyReminderTask,
      kDailyReminderTask,
      initialDelay: initialDelay,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// 取消每日提醒。
  Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await Workmanager().cancelByUniqueName(kDailyReminderTask);
  }

  /// 后台任务实际执行体：算数 -> 去重 -> 推通知。
  /// 也可在 App 启动时直接调用用于自测。
  Future<void> runDailyJob(AppDatabase database) async {
    final settings = SettingsRepo(database);

    // 1. 开关关着就不做任何事。
    final bool enabled = await settings.reminderEnabled();
    if (!enabled) return;

    // 2. 每天最多一条：今天已经推过就直接退出。
    final String todayKey = _dayKey(DateTime.now());
    final String? lastDay = await settings.lastNotifiedDay();
    if (lastDay == todayKey) return;

    // 3. 算数：未完成条目数 + 到期复习数。
    final questionRepo = QuestionRepo(database);
    final conceptRepo = ConceptRepo(database);
    final PlanRepo planRepo = PlanRepo(database);
    final int remaining = (await planRepo.todayPendingItems()).length;
    final int dueCards = await questionRepo.dueReviewCount();
    final int dueConcepts = await conceptRepo.dueConceptCount();

    final int total = remaining + dueCards + dueConcepts;
    // 全部做完就不打扰。
    if (total <= 0) {
      await settings.setLastNotifiedDay(todayKey);
      return;
    }

    // 4. 预计分钟：剩余条目按日均 minutes 估算，复习按每张 1 分钟。
    final int estMinutes = await planRepo.todayEstimateMinutes() +
        dueCards +
        dueConcepts;

    // 5. 文案严格按 SPEC 第 14 章。
    final String title = kAppName;
    var body = '今天计划 ' + total.toString() + ' 条，还没打卡';
    if (estMinutes > 0) {
      body = body + '，预计 ' + estMinutes.toString() + ' 分钟';
    }

    if (!Platform.isAndroid) return;
    await _plugin.show(
      kReminderNotificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kReminderChannelId,
          '每日打卡提醒',
          channelDescription: '每天提醒一次今天还剩多少条没打卡',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          // 只用大图标，不额外塞小图标资源，避免缺资源导致通知不显示。
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
      payload: kReminderPayload,
    );

    // 6. 记下今天已推，防止同日重复。
    await settings.setLastNotifiedDay(todayKey);
  }

  /// 生成「日」唯一键，按 04:00 为界（与全 App 口径一致）。
  String _dayKey(DateTime now) {
    final DateTime d = startOfDay(now);
    return d.year.toString().padLeft(4, '0') +
        '-' +
        d.month.toString().padLeft(2, '0') +
        '-' +
        d.day.toString().padLeft(2, '0');
  }
}
