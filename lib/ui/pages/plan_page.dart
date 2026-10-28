import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/db/tables.dart';
import '../../data/repo/plan_repo.dart' show effectiveToday;
import '../widgets/checkin_sheet.dart';

/// 计划页。
///
/// 三级树：模块 → 周 → 条目。
/// 宽屏（>= [AppConstants.breakpointDual]）双栏：左树右详情。
/// 窄屏单栏：点条目 push 独立详情页。
class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({super.key});

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  bool _loading = true;
  String? _error;

  List<Module> _modules = const <Module>[];
  List<Week> _weeks = const <Week>[];
  List<Item> _items = const <Item>[];
  Set<String> _doneIds = <String>{};

  /// 当前选中条目（宽屏右栏用）。
  Item? _selected;

  /// 正在提交的条目 id，避免重复点击。
  final Set<String> _submitting = <String>{};

  /// 撤销计时器，按条目 id 归位。
  final Map<String, Timer> _undoTimers = <String, Timer>{};

  /// 今天（按 4 点日界的业务日）。
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _today = effectiveToday();
    _load();
  }

  @override
  void dispose() {
    for (final Timer t in _undoTimers.values) {
      t.cancel();
    }
    _undoTimers.clear();
    super.dispose();
  }

  Future<void> _load() async {
    final planRepo = ref.read(planRepoProvider);
    final checkinRepo = ref.read(checkinRepoProvider);
    try {
      final results = await Future.wait(<Future<Object?>>[
        planRepo.allModules(),
        planRepo.allWeeks(),
        planRepo.allItems(),
        checkinRepo.doneIdsOfDay(_today),
      ]);
      if (!mounted) return;
      setState(() {
        _modules = results[0] as List<Module>;
        _weeks = results[1] as List<Week>;
        _items = results[2] as List<Item>;
        _doneIds = results[3] as Set<String>;
        _loading = false;
        _error = null;

        // 选中项丢了（或首次进入）就落到第一个条目。
        if (_items.isEmpty) {
          _selected = null;
        } else {
          final String? selId = _selected?.id;
          Item? again;
          if (selId != null) {
            for (final Item it in _items) {
              if (it.id == selId) {
                again = it;
                break;
              }
            }
          }
          _selected = again ?? _items.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  // ---------------- 打卡动作 ----------------

  Future<void> _openCheckinSheet(Item item) async {
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

  Future<void> _doCheckIn(Item item, int minutes, String note) async {
    if (_submitting.contains(item.id)) return;
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

  /// 已打卡的条目再点一次：走撤销（物理删除当行）。
  Future<void> _undoCheckIn(Item item) async {
    if (_submitting.contains(item.id)) return;
    setState(() => _submitting.add(item.id));
    final checkinRepo = ref.read(checkinRepoProvider);
    try {
      await checkinRepo.undo(item.id, _today);
      if (!mounted) return;
      setState(() => _submitting.remove(item.id));
      await _load();
      if (!mounted) return;
      _toast('已取消打卡 · ${item.watch}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting.remove(item.id));
      _toast('取消失败：$e');
    }
  }

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

  // ---------------- 数据装配 ----------------

  /// 模块 → 它覆盖的周号区间。
  /// Module.weeks 是「该模块占几周」，按 id 升序累加即得区间。
  Map<String, List<int>> _weekRangeByModule() {
    final Map<String, List<int>> out = <String, List<int>>{};
    int cursor = 1;
    for (final Module m in _modules) {
      final int span = m.weeks <= 0 ? 0 : m.weeks;
      out[m.id] = <int>[for (int i = 0; i < span; i++) cursor + i];
      cursor += span;
    }
    return out;
  }

  /// 周号 → 该周条目，按 day 升序。
  Map<int, List<Item>> _itemsByWeek() {
    final Map<int, List<Item>> out = <int, List<Item>>{};
    for (final Item it in _items) {
      out.putIfAbsent(it.week, () => <Item>[]).add(it);
    }
    for (final List<Item> list in out.values) {
      list.sort((Item a, Item b) => a.day.compareTo(b.day));
    }
    return out;
  }

  /// 周号 → 已完成条目数。
  Map<int, int> _doneCountByWeek() {
    final Map<int, int> out = <int, int>{};
    for (final Item it in _items) {
      if (_doneIds.contains(it.id)) {
        out[it.week] = (out[it.week] ?? 0) + 1;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('加载失败：$_error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool dual = constraints.maxWidth >= AppConstants.breakpointDual;
        return _buildBody(context, dual: dual);
      },
    );
  }

  Widget _buildBody(BuildContext context, {required bool dual}) {
    final ThemeData theme = Theme.of(context);
    final Map<String, List<int>> ranges = _weekRangeByModule();
    final Map<int, List<Item>> byWeek = _itemsByWeek();
    final Map<int, int> doneByWeek = _doneCountByWeek();

    final Widget tree = _TreePane(
      modules: _modules,
      weeks: _weeks,
      weekRangeByModule: ranges,
      itemsByWeek: byWeek,
      doneCountByWeek: doneByWeek,
      doneIds: _doneIds,
      selectedId: _selected?.id,
      submitting: _submitting,
      onTapItem: (Item item) {
        if (dual) {
          setState(() => _selected = item);
        } else {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext ctx) => _DetailPage(
                item: item,
                done: _doneIds.contains(item.id),
                onCheckIn: (int minutes, String note) async {
                  await _doCheckIn(item, minutes, note);
                },
                onUndo: () async {
                  await _undoCheckIn(item);
                },
              ),
            ),
          );
        }
      },
    );

    if (dual) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: AppConstants.leftPaneWidth, child: tree),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: _selected == null
                    ? const _EmptyDetail()
                    : _DetailPane(
                        item: _selected!,
                        done: _doneIds.contains(_selected!.id),
                        submitting: _submitting.contains(_selected!.id),
                        onTap: () {
                          final Item item = _selected!;
                          if (_doneIds.contains(item.id)) {
                            _undoCheckIn(item);
                          } else {
                            _openCheckinSheet(item);
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(child: tree),
    );
  }
}

/// ----------------------------------------------------------------
/// 左栏：三级树
/// ----------------------------------------------------------------
class _TreePane extends StatelessWidget {
  const _TreePane({
    required this.modules,
    required this.weeks,
    required this.weekRangeByModule,
    required this.itemsByWeek,
    required this.doneCountByWeek,
    required this.doneIds,
    required this.selectedId,
    required this.submitting,
    required this.onTapItem,
  });

  final List<Module> modules;
  final List<Week> weeks;
  final Map<String, List<int>> weekRangeByModule;
  final Map<int, List<Item>> itemsByWeek;
  final Map<int, int> doneCountByWeek;
  final Set<String> doneIds;
  final String? selectedId;
  final Set<String> submitting;
  final ValueChanged<Item> onTapItem;

  static const List<String> _dayNames = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  String _dayName(int day) =>
      (day >= 1 && day <= 7) ? _dayNames[day - 1] : '第 $day 天';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (modules.isEmpty) {
      return Center(
        child: Text('暂无计划数据', style: theme.textTheme.bodyMedium),
      );
    }

    final Map<int, Week> weekByNumber = <int, Week>{
      for (final Week w in weeks) w.week: w,
    };

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        for (final Module m in modules)
          _ModuleTile(
            module: m,
            weekNumbers: weekRangeByModule[m.id] ?? const <int>[],
            weekByNumber: weekByNumber,
            itemsByWeek: itemsByWeek,
            doneCountByWeek: doneCountByWeek,
            doneIds: doneIds,
            selectedId: selectedId,
            submitting: submitting,
            onTapItem: onTapItem,
            dayNameOf: _dayName,
          ),
      ],
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.weekNumbers,
    required this.weekByNumber,
    required this.itemsByWeek,
    required this.doneCountByWeek,
    required this.doneIds,
    required this.selectedId,
    required this.submitting,
    required this.onTapItem,
    required this.dayNameOf,
  });

  final Module module;
  final List<int> weekNumbers;
  final Map<int, Week> weekByNumber;
  final Map<int, List<Item>> itemsByWeek;
  final Map<int, int> doneCountByWeek;
  final Set<String> doneIds;
  final String? selectedId;
  final Set<String> submitting;
  final ValueChanged<Item> onTapItem;
  final String Function(int day) dayNameOf;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Container(
        width: 6,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(
        module.title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        module.sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMinor),
      ),
      children: <Widget>[
        for (final int wn in weekNumbers)
          _WeekTile(
            weekNumber: wn,
            week: weekByNumber[wn],
            items: itemsByWeek[wn] ?? const <Item>[],
            doneCount: doneCountByWeek[wn] ?? 0,
            doneIds: doneIds,
            selectedId: selectedId,
            submitting: submitting,
            onTapItem: onTapItem,
            dayNameOf: dayNameOf,
          ),
      ],
    );
  }
}

class _WeekTile extends StatelessWidget {
  const _WeekTile({
    required this.weekNumber,
    required this.week,
    required this.items,
    required this.doneCount,
    required this.doneIds,
    required this.selectedId,
    required this.submitting,
    required this.onTapItem,
    required this.dayNameOf,
  });

  final int weekNumber;
  final Week? week;
  final List<Item> items;
  final int doneCount;
  final Set<String> doneIds;
  final String? selectedId;
  final Set<String> submitting;
  final ValueChanged<Item> onTapItem;
  final String Function(int day) dayNameOf;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // SPEC：周完成度以 7 天为分母展示（口径由产品裁决，
    // 与 WeekProgress.itemRatio 的「按实际条目数」不同，勿混用）。
    final int denom = AppConstants.daysPerWeek;
    final int shownDone = doneCount > denom ? denom : doneCount;
    final bool full = shownDone >= denom;

    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 32, right: 16),
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        '第 $weekNumber 周',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        week?.title ?? '本周暂无标题',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMinor),
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 48, right: 16, bottom: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '已完成 $shownDone/$denom',
              style: theme.textTheme.labelSmall?.copyWith(
                color: full ? AppColors.success : AppColors.textMinor,
                fontWeight: full ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
        for (final Item it in items)
          _ItemTile(
            item: it,
            done: doneIds.contains(it.id),
            selected: selectedId == it.id,
            busy: submitting.contains(it.id),
            dayName: dayNameOf(it.day),
            onTap: () => onTapItem(it),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.done,
    required this.selected,
    required this.busy,
    required this.dayName,
    required this.onTap,
  });

  final Item item;
  final bool done;
  final bool selected;
  final bool busy;
  final String dayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected
          ? AppColors.gold.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 10, 16, 10),
          child: Row(
            children: <Widget>[
              Icon(
                done ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: done ? AppColors.success : AppColors.divider,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.watch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: done ? AppColors.textMinor : AppColors.text,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dayName · ${item.minutes} 分钟',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textMinor,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------
/// 右栏：条目详情 + 打卡
/// ----------------------------------------------------------------
class _DetailPane extends StatelessWidget {
  const _DetailPane({
    required this.item,
    required this.done,
    required this.submitting,
    required this.onTap,
  });

  final Item item;
  final bool done;
  final bool submitting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DetailContent(
      item: item,
      done: done,
      submitting: submitting,
      onTap: onTap,
      bottomInset: 24,
    );
  }
}

/// 窄屏独立页：自己持 state，因为 push 出去的页面不回读父页状态。
class _DetailPage extends StatefulWidget {
  const _DetailPage({
    required this.item,
    required this.done,
    required this.onCheckIn,
    required this.onUndo,
  });

  final Item item;
  final bool done;
  final Future<void> Function(int minutes, String note) onCheckIn;
  final Future<void> Function() onUndo;

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> {
  bool _done = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _done = widget.done;
  }

  Future<void> _tap() async {
    if (_busy) return;
    if (_done) {
      setState(() => _busy = true);
      await widget.onUndo();
      if (!mounted) return;
      setState(() {
        _done = false;
        _busy = false;
      });
      return;
    }
    final CheckinInput? input = await showModalBottomSheet<CheckinInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => CheckinSheet(
        item: widget.item,
        defaultMinutes: widget.item.minutes,
      ),
    );
    if (input == null) return;
    setState(() => _busy = true);
    await widget.onCheckIn(input.minutes, input.note);
    if (!mounted) return;
    setState(() {
      _done = true;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.item.watch,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: _DetailContent(
          item: widget.item,
          done: _done,
          submitting: _busy,
          onTap: _tap,
          bottomInset: 16,
        ),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.item,
    required this.done,
    required this.submitting,
    required this.onTap,
    required this.bottomInset,
  });

  final Item item;
  final bool done;
  final bool submitting;
  final VoidCallback onTap;
  final double bottomInset;

  static const List<String> _dayNames = <String>[
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
    final ThemeData theme = Theme.of(context);
    final String dayName = (item.day >= 1 && item.day <= 7)
        ? _dayNames[item.day - 1]
        : '第 ${item.day} 天';

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset),
      children: <Widget>[
        Text(
          item.watch,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '第 ${item.week} 周 · $dayName · 预估 ${item.minutes} 分钟',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMinor,
          ),
        ),
        const SizedBox(height: 20),
        _DetailRow(
          icon: Icons.play_circle_outline,
          label: '看',
          text: item.watch,
        ),
        _DetailRow(
          icon: Icons.build_outlined,
          label: '练',
          text: item.practice,
        ),
        _DetailRow(
          icon: Icons.article_outlined,
          label: '产出',
          text: item.output,
        ),
        _DetailRow(
          icon: Icons.schedule,
          label: '预估用时',
          text: '${item.minutes} 分钟',
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: submitting ? null : onTap,
            icon: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(done ? Icons.undo : Icons.check),
            label: Text(done ? '取消打卡' : '打卡'),
          ),
        ),
        if (done) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '已完成。再点一次可撤销（物理删除当日记录）。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textMinor,
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.gold),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMinor,
              ),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.touch_app_outlined, size: 40, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(
            '从左侧选择一个条目',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textMinor,
            ),
          ),
        ],
      ),
    );
  }
}
