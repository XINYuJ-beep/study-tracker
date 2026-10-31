import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/backup/backup_service.dart';
import '../../data/seed/seeder.dart';
import '../../data/repo/settings_repo.dart';
import '../../core/notify/reminder_service.dart';

/// 设置页。
///
/// 六项功能：每日目标（读写 app_settings.daily_goal）、数据版本、
/// 数据现状（八表计数对照内置期望）、重新导入、清空重导、关于。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _loading = true;
  String? _error;

  bool _busy = false;
  String _busyText = '处理中…';

  int _dailyGoal = AppConstants.dailyGoalDefault;
  int? _installedVersion;
  SeedResult? _counts;
  bool _reminderEnabled = true;
  int _reminderHour = AppConstants.reminderHourDefault;
  int _reminderMinute = AppConstants.reminderMinuteDefault;
  bool _permGranted = true;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoBackupIfNeeded();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final seeder = ref.read(seederProvider);

      final rows = await db.query(
        T.appSettings,
        where: 'key = ? OR key = ?',
        whereArgs: ['daily_goal', AppConstants.keyDataVersion],
      );

      String? goalRaw;
      String? versionRaw;
      for (final r in rows) {
        final k = r['key'] as String?;
        final v = r['value'] as String?;
        if (k == 'daily_goal') goalRaw = v;
        if (k == AppConstants.keyDataVersion) versionRaw = v;
      }

      final counts = await seeder.countExisting();
      final SettingsRepo settings = SettingsRepo(db);
      final bool rEnabled = await settings.reminderEnabled();
      final (int, int) rTime = await settings.reminderTime();
      bool perm = true;
      try {
        perm = await ReminderService().isPermissionGranted();
      } catch (_) {
        perm = true;
      }

      if (!mounted) return;
      setState(() {
        _dailyGoal = _parseGoal(goalRaw);
        _installedVersion = _parseVersion(versionRaw);
        _counts = counts;
        _reminderEnabled = rEnabled;
        _reminderHour = rTime.$1;
        _reminderMinute = rTime.$2;
        _permGranted = perm;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _parseGoal(String? raw) {
    if (raw == null) return AppConstants.dailyGoalDefault;
    final n = int.tryParse(raw.trim());
    if (n == null || n <= 0) return AppConstants.dailyGoalDefault;
    return n;
  }

  String _hhmm(int h, int m) {
    return h.toString().padLeft(2, '0') + ':' + m.toString().padLeft(2, '0');
  }

  Future<void> _toggleReminder(bool on) async {
    final bool prev = _reminderEnabled;
    setState(() => _reminderEnabled = on);
    try {
      final SettingsRepo settings = SettingsRepo(ref.read(databaseProvider));
      await settings.setReminderEnabled(on);
      final svc = ReminderService();
      if (on) {
        final bool granted = await svc.requestPermission();
      if (!mounted) return;
        setState(() => _permGranted = granted);
        if (!granted) {
          _toast('未授予通知权限，提醒不会弹出。请到系统设置里打开。');
        }
        await svc.schedule(hour: _reminderHour, minute: _reminderMinute);
      if (!mounted) return;
        _toast('已开启每日提醒：' + _hhmm(_reminderHour, _reminderMinute));
      } else {
        await svc.cancel();
      if (!mounted) return;
        _toast('已关闭每日提醒');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _reminderEnabled = prev);
      _toast('设置失败：' + e.toString());
    }
  }

  Future<void> _pickReminderTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
      helpText: '选择每天提醒的时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    final int prevH = _reminderHour;
    final int prevM = _reminderMinute;
    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
    try {
      final SettingsRepo settings = SettingsRepo(ref.read(databaseProvider));
      await settings.setReminderTime(picked.hour, picked.minute);
      if (_reminderEnabled) {
        await ReminderService().schedule(
          hour: picked.hour,
          minute: picked.minute,
        );
      }
      if (!mounted) return;
      _toast('提醒时间已改为 ' + _hhmm(picked.hour, picked.minute));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reminderHour = prevH;
        _reminderMinute = prevM;
      });
      _toast('保存失败：' + e.toString());
    }
  }

  int? _parseVersion(String? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  Future<void> _saveGoal(int v) async {
    final int goal = v.clamp(1, 20).toInt();
    final prev = _dailyGoal;
    setState(() => _dailyGoal = goal);
    try {
      final db = ref.read(databaseProvider);
      await db.insert(
        T.appSettings,
        {'key': 'daily_goal', 'value': goal.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (!mounted) return;
      _toast('每日目标已保存：' + goal.toString() + ' 题');
    } catch (e) {
      if (!mounted) return;
      setState(() => _dailyGoal = prev);
      _toast('保存失败：' + e.toString());
    }
  }

  Future<void> _reseed() async {
    final yes = await _confirm(
      title: '重新导入数据',
      message: '将按内置 JSON 重新导入缺失数据（已存在的数据不会重复写入）。继续？',
    );
    if (!yes) return;

    await _runTask('正在导入…', () async {
      final seeder = ref.read(seederProvider);
      final result = await seeder.seedIfNeeded();
      await _load();
      _showResult(result, '导入完成');
      return null;
    });
  }

  Future<void> _clearAndReseed() async {
    final yes = await _confirm(
      title: '清空并重导',
      message: '将清空全部业务数据（学习记录、计划、题库进度等），'
          '仅保留每日目标等设置，然后重新导入内置数据。\n\n此操作不可撤销。',
      danger: true,
    );
    if (!yes) return;

    await _runTask('正在清空并重导…', () async {
      final db = ref.read(databaseProvider);
      final seeder = ref.read(seederProvider);

      // 清空前先落一份回滚备份，失败了不阻断清空流程。
      try {
        final rollback = await BackupService(
          await db.database,
        ).exportJson(prefix: BackupService.rollbackPrefix);
        await rollback.length();
      } catch (_) {}

      final cleared = await db.clearBusinessData();
      final result = await seeder.seedIfNeeded();
      await _load();

      if (!mounted) return;
      _toast(
        '已清空 ' +
            cleared.tableCount.toString() +
            ' 张表 / ' +
            cleared.deletedRows.toString() +
            ' 行，重置设置 ' +
            cleared.settingsRows.toString() +
            ' 项',
      );
      _showResult(result, '重导完成');
      return null;
    });
  }

  /// 执行一次性长任务：统一置忙态、兜住异常。
  /// body 可返回结果文案，非 null 时在任务结束后以 toast 呈现。
  Future<void> _runTask(String text, Future<String?> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyText = text;
    });
    String? result;
    try {
      result = await body();
    } catch (e) {
      if (mounted) _toast('出错了：' + e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (result != null) _toast(result);
  }

  void _showResult(SeedResult r, String okTitle) {
    if (r.ok) {
      _toast(
        okTitle +
            '：模块 ' +
            r.modules.toString() +
            ' / 周 ' +
            r.weeks.toString() +
            ' / 条目 ' +
            r.items.toString() +
            ' / 卡片 ' +
            r.cards.toString() +
            ' / 选择题 ' +
            r.mcqs.toString() +
            ' / 概念 ' +
            r.concepts.toString() +
            ' / 阶段 ' +
            r.stages.toString() +
            ' / 题组 ' +
            r.streams.toString(),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(okTitle + '但有异常'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.fatalError != null) ...[
                Text('致命错误：', style: _tsBoldWarning),
                Text(r.fatalError!),
                const SizedBox(height: AppSizes.gap2),
              ],
              ...r.failures().map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· ' + f),
                ),
              ),
              if (r.skipped.isNotEmpty) ...[
                const SizedBox(height: AppSizes.gap2),
                Text('跳过 ' + r.skipped.length.toString() + ' 项（前 5 条）：'),
                ...r.skipped.take(5).map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('· ' + s, style: _tsMinor),
                      ),
                    ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    bool danger = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: danger
                ? TextButton.styleFrom(foregroundColor: AppColors.warning)
                : null,
            child: Text(danger ? '清空并重导' : '继续'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _toast(String msg) {
      if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '刷新',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Center(
        child: Semantics(
          label: '正在加载…',
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.gap3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.warning),
              const SizedBox(height: AppSizes.gap2),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppSizes.body,
                  color: AppColors.textMinor,
                ),
              ),
              const SizedBox(height: AppSizes.gap3),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppConstants.breakpointNarrow;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSizes.gap2,
              AppSizes.gap,
              AppSizes.gap2,
              AppSizes.gap3,
            ),
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _goalCard()),
                    const SizedBox(width: AppSizes.gap2),
                    Expanded(child: _versionCard()),
                  ],
                )
              else ...[
                _goalCard(),
                const SizedBox(height: AppSizes.gap2),
                _versionCard(),
              ],
              const SizedBox(height: AppSizes.gap2),
              _reminderCard(),
              const SizedBox(height: AppSizes.gap2),
              _dataCard(),
              const SizedBox(height: AppSizes.gap2),
              _actionCard(),
              const SizedBox(height: AppSizes.gap2),
              _aboutCard(),
            ],
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: _busyText,
              child: Container(
              color: Colors.black.withValues(alpha: 0.28),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.gap3,
                    vertical: AppSizes.gap2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                    boxShadow: kCardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      const SizedBox(height: AppSizes.gap2),
                      Text(
                        _busyText,
                        style: const TextStyle(
                          fontSize: AppSizes.body,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _goalCard() {
    return _Panel(
      title: '每日目标',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dailyGoal.toString(),
            style: const TextStyle(
              fontSize: AppSizes.numberMid,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.1,
            ),
          ),
          Text(
            '题 / 天',
            style: const TextStyle(
              fontSize: AppSizes.caption,
              color: AppColors.textMinor,
            ),
          ),
          const SizedBox(height: AppSizes.gap2),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove,
                onTap: _dailyGoal <= 1 ? null : () => _saveGoal(_dailyGoal - 1),
              ),
              const SizedBox(width: AppSizes.gap),
              _StepButton(
                icon: Icons.add,
                onTap: _dailyGoal >= 20 ? null : () => _saveGoal(_dailyGoal + 1),
              ),
              const Spacer(),
              TextButton(
                onPressed: _onCustomGoal,
                child: const Text('自定义'),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.gap),
          Text(
            '默认 ' +
                AppConstants.dailyGoalDefault.toString() +
                ' 题。修改后今日页的完成度立即按新目标计算。',
            style: _tsMinor,
          ),
        ],
      ),
    );
  }

  Future<void> _onCustomGoal() async {
    final ctrl = TextEditingController(text: _dailyGoal.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义每日目标'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '每天目标题数（1 ~ 20）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final raw = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    final n = int.tryParse(raw);
    if (n == null || n < 1 || n > 20) {
      _toast('请输入 1 ~ 20 之间的整数');
      return;
    }
    await _saveGoal(n);
  }

  Widget _versionCard() {
    final installed = _installedVersion;
    final expected = AppConstants.dataVersion;
    final bool match = installed == expected;
    final String label;
    final Color color;
    if (installed == null) {
      label = '未导入';
      color = AppColors.textMinor;
    } else if (match) {
      label = '已是最新';
      color = AppColors.success;
    } else {
      label = '需要更新';
      color = AppColors.warning;
    }

    return _Panel(
      title: '数据版本',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            installed == null ? '—' : installed.toString(),
            style: const TextStyle(
              fontSize: AppSizes.numberMid,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.1,
            ),
          ),
          Text(
            '内置版本 ' + expected.toString(),
            style: _tsMinor,
          ),
          const SizedBox(height: AppSizes.gap2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.gap,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppSizes.caption,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reminderCard() {
    final timeText = _hhmm(_reminderHour, _reminderMinute);
    return _Panel(
      title: '每日提醒',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reminderEnabled ? '已开启' : '已关闭',
                      style: TextStyle(
                        fontSize: AppSizes.body,
                        fontWeight: FontWeight.w600,
                        color: _reminderEnabled
                            ? AppColors.success
                            : AppColors.textMinor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('到点提醒还有多少条没打卡', style: _tsMinor),
                  ],
                ),
              ),
              Switch(
                value: _reminderEnabled,
                onChanged: _busy ? null : _toggleReminder,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.gap2),
          Material(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              onTap: (_reminderEnabled && !_busy) ? _pickReminderTime : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.gap2,
                  vertical: AppSizes.gap,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 18,
                      color: _reminderEnabled
                          ? AppColors.gold
                          : AppColors.textMinor,
                    ),
                    const SizedBox(width: AppSizes.gap),
                    Expanded(
                      child: Text('提醒时间', style: _tsMinor),
                    ),
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: AppSizes.body,
                        fontWeight: FontWeight.w600,
                        color: _reminderEnabled
                            ? AppColors.ink
                            : AppColors.textMinor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_permGranted) ...[
            const SizedBox(height: AppSizes.gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '通知权限未开启，到点不会弹出提醒。请到系统设置里为本应用打开通知权限。',
                    style: _tsBoldWarning.copyWith(
                      fontSize: AppSizes.caption,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  Widget _dataCard() {
    final c = _counts;
    if (c == null) {
      return _Panel(
        title: '数据现状',
        child: Text('暂无数据', style: _tsMinor),
      );
    }

    final bool dataOk = c.ok;
    if (!dataOk) {
      final List<String> fails = c.failures();
      final String detail = fails.isEmpty
          ? (c.fatalError ?? '数据结构校验未通过')
          : fails.join('\n');
      return _Panel(
        title: '数据现状',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSizes.gap2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSizes.gap),
                      Expanded(
                        child: Text(
                          '数据校验未通过',
                          style: const TextStyle(
                            fontSize: AppSizes.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.gap),
                  Text(detail, style: _tsBoldWarning),
                  const SizedBox(height: AppSizes.gap),
                  Text(
                    '可先点「重试」重新读取；若仍不符，用「清空重导」按内置 JSON 重建。',
                    style: _tsMinor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.gap2),
            OutlinedButton.icon(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
            const SizedBox(height: AppSizes.gap),
            OutlinedButton.icon(
              onPressed: _busy ? null : _clearAndReseed,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('清空重导'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
              ),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[
      _Row(label: '模块', actual: c.modules, expected: AppConstants.expectedModules),
      _Row(label: '周计划', actual: c.weeks, expected: AppConstants.expectedWeeks),
      _Row(label: '学习条目', actual: c.items, expected: AppConstants.expectedItems),
      _Row(label: '复习卡片', actual: c.cards, expected: AppConstants.expectedCards),
      _Row(label: '选择题', actual: c.mcqs, expected: AppConstants.expectedMcqs),
      _Row(label: '概念词条', actual: c.concepts, expected: AppConstants.expectedConcepts),
      _Row(label: '阶段', actual: c.stages, expected: AppConstants.expectedStages),
      _Row(label: '题组', actual: c.streams, expected: AppConstants.expectedStreams),
    ];

    return _Panel(
      title: '数据现状',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前库内数量 / 内置期望数量', style: _tsMinor),
          const SizedBox(height: AppSizes.gap2),
          ...rows,
        ],
      ),
    );
  }

  Widget _actionCard() {
    return _Panel(
      title: '数据维护',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _reseed,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('重新导入数据'),
          ),
          const SizedBox(height: AppSizes.gap),
          Text(
            '按版本号比对，仅补齐缺失部分，不覆盖已有记录。',
            style: _tsMinor,
          ),
          const SizedBox(height: AppSizes.gap2),
          OutlinedButton.icon(
            onPressed: _busy ? null : _clearAndReseed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: BorderSide(
                color: AppColors.warning.withValues(alpha: 0.55),
              ),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清空并重导'),
          ),
          const SizedBox(height: AppSizes.gap),
          Text(
            '清空全部业务数据后重新导入。每日目标等设置会保留。此操作不可撤销。',
            style: _tsMinor,
          ),
          const SizedBox(height: AppSizes.gap2),
          OutlinedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('导出备份数据'),
          ),
          const SizedBox(height: AppSizes.gap),
          Text(
            '导出整份数据库副本，成功后会在对话框显示完整路径。',
            style: _tsMinor,
          ),
          const SizedBox(height: AppSizes.gap2),
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportCsv,
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('导出打卡 CSV'),
          ),
          const SizedBox(height: AppSizes.gap),
          Text(
            '导出打卡流水表，可用 Excel 打开，共九列含日期、科目与备注。',
            style: _tsMinor,
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    await _runTask('正在导出备份', () async {
      final dbPath = p.join(await getDatabasesPath(), AppDatabase.fileName);
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return '导出失败：数据库文件不存在\n' + dbPath;
      }

      Directory? targetDir;
      try {
        targetDir = await getExternalStorageDirectory();
      } catch (_) {
        targetDir = null;
      }
      targetDir ??= await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(targetDir.path, 'study_tracker_backup'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp = now.year.toString() +
          two(now.month) +
          two(now.day) +
          '_' +
          two(now.hour) +
          two(now.minute) +
          two(now.second);
      final target = p.join(backupDir.path, 'study_tracker_' + stamp + '.sqlite');

      // 先做 checkpoint 保证 -wal 内容已落主库，再复制，避免备份丢最近写入。
      final db = await ref.read(databaseProvider).database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await dbFile.copy(target);

      final size = await File(target).length();
      final kb = (size / 1024).toStringAsFixed(1);
      return '导出成功\n' + target + '\n文件大小 ' + kb + ' KB';
    });
  }

  Future<void> _exportCsv() async {
    await _runTask('正在导出打卡 CSV…', () async {
      final db = await ref.read(databaseProvider).database;
      final svc = BackupService(db);
      final file = await svc.exportCheckinsCsv();
      final size = await file.length();
      final kb = (size / 1024).toStringAsFixed(1);
      return '导出成功\n' + file.path + '\n文件大小 ' + kb + ' KB';
    });
  }

  Future<void> _autoBackupIfNeeded() async {
    try {
      final db = await ref.read(databaseProvider).database;
      final svc = BackupService(db);
      final file = await svc.autoBackupIfNeeded();
      if (file == null) return;
      await svc.pruneAutoBackups();
      if (!mounted) return;
      _toast('已自动备份本周数据');
    } catch (_) {
      // 自动备份失败不打断用户操作，静默跳过。
    }
  }

  Widget _aboutCard() {
    return _Panel(
      title: '关于',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kAppName,
            style: const TextStyle(
              fontSize: AppSizes.h3,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: AppSizes.gap),
          Text('本地离线应用，数据全部保存在本机，不联网、不上传。', style: _tsMinor),
          const SizedBox(height: AppSizes.gap),
          Text('内置数据版本 v' + AppConstants.dataVersion.toString(), style: _tsMinor),
        ],
      ),
    );
  }
}

// ---------- 样式常量 ----------

const TextStyle _tsMinor = TextStyle(
  fontSize: AppSizes.caption,
  color: AppColors.textMinor,
  height: 1.5,
);

const TextStyle _tsBoldWarning = TextStyle(
  fontSize: AppSizes.body,
  fontWeight: FontWeight.w600,
  color: AppColors.warning,
);

// ---------- 局部组件 ----------

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.gap2),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: AppSizes.h3,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: AppSizes.gap2),
          child,
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? AppColors.gold.withValues(alpha: 0.10)
          : AppColors.divider.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        side: BorderSide(
          color: enabled
              ? AppColors.gold.withValues(alpha: 0.45)
              : AppColors.divider,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? AppColors.gold : AppColors.textMinor,
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.actual,
    required this.expected,
  });

  final String label;
  final int actual;
  final int expected;

  @override
  Widget build(BuildContext context) {
    final bool ok = actual == expected;
    final color = ok ? AppColors.success : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSizes.gap),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppSizes.body,
                color: AppColors.text,
              ),
            ),
          ),
          Text(
            actual.toString() + ' / ' + expected.toString(),
            style: TextStyle(
              fontSize: AppSizes.body,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
