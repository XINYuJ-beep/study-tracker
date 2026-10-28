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
      if (!mounted) return;
      setState(() {
        _streak = streak;
        _weekMinutes = week;
        _heat = heat;
        _modules = modules;
        _mastery = mastery;
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
          ],
        ),
      ),
    );
  }
}

/// 统一卡片外壳：白底、圆角 20、唯一阴影。
class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.child});

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
        children: <Widget>[
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
class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}
