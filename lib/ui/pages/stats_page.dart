import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/repo/stats_repo.dart';

/// 统计页：连续天数、本周时长、12 周热力图、8 个模块进度、掌握度饼图。
/// 数据全部来自 StatsRepo 与 PlanRepo.currentStreak，页面不做任何聚合计算。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  bool _loading = true;
  String? _error;

  int _streak = 0;
  int _weekMinutes = 0;
  List<HeatCell> _heat = const <HeatCell>[];
  List<ModuleProgress> _modules = const <ModuleProgress>[];
  MasteryBuckets _mastery = const MasteryBuckets(red: 0, yellow: 0, green: 0);
  FailReasonBucket _failReasons = const FailReasonBucket(
    cannotParse: 0,
    forgot: 0,
    mixedUp: 0,
    wrongReasoning: 0,
  );
  FailReasonBucket _failHistory = const FailReasonBucket(
    cannotParse: 0,
    forgot: 0,
    mixedUp: 0,
    wrongReasoning: 0,
  );
  MasteryForecast _forecast = const MasteryForecast(
    pendingCount: 0,
    graduatedCount: 0,
    daysToFinish: 0,
    reviewsLeft: 0,
  );
  ReviewQuota _quota = const ReviewQuota(
    dueCount: 0,
    doToday: 0,
    deferred: 0,
  );
  List<MockExamRecord> _mockTrend = const <MockExamRecord>[];
  List<TimeSink> _timeSinks = const <TimeSink>[];
  /// 错因卡视图：false = 当前，true = 趋势。
  bool _reasonTrendView = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 一次性拉全部统计数据，成功后 setState 统一落地。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final planRepo = ref.read(planRepoProvider);
      final statsRepo = ref.read(statsRepoProvider);
      final streak = await planRepo.currentStreak();
      final week = await statsRepo.weekMinutes();
      final heat = await statsRepo.heatmap(weeks: 12);
      final modules = await statsRepo.moduleProgress();
      final mastery = await statsRepo.masteryBuckets();
      final failReasons = await statsRepo.failReasonBuckets();
      final failHistory = await statsRepo.failReasonHistory();
      final forecast = await statsRepo.masteryForecast();
      final quota = await statsRepo.todayQuota();
      final mockTrend = await statsRepo.mockTrend();
      final timeSinks = await statsRepo.timeSinks();
      if (!mounted) return;
      setState(() {
        _streak = streak;
        _weekMinutes = week;
        _heat = heat;
        _modules = modules;
        _mastery = mastery;
        _failReasons = failReasons;
        _failHistory = failHistory;
        _forecast = forecast;
        _quota = quota;
        _mockTrend = mockTrend;
        _timeSinks = timeSinks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '统计数据读取失败';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool wide = width >= AppConstants.breakpointNarrow;

    if (_loading) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: '正在加载…',
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('统计')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_error!, style: const TextStyle(color: AppColors.warning)),
              const SizedBox(height: AppSizes.gap2),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.gap2,
            AppSizes.gap,
            AppSizes.gap2,
            AppSizes.gap3,
          ),
          children: <Widget>[
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _StreakCard(streak: _streak)),
                  const SizedBox(width: AppSizes.gap2),
                  Expanded(child: _WeekCard(minutes: _weekMinutes)),
                ],
              )
            else ...<Widget>[
              _StreakCard(streak: _streak),
              const SizedBox(height: AppSizes.gap2),
              _WeekCard(minutes: _weekMinutes),
            ],
            const SizedBox(height: AppSizes.gap2),
            _HeatmapCard(cells: _heat),
            const SizedBox(height: AppSizes.gap2),
            _ModuleCard(list: _modules),
            const SizedBox(height: AppSizes.gap2),
            _MasteryCard(buckets: _mastery),
            const SizedBox(height: AppSizes.gap2),
            _ForecastCard(forecast: _forecast),
            const SizedBox(height: AppSizes.gap2),
            _QuotaCard(quota: _quota),
            const SizedBox(height: AppSizes.gap2),
            _FailReasonCard(
              current: _failReasons,
              history: _failHistory,
              trendView: _reasonTrendView,
              onToggle: (bool v) => setState(() => _reasonTrendView = v),
            ),
            if (_mockTrend.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSizes.gap2),
              _MockTrendCard(records: _mockTrend),
            ],
            if (_timeSinks.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSizes.gap2),
              _TimeSinkCard(items: _timeSinks),
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一卡片外壳：白底、圆角 20、唯一阴影。
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

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
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppSizes.h3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSizes.gap2),
          child,
        ],
      ),
    );
  }
}

