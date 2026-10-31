/// 每日提醒服务（SPEC 第 14 章）。
///
/// 职责三件：
///   1. Android 13+ 动态申请 POST_NOTIFICATIONS；拒绝不崩溃、不阻塞。
///   2. 用 flutter_local_notifications 的 zonedSchedule 预排每日通知，到点由系统闹钟唤醒直接弹出。
///   3. 每天最多一条、错过不补发（用 app_settings 里 last_notified_day 去重）。
///
/// 设计口径：
/// - 通知文案在「每次 App 启动 / 每次重设提醒」时实时算一次，到点由系统按排程弹出；
///   不再引入 WorkManager 后台隔离进程（其 pigeon 产物的 Kotlin metadata 会触发 D8/ng4 崩溃）。
/// - 用户关掉提醒 / 拒绝权限时，任务照样注册但内部直接 return，避免反复申请打扰。
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants.dart';
import '../date_utils.dart';
import '../../data/db/app_database.dart';
import '../../data/repo/concept_repo.dart';
import '../../data/repo/question_repo.dart';
import '../../data/repo/plan_repo.dart';
import '../../data/repo/settings_repo.dart';

/// 通知渠道 id。
const String kReminderChannelId = 'daily_reminder';

/// 通知 id（固定，保证同日只覆盖不叠加）。
const int kReminderNotificationId = 1001;

/// 通知点击后回到 App 的负载（目前只用于识别来源）。
const String kReminderPayload = 'open_today';

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

    tzdata.initializeTimeZones();
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
  /// 用 zonedSchedule 预排：每天同一时刻重复，App 不需要常驻。
  /// 重复调用只会替换同 id 的那一条，不会叠加。
  /// [database] 为空时用兜底文案（启动早期 DB 尚未就绪的场景）。
  Future<void> schedule({
    required int hour,
    required int minute,
    AppDatabase? database,
  }) async {
    if (!Platform.isAndroid) return;
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime next =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    final String body = database == null
        ? '今天还有任务没打卡，点开看看'
        : await _buildBody(database);
    await _plugin.zonedSchedule(
      kReminderNotificationId,
      kAppName,
      body,
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kReminderChannelId,
          '每日打卡提醒',
          channelDescription: '每天提醒一次今天还剩多少条没打卡',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: kReminderPayload,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// 取消每日提醒。
  Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await _plugin.cancel(kReminderNotificationId);
  }

  /// 算出当前该推的文案（不写 last_notified_day，纯计算）。
  Future<String> _buildBody(AppDatabase database) async {
    final questionRepo = QuestionRepo(database);
    final conceptRepo = ConceptRepo(database);
    final PlanRepo planRepo = PlanRepo(database);
    final int remaining = (await planRepo.todayPendingItems()).length;
    final int dueCards = await questionRepo.dueReviewCount();
    final int dueConcepts = await conceptRepo.dueConceptCount();
    final int total = remaining + dueCards + dueConcepts;
    if (total <= 0) {
      return '今天的任务都完成了，明天见';
    }
    final int estMinutes = await planRepo.todayEstimateMinutes() +
        dueCards +
        dueConcepts;
    var body = '今天计划 ' + total.toString() + ' 条，还没打卡';
    if (estMinutes > 0) {
      body = body + '，预计 ' + estMinutes.toString() + ' 分钟';
    }
    return body;
  }

  /// 立即推一条（自测入口）：算数 -> 去重 -> 推通知。
  Future<void> runDailyJob(AppDatabase database) async {
    final settings = SettingsRepo(database);

    final bool enabled = await settings.reminderEnabled();
    if (!enabled) return;

    final String todayKey = _dayKey(DateTime.now());
    final String? lastDay = await settings.lastNotifiedDay();
    if (lastDay == todayKey) return;

    final String body = await _buildBody(database);

    if (!Platform.isAndroid) return;
    await _plugin.show(
      kReminderNotificationId,
      kAppName,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kReminderChannelId,
          '每日打卡提醒',
          channelDescription: '每天提醒一次今天还剩多少条没打卡',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
      payload: kReminderPayload,
    );

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
