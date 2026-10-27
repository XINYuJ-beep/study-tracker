import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/db/tables.dart' show Item;
import '../../data/repo/plan_repo.dart';
import '../../data/repo/checkin_repo.dart';
import '../../data/repo/question_repo.dart';
import '../../data/repo/concept_repo.dart';
import '../widgets/checkin_sheet.dart';

/// 今日页：今日进度的唯一入口。
///
/// 对应 SPEC 3.1 + 4.1 + 4.6，功能闭环：
/// 1. 日期 / 问候语 / 当前模块名；
/// 2. 进度环：今日已完成条目 / 今日目标条目（默认 3，settings 可改）；
/// 3. 推荐列表：队列最前 6 条，累计分钟不超过 90 x 1.2 = 108；
/// 4. 打卡：弹面板可改用时、写备注，默认取 items.minutes；
/// 5. 撤销：SnackBar 5 秒内可撤，撤销走物理删除；
/// 6. 到期复习条：有 N 张卡待复习，点击去测试页；
/// 7. 底部：今日用时 + 完成条数 + 连续天数；
/// 8. 空态：不撒花不弹窗，一句话 + 今日用时。
///
/// 数据全部走 repo，页面里不写 SQL。
/// 跨天以凌晨 4 点为界，统一用 effectiveToday()。
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  /// 今天（4 点日界）
  DateTime _today = effectiveToday();

  /// 今日推荐条目
  List<Item> _items = const <Item>[];

  /// 今日已完成条数
  int _doneCount = 0;

  /// 今日目标条数（settings 覆盖，默认 3）
  int _dailyGoal = AppConstants.dailyGoalDefault;

  /// 今日累计用时（分钟）
  int _todayMinutes = 0;

  /// 连续打卡天数
  int _streak = 0;

  /// 到期复习张数
  int _dueReview = 0;
  /// 到期复习概念数
  int _dueConcept = 0;

  /// 当前模块标题（取推荐队列首条所属周所属模块，取不到则空）
  String _currentModule = '';

  /// 首次加载中
  bool _loading = true;

  /// 正在提交打卡请条目的 id ，防连点
  final Set<String> _submitting = <String>{};

  /// 已打卡且仍在撤销窗口内的条目 id -> 定时器
  final Map<String, Timer> _undoTimers = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    for (final Timer t in _undoTimers.values) {
      t.cancel();
    }
    _undoTimers.clear();
    super.dispose();
  }

  /// 统一刷新：一次拉齐页面需要的全部数据。
  Future<void> _load() async {
    final PlanRepo planRepo = ref.read(planRepoProvider);
    final CheckinRepo checkinRepo = ref.read(checkinRepoProvider);
    final QuestionRepo questionRepo = ref.read(questionRepoProvider);
    final ConceptRepo conceptRepo = ref.read(conceptRepoProvider);

    // 每次刷新重算「今天」，防止页面挂过夜后日期不更新
    final DateTime today = effectiveToday();

    try {
      final List<Item> items = await planRepo.todayRecommendation();
      final int doneCount = await checkinRepo.todayCount();
      final int minutes = await checkinRepo.todayMinutes();
      final int streak = await planRepo.currentStreak();
      final int due = await questionRepo.dueReviewCount();
      final int dueConcept = await conceptRepo.dueConceptCount();
      final int goal = await _readDailyGoal();
      final String module = await _moduleNameOf(items);

      if (!mounted) return;
      setState(() {
        _today = today;
        _items = items;
        _doneCount = doneCount;
        _todayMinutes = minutes;
        _streak = streak;
        _dueReview = due;
        _dueConcept = dueConcept;
        _dailyGoal = goal;
        _currentModule = module;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('数据加载失败：$e');
    }
  }

  /// 读每日目标条数。settings 里没有就用默认 3。
  Future<int> _readDailyGoal() async {
    try {
      final db = ref.read(databaseProvider);
      final rows = await db.query(
        'app_settings',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>['daily_goal'],
        limit: 1,
      );
      if (rows.isEmpty) return AppConstants.dailyGoalDefault;
      final int? v = int.tryParse((rows.first['value'] as String?) ?? '');
      if (v == null || v <= 0) return AppConstants.dailyGoalDefault;
      return v;
    } catch (_) {
      return AppConstants.dailyGoalDefault;
    }
  }

  /// 取推荐队列首条所属模块的标题。
  ///
  /// weeks 表没有 module 字段，模块归属只能按 modules.weeks 顺序累加
  /// 推出周区间，再用 item.week 落入区间反查（与 question_repo 同口径）。
  Future<String> _moduleNameOf(List<Item> items) async {
    if (items.isEmpty) {
      return '';
    }
    try {
      final db = ref.read(databaseProvider);
      final rows = await db.query(
        'modules',
        columns: <String>['id', 'title', 'weeks'],
        orderBy: 'id ASC',
      );
      int cursor = 1;
      final int week = items.first.week;
      for (final r in rows) {
        final int span = (r['weeks'] as int?) ?? 0;
        if (week >= cursor && week < cursor + span) {
          return (r['title'] as String?) ?? '';
        }
        cursor += span;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 点开一条推荐：弹打卡面板，可改用时、写备注。
  Future<void> _onTapItem(Item item) async {
    if (_submitting.contains(item.id)) return;
    final CheckinInput? input = await showModalBottomSheet<CheckinInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => CheckinSheet(
        item: item,
        defaultMinutes: item.minutes,
      ),
    );
    if (input == null) return;
    await _doCheckIn(item, input.minutes, input.note);
  }

  /// 省事模式：直接打卡，用预估用时。
  Future<void> _quickCheckIn(Item item) async {
    if (_submitting.contains(item.id)) return;
    await _doCheckIn(item, item.minutes, '');
  }

  /// 执行打卡 + 弹 5 秒撤销。
  Future<void> _doCheckIn(Item item, int minutes, String note) async {
    setState(() => _submitting.add(item.id));
    final checkinRepo = ref.read(checkinRepoProvider);
    try {
      final int actual = await checkinRepo.checkIn(
        item.id,
        _today,
        minutes: minutes,
        note: note,
      );
      if (!mounted) return;
      setState(() => _submitting.remove(item.id));
      await _load();
      if (!mounted) return;
      _scheduleUndo(item, actual);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting.remove(item.id));
      _toast('打卡失败：$e');
    }
  }

  /// 弹出 5 秒可撤销的 SnackBar。
  void _scheduleUndo(Item item, int minutes) {
    _undoTimers[item.id]?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已打卡 · 用时 $minutes 分钟'),
        duration: const Duration(seconds: AppConstants.undoWindowSeconds),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            _undoTimers[item.id]?.cancel();
            _undoTimers.remove(item.id);
            final checkinRepo = ref.read(checkinRepoProvider);
            await checkinRepo.undo(item.id, _today);
            if (!mounted) return;
            await _load();
          },
        ),
      ),
    );
    final timer = Timer(
      const Duration(seconds: AppConstants.undoWindowSeconds),
      () => _undoTimers.remove(item.id),
    );
    _undoTimers[item.id] = timer;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dual = MediaQuery.sizeOf(context).width >= AppConstants.breakpointDual;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final Widget header = _TodayHeader(
      today: _today,
      moduleName: _currentModule,
      onSettings: () => context.go('/settings'),
      onRefresh: _load,
    );

    final Widget ring = _ProgressRing(
      done: _doneCount,
      goal: _dailyGoal,
      minutes: _todayMinutes,
    );

    final Widget body = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        header,
        const SizedBox(height: 24),
        if (dual)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ring,
              const SizedBox(width: 32),
              Expanded(child: _TodaySummary(
                done: _doneCount,
                goal: _dailyGoal,
                minutes: _todayMinutes,
                streak: _streak,
              )),
            ],
          )
        else ...<Widget>[
          Center(child: ring),
          const SizedBox(height: 24),
          _TodaySummary(
            done: _doneCount,
            goal: _dailyGoal,
            minutes: _todayMinutes,
            streak: _streak,
          ),
        ],
        const SizedBox(height: 24),
        if (_dueReview > 0 || _dueConcept > 0) ...<Widget>[
          _ReviewBanner(
            cardCount: _dueReview,
            conceptCount: _dueConcept,
            onTap: () => context.go('/qa'),
          ),
          const SizedBox(height: 16),
        ],
        _SectionTitle(
          title: '今日推荐',
          trailing: _items.isEmpty ? null : '共 ${_items.length} 条',
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty)
          _EmptyState(doneCount: _doneCount, minutes: _todayMinutes)
        else
          ..._items.map(
            (Item item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ItemCard(
                item: item,
                busy: _submitting.contains(item.id),
                onTap: () => _onTapItem(item),
                onQuick: () => _quickCheckIn(item),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

/// 顶部：日期 + 问候语 + 当前模块 + 设置入口。
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.today,
    required this.moduleName,
    required this.onSettings,
    required this.onRefresh,
  });

  final DateTime today;
  final String moduleName;
  final VoidCallback onSettings;
  final Future<void> Function() onRefresh;

  static const List<String> _weekNames = <String>[
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  String get _greeting {
    final int h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String weekday = _weekNames[today.weekday - 1];
    final String dateText = '${today.month} 月 ${today.day} 日 · $weekday';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                dateText,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                _greeting,
                style: theme.textTheme.headlineLarge,
              ),
              if (moduleName.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '当前模块·$moduleName',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: () => onRefresh(),
        ),
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
        ),
      ],
    );
  }
}

