/// 今日考核页（按「周-天」投放）。
///
/// 这是整个学习闭环的入口，流程：
///   听完当天视频 → 点进「第 X 周 第 Y 天」→ 看今天该懂什么
///   → 做完当天全部题目 → 显示对错 → 才允许打卡
///
/// 打卡不再是「自己点个勾」，而是「考完才算」。
/// 打完卡后，这一天做过的题全部进 SM-2 队列，按 7 档毕业。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/repo/question_repo.dart';
import '../widgets/qa_widgets.dart';

/// 单天的考核入口参数。
class DayExamArgs {
  const DayExamArgs({
    required this.week,
    required this.day,
    required this.itemId,
    required this.watch,
    required this.practice,
    required this.output,
    required this.minutes,
  });

  final int week;
  final int day;
  final String itemId;
  final String watch;
  final String practice;
  final String output;
  final int minutes;

  String get title => '第 $week 周 · 第 $day 天';

  /// 周一到周日显示名
  String get dayLabel {
    const List<String> names = <String>[
      '周一', '周二', '周三',
      '周四', '周五', '周六', '周日',
    ];
    return names[(day - 1).clamp(0, 6)];
  }
}

enum _Phase { intro, exam, result, checking }

class DayExamPage extends ConsumerStatefulWidget {
  const DayExamPage({super.key, required this.args});

  final DayExamArgs args;

  @override
  ConsumerState<DayExamPage> createState() => _DayExamPageState();
}

class _DayExamPageState extends ConsumerState<DayExamPage> {
  _Phase _phase = _Phase.checking;
  String? _error;

  List<McqQuestion> _questions = const <McqQuestion>[];
  /// 每题选择，-1 = 未答
  List<int> _picks = const <int>[];
  int _index = 0;
  bool _answered = false;
  int _right = 0;

