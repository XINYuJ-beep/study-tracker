/// 限时模拟考（缺口④）。
///
/// 设计口径：
///   - 从已学范围（week <= 渐进游标周）随机抽 30 题；
///   - 限时 40 分钟，顶栏倒计时，剩 5 分钟变红；
///   - 一次性交卷：作答期间不显示对错和解析，交卷后才给答案；
///   - 不写 SM-2，不写错题本。模考是「监考」场景，和日常刷题完全分离。
///   - 中途退出算弃考，不保留进度。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../data/db/tables.dart';
import '../widgets/concept_popup.dart';
import '../widgets/qa_widgets.dart';

/// 模考参数（常量落这里，方便以后调）。
class MockExamConfig {
  const MockExamConfig._();

  /// 题量
  static const int questionCount = 30;

  /// 限时（分钟）
  static const int durationMinutes = 40;

  /// 及格线（答对数）
  static const int passLine = 24;
}

class MockExamPage extends ConsumerStatefulWidget {
  const MockExamPage({super.key});

  @override
  ConsumerState<MockExamPage> createState() => _MockExamPageState();
}

enum _Phase { loading, running, finished, error }

class _MockExamPageState extends ConsumerState<MockExamPage> {
  _Phase _phase = _Phase.loading;
  String? _error;

  List<McqQuestion> _items = const <McqQuestion>[];
  /// 每题的选择，-1 = 未答。
  List<int> _picks = const <int>[];
  int _index = 0;

  /// 已用秒数，只算正向。
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _totalSeconds => MockExamConfig.durationMinutes * 60;
  int get _remainSeconds =>
      (_totalSeconds - _elapsed).clamp(0, _totalSeconds);

  Future<void> _start() async {
    try {
      final week = await ref.read(planRepoProvider).progressiveCursorWeek();
      final list = await ref.read(questionRepoProvider).randomWithinWeeks(
            week,
            limit: MockExamConfig.questionCount,
          );
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _phase = _Phase.error;
          _error = '已学范围里还没有选择题，先把当前周的选择题做一遍';
        });
        return;
      }
      setState(() {
        _items = list;
        _picks = List<int>.filled(list.length, -1);
        _index = 0;
        _elapsed = 0;
        _phase = _Phase.running;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _elapsed++);
        if (_remainSeconds <= 0) {
          t.cancel();
          _submit(auto: true);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '抽题失败：$e';
      });
    }
  }

  int get _answeredCount => _picks.where((int p) => p >= 0).length;

  int get _rightCount {
    var n = 0;
    for (var i = 0; i < _items.length; i++) {
      if (_picks[i] >= 0 && _picks[i] == _items[i].answer) n++;
    }
    return n;
  }

  void _submit({bool auto = false}) async {
    if (_phase != _Phase.running) return;
    _timer?.cancel();
    if (!auto) {
      final int un = _items.length - _answeredCount;
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('交卷'),
          content: Text(
            un == 0
                ? '确定交卷？交卷后不再显示作答界面。'
                : '还有 $un 题没答，确定现在交卷？',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('继续作答'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('交卷'),
            ),
          ],
        ),
      );
      if (go != true) {
        _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() => _elapsed++);
          if (_remainSeconds <= 0) {
            t.cancel();
            _submit(auto: true);
          }
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.finished);
  }

  String _fmt(int sec) {
    final int m = sec ~/ 60;
    final int s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmQuit() async {
    if (_phase != _Phase.running) return true;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('放弃本次模考？'),
        content: const Text('中途退出算弃考，本次成绩不保留。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续考'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('弃考'),
          ),
        ],
      ),
    );
    return go == true;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return PopScope(
      canPop: _phase != _Phase.running,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool go = await _confirmQuit();
        if (go && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('限时模考'),
          actions: <Widget>[
            if (_phase == _Phase.running)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    _fmt(_remainSeconds),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                      color: _remainSeconds <= 300
                          ? AppColors.warning
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_error ?? '出错了', textAlign: TextAlign.center),
                const SizedBox(height: AppSizes.gap2),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        );
      case _Phase.running:
        return _buildQuestion(theme);
      case _Phase.finished:
        return _buildResult(theme);
    }
  }

  Widget _buildQuestion(ThemeData theme) {
    final McqQuestion q = _items[_index];
    final int picked = _picks[_index];

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '第 ${_index + 1} / ${_items.length} 题',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    '已答 $_answeredCount / ${_items.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _items.length,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConceptTappable(
                  text: q.question,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OptionTile(
                      label: String.fromCharCode(65 + i),
                      text: q.options[i],
                      selected: picked == i,
                      correct: false,
                      wrong: false,
                      onTap: () => setState(() => _picks[_index] = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index == 0
                        ? null
                        : () => setState(() => _index--),
                    child: const Text('上一题'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _index + 1 >= _items.length
                      ? FilledButton(
                          onPressed: () => _submit(),
                          child: const Text('交卷'),
                        )
                      : FilledButton(
                          onPressed: () => setState(() => _index++),
                          child: const Text('下一题'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(ThemeData theme) {
    final int right = _rightCount;
    final int total = _items.length;
    final int pct = total == 0 ? 0 : (right / total * 100).round();
    final bool passed = right >= MockExamConfig.passLine;
    final Color tone = passed ? AppColors.success : AppColors.warning;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tone.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: <Widget>[
              Text(
                '$right / $total',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$pct%  ·  用时 ${_fmt(_elapsed)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tone,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                passed ? '过线了（及格线 $right≥${MockExamConfig.passLine}）' : '没到及格线（需 ${MockExamConfig.passLine} 题）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('逐题回顾', style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        for (var i = 0; i < _items.length; i++) ...<Widget>[
          _ReviewTile(
            index: i,
            q: _items[i],
            picked: _picks[i],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        Center(
          child: Text(
            '模考不计入复习排程，也不进错题本。它只用来称一下你现在的斤两。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('结束'),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.index,
    required this.q,
    required this.picked,
  });

  final int index;
  final McqQuestion q;
  final int picked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool ok = picked == q.answer;
    final bool blank = picked < 0;
    final Color tone = blank
        ? theme.colorScheme.onSurfaceVariant
        : (ok ? AppColors.success : AppColors.warning);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${index + 1}.',
                style: theme.textTheme.labelLarge?.copyWith(color: tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.question,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            blank
                ? '未作答 · 正确答案 ${String.fromCharCode(65 + q.answer)}'
                : (ok
                    ? '✓ 正确，你选了 ${String.fromCharCode(65 + picked)}'
                    : '✗ 你选了 ${String.fromCharCode(65 + picked)}，正确是 ${String.fromCharCode(65 + q.answer)}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (q.explain != null && q.explain!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              q.explain!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