/// 进度环：今日已完成 / 今日目标，圆心显示数字。
///
/// 自绘，不依赖 fl_chart（该包只给统计页用）。
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.done,
    required this.goal,
    required this.minutes,
  });

  final int done;
  final int goal;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final int safeGoal = goal <= 0 ? 1 : goal;
    final double raw = done / safeGoal;
    final double ratio = raw.clamp(0.0, 1.0).toDouble();
    final bool finished = done >= safeGoal;
    final Color arcColor = finished
        ? AppColors.success
        : (dark ? AppColors.darkPrimary : AppColors.ink);

    return Semantics(
      label: '今日已完成 $done 条，目标 $safeGoal 条，共 $minutes 分钟',
      child: SizedBox(
        width: 168,
        height: 168,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox(
              width: 168,
              height: 168,
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 10,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(arcColor),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '$done',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: arcColor,
                      ),
                    ),
                    Text(
                      ' / $safeGoal',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '条今日已完成',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 三个数字：今日用时 / 完成条数 / 连续天数。
class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.done,
    required this.goal,
    required this.minutes,
    required this.streak,
  });

  final int done;
  final int goal;
  final int minutes;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _stat(theme, '今日用时', '$minutes', '分钟'),
        _stat(theme, '已完成', '$done', '条'),
        _stat(theme, '连续', '$streak', '天'),
      ],
    );
  }

  Widget _stat(ThemeData theme, String label, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Text(unit, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 区块标题行。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        if (trailing != null)
          Text(trailing!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 到期复习提示条：卡片与概念两路到期合并展示，点击进测试页。
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({
    required this.cardCount,
    required this.conceptCount,
    required this.onTap,
  });

  final int cardCount;
  final int conceptCount;
  final VoidCallback onTap;

  /// 两路到期合并成一句人话，空的一路不显示。
  String get _label {
    final List<String> parts = <String>[];
    if (cardCount > 0) {
      parts.add(cardCount.toString() + ' 张卡');
    }
    if (conceptCount > 0) {
      parts.add(conceptCount.toString() + ' 个概念');
    }
    if (parts.isEmpty) {
      return '没有待复习内容';
    }
    return '有 ' + parts.join(' + ') + ' 待复习';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.gold.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              const Icon(Icons.autorenew, size: 20, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '去复习',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.gold),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态：不撒花不弹窗，只一句文案 + 今日用时。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.doneCount, required this.minutes});

  final int doneCount;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String line = doneCount > 0
        ? '今天的都做完了，去休息吧。'
        : '今天没有待办条目。';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(line, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            '今日用时 $minutes 分钟',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 推荐条目卡片。
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onQuick,
  });

  final Item item;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onQuick;

  static const List<String> _dayNames = <String>[
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String dayName = (item.day >= 1 && item.day <= 7)
        ? _dayNames[item.day - 1]
        : '第 ${item.day} 天';

    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: '打卡',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.radio_button_unchecked),
                      onPressed: onQuick,
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _tag(theme, '第 ${item.week} 周'),
                        const SizedBox(width: 6),
                        _tag(theme, dayName),
                        const SizedBox(width: 6),
                        _tag(theme, '${item.minutes} 分钟'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.watch,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '练：${item.practice}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.output.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '产出：${item.output}',
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.divider.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}