  /// 每道题是否已经记账（避免重复）
  List<bool> _logged = const <bool>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(questionRepoProvider)
          .todayExam(widget.args.week, widget.args.day);
      if (!mounted) return;
      setState(() {
        _questions = list;
        _picks = List<int>.filled(list.length, -1);
        _logged = List<bool>.filled(list.length, false);
        _index = 0;
        _right = 0;
        _phase = list.isEmpty ? _Phase.result : _Phase.intro;
        _error = list.isEmpty ? '这一天的题库还没建好，先自己看视频吧' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.result;
        _error = '读取失败：$e';
      });
    }
  }

  int get _total => _questions.length;
  int get _doneCount => _picks.where((int p) => p >= 0).length;

  Future<void> _submit() async {
    if (_answered || _picks[_index] < 0) return;
    final q = _questions[_index];
    final bool ok = _picks[_index] == q.answer;
    setState(() {
      _answered = true;
      if (ok) _right++;
    });

    // 答对 → 不立即记账，等自评（与主答题页一致）。
    // 答错 → 立即记账（错因可选），保证出错也进展。
    if (!ok) {
      try {
        await ref.read(questionRepoProvider).recordAnswer(q.id, false);
        _logged[_index] = true;
      } catch (_) {
        // 记账失败不阻断
      }
    }
  }

  /// 自评提交，带 selfScore 记账
  Future<void> _rate(int score) async {
    final q = _questions[_index];
    try {
      await ref
          .read(questionRepoProvider)
          .recordAnswer(q.id, true, selfScore: score);
      _logged[_index] = true;
    } catch (_) {
      // 记账失败不阻断
    }
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _total) {
        _phase = _Phase.result;
      } else {
        _index++;
        _picks[_index] = -1;
        _answered = false;
      }
    });
  }

  /// 打卡：做完当天全部题目才能点
  Future<void> _doCheckin() async {
    try {
      await ref
          .read(checkinRepoProvider)
          .check(widget.args.itemId, DateTime.now());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已打卡：${widget.args.title}')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打卡失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.checking:
        return const Center(child: CircularProgressIndicator());
      case _Phase.intro:
        return _buildIntro();
      case _Phase.exam:
        return _buildExam();
      case _Phase.result:
        return _buildResult();
    }
  }

  // ---------------- 进场：今天该懂什么 ----------------
  Widget _buildIntro() {
    final theme = Theme.of(context);
    final a = widget.args;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${a.dayLabel} · ${a.minutes} 分钟',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _InfoRow(label: '看', text: a.watch),
              const SizedBox(height: 10),
              _InfoRow(label: '练', text: a.practice),
              const SizedBox(height: 10),
              _InfoRow(label: '交', text: a.output),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.assignment_turned_in_outlined,
                      size: 18, color: AppColors.goldText),
                  const SizedBox(width: 6),
                  Text('今天要考 $_total 道题',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: AppColors.goldText)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '考完才能打卡。这是唯一能证明「今天真的听进去了」的东西。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _phase = _Phase.exam),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('开始考核'),
        ),
      ],
    );
  }

  // ---------------- 答题 ----------------
  Widget _buildExam() {
    final theme = Theme.of(context);
    final q = _questions[_index];
    final int picked = _picks[_index];
    final bool ok = _answered && picked == q.answer;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('第 ${_index + 1} / $_total 题',
                      style: theme.textTheme.bodySmall),
                  const Spacer(),
                  Text('已答 $_doneCount / $_total',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _total,
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
                Text(q.question,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.5)),
                const SizedBox(height: 16),
                for (var i = 0; i < q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OptionTile(
                      label: String.fromCharCode(65 + i),
                      text: q.options[i],
                      selected: picked == i,
                      correct: _answered && i == q.answer,
                      wrong: _answered && picked == i && i != q.answer,
                      onTap: _answered
                          ? null
                          : () => setState(() => _picks[_index] = i),
                    ),
                  ),
                if (_answered && q.explain != null && q.explain!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ExplainBox(text: q.explain!),
                ],
                if (_answered && ok) ...[
                  const SizedBox(height: 14),
                  _QuickRate(onRate: _rate),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !_answered
                    ? (picked < 0 ? null : _submit)
                    : (_index + 1 >= _total ? () => setState(() => _phase = _Phase.result) : _next),
                child: Text(
                  !_answered
                      ? '提交'
                      : (_index + 1 >= _total ? '查看结果' : '下一题'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- 结果 + 打卡 ----------------
  Widget _buildResult() {
    final theme = Theme.of(context);
    final int done = _doneCount;
    final bool finished = _total > 0 && done >= _total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: <Widget>[
              Text(
                _total == 0 ? '—' : '$_right / $_total',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error ??
                    (_total == 0
                        ? '没有题目'
                        : (finished
                            ? '做完 $done 道，答对 $_right 道'
                            : '还剩 ${_total - done} 道没做')),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_total > 0 && !finished) ...<Widget>[
          OutlinedButton(
            onPressed: () => setState(() {
              // 回到第一道未答的题
              final int nxt = _picks.indexWhere((int p) => p < 0);
              _index = nxt < 0 ? 0 : nxt;
              _answered = _picks[_index] >= 0;
              _phase = _Phase.exam;
            }),
            child: const Text('继续未答的题'),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: finished ? _doCheckin : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(finished ? '打卡：今天学完了' : '做完 $_total 道才能打卡'),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '打卡后，今天的 $_total 道题全部进复习队列，按 1/2/4/7/15/30/60 天回来。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.ink)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ),
      ],
    );
  }
}

/// 答对后的快速自评（三档，不跑验证题，日考核场景要快）。
class _QuickRate extends StatelessWidget {
  const _QuickRate({required this.onRate});

  final Future<void> Function(int score) onRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('讲得出来吗？', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Chip(
                label: '讲清了',
                color: AppColors.success,
                onTap: () => onRate(4),
              ),
              _Chip(
                label: '要停一下',
                color: AppColors.ink,
                onTap: () => onRate(3),
              ),
              _Chip(
                label: '绕过去了',
                color: const Color(0xFFFF9500),
                onTap: () => onRate(2),
              ),
              _Chip(
                label: '讲不出来',
                color: AppColors.warning,
                onTap: () => onRate(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
