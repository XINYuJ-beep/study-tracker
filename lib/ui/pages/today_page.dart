import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/tables.dart' show Item;
import '../../data/repo/plan_repo.dart';

/// 今日页：M1 之后第一个真正能用的页面。
///
/// 功能闭环：
/// 1. 显示今天日期（走 4 点日界，与全项目一致）；
/// 2. 显示今日已完成条数 + 连续打卡天数；
/// 3. 列出今天推荐的学习条目，点勾选框打卡；
/// 4. 打完卡列表自动刷新（已完成的不再出现在推荐里）；
/// 5. 空态提示；
/// 6. 手动刷新按钮（兜底）。
///
/// 数据来源全部走 repo，页面里不写任何 SQL。
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

  /// 连续打卡天数
  int _streak = 0;

  /// 首次加载中
  bool _loading = true;

  /// 正在提交打卡的条目 id（防止连点重复提交，也用于单行 loading）
  final Set<String> _submitting = <String>{};

  @override
  void initState() {
    super.initState();
    // initState 里不能直接 await，用 microtask 把异步甩出去
    Future<void>.microtask(_load);
  }

  /// 统一刷新：一次把三份数据都取回来。
  Future<void> _load() async {
    final planRepo = ref.read(planRepoProvider);
    final checkinRepo = ref.read(checkinRepoProvider);

    // 每次刷新都重新算一次「今天」，防止页面挂过夜后日期不更新
    final DateTime today = effectiveToday();

    try {
      final List<Item> items = await planRepo.todayRecommendation();
      final int doneCount = await checkinRepo.todayCount();
      final int streak = await planRepo.currentStreak();

      if (!mounted) return;
      setState(() {
        _today = today;
        _items = items;
        _doneCount = doneCount;
        _streak = streak;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('数据加载失败：$e');
    }
  }

  /// 点击某一条：切换打卡状态，然后整页重刷。
  Future<void> _onToggle(Item item) async {
    if (_submitting.contains(item.id)) return;
    setState(() => _submitting.add(item.id));

    final checkinRepo = ref.read(checkinRepoProvider);

    try {
      final bool nowDone = await checkinRepo.toggle(item.id, _today);
      if (!mounted) return;
      setState(() => _submitting.remove(item.id));
      _toast(nowDone ? '已完成：${item.practice}' : '已撤销：${item.practice}');
      // 打完卡重新拉一遍：已完成的不再出现在推荐里，统计也跟着变
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting.remove(item.id));
      _toast('打卡失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: <Widget>[
                  _DateHeader(today: _today),
                  const SizedBox(height: 8),
                  _StatsLine(doneCount: _doneCount, streak: _streak),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    _EmptyState(doneCount: _doneCount)
                  else
                    ..._items.map(
                      (Item item) => _ItemTile(
                        item: item,
                        busy: _submitting.contains(item.id),
                        onTap: () => _onToggle(item),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// 顶部日期行
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.today});

  final DateTime today;

  static const List<String> _weekNames = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final String weekday = _weekNames[today.weekday - 1];
    final String text = '${today.year}年${today.month}月${today.day}日  $weekday';
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}

/// 统计行：今日已完成 X 条 · 累计 N 天
class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.doneCount, required this.streak});

  final int doneCount;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '今日已完成 $doneCount 条 · 累计 $streak 天',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 空态
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.doneCount});

  final int doneCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            doneCount > 0 ? '今天的都完成了，去休息吧' : '今天没有待办条目',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// 单条推荐
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.busy,
    required this.onTap,
  });

  final Item item;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: '标记完成',
                icon: const Icon(Icons.radio_button_unchecked),
                onPressed: onTap,
              ),
        title: Text(
          item.practice,
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '第 ${item.week} 周 · 第 ${item.day} 天 · ${item.minutes} 分钟\n'
            '看：${item.watch}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        isThreeLine: true,
        onTap: busy ? null : onTap,
      ),
    );
  }
}