/// 连续天数卡片。
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return _StatCard(
      title: '连续天数',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            '$streak',
            style: const TextStyle(
              fontSize: AppSizes.numberLarge,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.0,
            ),
          ),
          const SizedBox(width: AppSizes.gap),
          const Text(
            '天',
            style: TextStyle(fontSize: AppSizes.body, color: AppColors.textMinor),
          ),
        ],
      ),
    );
  }
}

/// 本周时长卡片：数字 + 进度条（分母 weekGoalMinutes）。
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final double ratio = AppConstants.weekGoalMinutes <= 0
        ? 0.0
        : (minutes / AppConstants.weekGoalMinutes).clamp(0.0, 1.0);
    return _StatCard(
      title: '本周时长',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '$minutes',
                style: const TextStyle(
                  fontSize: AppSizes.numberLarge,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Text(
                '分钟 / 目标 ${AppConstants.weekGoalMinutes}',
                style: const TextStyle(
                  fontSize: AppSizes.caption,
                  color: AppColors.textMinor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.gap2),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.gap),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

/// 12 周热力图：列 = 周，行 = 周一至周日。
/// heatmap() 返回长度 weeks*7，索引 i 对应第 i~/7 列、第 i%7 行。
class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.cells});

  final List<HeatCell> cells;

  /// 根据当天打卡条数取色阶，0 条用分隔线色。
  static Color _levelColor(int count) {
    if (count <= 0) return AppColors.divider;
    if (count == 1) return AppColors.gold.withValues(alpha: 0.35);
    if (count <= 3) return AppColors.gold.withValues(alpha: 0.65);
    return AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) {
      return const _StatCard(
        title: '最近 12 周',
        child: Text(
          '暂无数据',
          style: TextStyle(fontSize: AppSizes.caption, color: AppColors.textMinor),
        ),
      );
    }

    final int weeks = (cells.length / AppConstants.daysPerWeek).ceil();
    // 按列切分：每列 7 个格子（周一 → 周日）。
    final List<List<HeatCell>> columns = <List<HeatCell>>[];
    for (int w = 0; w < weeks; w++) {
      final int start = w * AppConstants.daysPerWeek;
      final int end = (start + AppConstants.daysPerWeek).clamp(0, cells.length);
      columns.add(cells.sublist(start, end));
    }

    return _StatCard(
      title: '最近 12 周',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int w = 0; w < columns.length; w++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Column(
                      children: <Widget>[
                        for (final HeatCell c in columns[w])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Tooltip(
                              message: '${c.day.month}/${c.day.day} · ${c.count} 条',
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _levelColor(c.count),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.gap),
          Row(
            children: <Widget>[
              const Text(
                '少',
                style: TextStyle(fontSize: AppSizes.caption, color: AppColors.textMinor),
              ),
              const SizedBox(width: 4),
              for (final int v in <int>[0, 1, 2, 4])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _levelColor(v),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const Text(
                '多',
                style: TextStyle(fontSize: AppSizes.caption, color: AppColors.textMinor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 8 个模块进度条。
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.list});

  final List<ModuleProgress> list;

  /// modules.color 是原始字符串，解析失败统一回落金色。
  static Color _parseColor(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return AppColors.gold;
    final String hex = s.startsWith('#') ? s.substring(1) : s;
    if (hex.length == 6) {
      final int? v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    if (hex.length == 8) {
      final int? v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(v);
    }
    return AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    return _StatCard(
      title: '模块进度',
      child: Column(
        children: <Widget>[
          for (int i = 0; i < list.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == list.length - 1 ? 0 : AppSizes.gap2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          list[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppSizes.body,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Text(
                        '${list[i].doneItems}/${list[i].totalItems}',
                        style: const TextStyle(
                          fontSize: AppSizes.caption,
                          color: AppColors.textMinor,
                        ),
                      ),
                      const SizedBox(width: AppSizes.gap),
                      Text(
                        '${(list[i].ratio * 100).round()}%',
                        style: const TextStyle(
                          fontSize: AppSizes.caption,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.gap),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSizes.gap),
                    child: LinearProgressIndicator(
                      value: list[i].ratio,
                      minHeight: 6,
                      backgroundColor: AppColors.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _parseColor(list[i].color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 掌握度红黄绿饼图。
class _MasteryCard extends StatelessWidget {
  const _MasteryCard({required this.buckets});

  final MasteryBuckets buckets;

  @override
  Widget build(BuildContext context) {
    final int total = buckets.total;
    if (total <= 0) {
      return const _StatCard(
        title: '掌握度',
        child: Text(
          '暂无概念数据',
          style: TextStyle(fontSize: AppSizes.caption, color: AppColors.textMinor),
        ),
      );
    }

    final List<_Slice> slices = <_Slice>[
      _Slice('已掌握', buckets.green, AppColors.success),
      _Slice('半熟', buckets.yellow, AppColors.gold),
      _Slice('薄弱', buckets.red, AppColors.warning),
    ];

    return _StatCard(
      title: '掌握度',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 120,
            height: 120,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 28,
                sections: <PieChartSectionData>[
                  for (final _Slice s in slices)
                    if (s.value > 0)
                      PieChartSectionData(
                        value: s.value.toDouble(),
                        color: s.color,
                        radius: 22,
                        showTitle: false,
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSizes.gap3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '共 $total 个概念',
                  style: const TextStyle(
                    fontSize: AppSizes.caption,
                    color: AppColors.textMinor,
                  ),
                ),
                const SizedBox(height: AppSizes.gap2),
                for (final _Slice s in slices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.gap),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: AppSizes.gap),
                        Expanded(
                          child: Text(
                            s.label,
                            style: const TextStyle(
                              fontSize: AppSizes.body,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Text(
                          '${s.value} · ${(s.value / total * 100).round()}%',
                          style: const TextStyle(
                            fontSize: AppSizes.caption,
                            color: AppColors.textMinor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 饼图单块数据。
/// 薄弱类型分布（缺口③）：当前快照 + 30 天趋势双视图。
///
/// 「当前」看每题最新标的是什么——现在弱在哪。
/// 「趋势」看最近 30 天标了多少次——学习方法改了没有。
/// 两个问题只能用两份数据回答，所以分两个视图。
class _FailReasonCard extends StatelessWidget {
  const _FailReasonCard({
    required this.current,
    required this.history,
    required this.trendView,
    required this.onToggle,
  });

  final FailReasonBucket current;
  final FailReasonBucket history;
  final bool trendView;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FailReasonBucket b = trendView ? history : current;
    final bool empty = b.total == 0;

    return _StatCard(
      title: '薄弱类型',
      trailing: SegmentedButton<bool>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: theme.textTheme.labelSmall,
        ),
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(value: false, label: Text('当前')),
          ButtonSegment<bool>(value: true, label: Text('30天')),
        ],
        selected: <bool>{trendView},
        onSelectionChanged: (Set<bool> v) => onToggle(v.first),
      ),
      child: empty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                trendView
                    ? '最近 30 天没有错因记录。'
                    : '还没有错因记录。答错时选一下「错在哪」，这里就会告诉你反复死在哪儿。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ReasonBar(
                  label: '看不懂题',
                  count: b.cannotParse,
                  total: b.total,
                  color: const Color(0xFF8E8E93),
                ),
                const SizedBox(height: 10),
                _ReasonBar(
                  label: '知识点没记住',
                  count: b.forgot,
                  total: b.total,
                  color: const Color(0xFF4D6BFE),
                ),
                const SizedBox(height: 10),
                _ReasonBar(
                  label: '记混了',
                  count: b.mixedUp,
                  total: b.total,
                  color: const Color(0xFFFF9500),
                ),
                const SizedBox(height: 10),
                _ReasonBar(
                  label: '想陷了',
                  count: b.wrongReasoning,
                  total: b.total,
                  color: const Color(0xFFFF3B30),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    trendView
                        ? '最近 30 天共标了 ${b.total} 次错因，最多的是「${b.dominant}」。'
                        : '共 ${b.total} 道题标了错因，最多的是「${b.dominant}」。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReasonBar extends StatelessWidget {
  const _ReasonBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double ratio = total == 0 ? 0 : count / total;
    final int pct = (ratio * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              '$count 题  $pct%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// 掌握度预测（第 6 项）：还要多久才能全部变绿。
///
/// 按 SM-2 现有参数往后推，假设之后全对、每天复习量不超过配额。
/// 这是乐观下限，页面上必须标清楚，不然会给人假希望。
class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast});

  final MasteryForecast forecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int pct = (forecast.progress * 100).round();

    return _StatCard(
      title: '还要多久',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${forecast.daysToFinish}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '天',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '还剩 ${forecast.reviewsLeft} 次复习',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: forecast.progress,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已毕业 ${forecast.graduatedCount} / ${forecast.totalCount} 题（$pct%）· 按全对推算，实际会更久',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日复习配额（第 7 项）：把断更回来的积压炸弹拆开。
class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});

  final ReviewQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool overwhelming = quota.deferred > 0 && quota.deferred > quota.doToday;

    return _StatCard(
      title: '今日复习',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${quota.doToday}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ ${quota.dueCount} 题到期',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            quota.deferred == 0
                ? '今天到期全部在配额内，一次做完。'
                : (overwhelming
                    ? '积压较多（${quota.deferred} 题顺延）。别慌，一天做完的意义就是把断掉的链接上；顺延的明天排在最前面。'
                    : '还有 ${quota.deferred} 题顺延到明天，明天会优先排。'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 模考成绩趋势（第 5 项）：一条折线看进步。
class _MockTrendCard extends StatelessWidget {
  const _MockTrendCard({required this.records});

  final List<MockExamRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final MockExamRecord last = records.last;
    final MockExamRecord? prev = records.length >= 2 ? records[records.length - 2] : null;
    final int delta = prev == null ? 0 : last.percent - prev.percent;

    return _StatCard(
      title: '模考成绩',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${last.percent}%',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  prev == null
                      ? '首次模考'
                      : (delta > 0
                          ? '↑ $delta%'
                          : (delta < 0 ? '↓ ${-delta}%' : '持平')),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: delta > 0
                        ? AppColors.success
                        : (delta < 0 ? AppColors.warning : theme.colorScheme.onSurfaceVariant),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '共 ${records.length} 次',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final r in records)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          Container(
                            height: (r.ratio * 60).clamp(2, 60),
                            decoration: BoxDecoration(
                              color: r.ratio >= 0.8
                                  ? AppColors.success
                                  : (r.ratio >= 0.6
                                      ? const Color(0xFFFF9500)
                                      : AppColors.warning),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '柱高 = 正确率，绿柱 = 过线（80%）。最近一次：${last.rightCount}/${last.total}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间黑洞（第 8 项）：花时间最多、但该周选择题正确率还没上来的点。
class _TimeSinkCard extends StatelessWidget {
  const _TimeSinkCard({required this.items});

  final List<TimeSink> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StatCard(
      title: '时间黑洞',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '这几处花的时间最多，但对应周次的正确率还没到 80%。这是你真正卡住的地方。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...<Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: items[i].level == 0
                        ? AppColors.warning
                        : const Color(0xFFFF9500),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${items[i].minutes}分 · 正确率${(items[i].accuracy * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (i != items.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}
