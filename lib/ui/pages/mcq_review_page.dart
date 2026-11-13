/// 到期选择题复习（完整流程）。
///
/// 与日考核的分工：
///   日考核 = 当天学完马上考，轻量，只走四档自评。
///   本页   = 几天后按 SM-2 到期回来，走完整流程：
///            自评 → 验证题（验自评准不准）→ 错因归因（答错时）。
///
/// 为什么分期不同：
///   刚学完时记忆还热，不用验；隔几天后「我觉得记得」才最需要被打脸。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/repo/question_repo.dart';
import '../widgets/qa_widgets.dart';
import '../widgets/review_widgets.dart';

class McqReviewPage extends ConsumerStatefulWidget {
  const McqReviewPage({super.key});

  @override
  ConsumerState<McqReviewPage> createState() => _McqReviewPageState();
}

class _McqReviewPageState extends ConsumerState<McqReviewPage> {
  bool _loading = true;
  String? _error;

  List<McqQuestion> _items = const <McqQuestion>[];
  int _index = 0;

  int? _picked;
  bool _answered = false;
  int _right = 0;

  // 自评
  int _selfScore = 0;
  bool _selfRated = true;
  final TextEditingController _selfCtrl = TextEditingController();

  // 验证题
  int _pendingScore = 0;
  McqQuestion? _verifyMcq;
  int _verifyPicked = -1;

  // 错因
  int _failReason = 0;
  bool _wrongLogged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _selfCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list =
          await ref.read(questionRepoProvider).dueMcqs(limit: AppConstants.dailyReviewQuota);
      if (!mounted) return;
      setState(() {
        _items = list;
        _index = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取失败：$e';
      });
    }
  }

  McqQuestion get _q => _items[_index];

  void _resetForNext() {
    _picked = null;
    _answered = false;
    _selfScore = 0;
    _selfRated = true;
    _pendingScore = 0;
    _verifyMcq = null;
    _verifyPicked = -1;
    _failReason = 0;
    _wrongLogged = false;
    _selfCtrl.clear();
  }

  Future<void> _submit() async {
    if (_answered || _picked == null) return;
    final bool ok = _picked == _q.answer;
    setState(() {
      _answered = true;
      if (ok) _right++;
      // 答对等自评；答错等选错因
      _selfRated = !ok;
    });
  }

  /// 自评：3/4 抽验证题，1/2 直接记账
  Future<void> _rate(int score) async {
    if (_selfRated) return;
    if (score >= 3) {
      McqQuestion? v;
      try {
        v = await ref
            .read(questionRepoProvider)
            .pickVerifyMcq(_q.id, week: _q.week);
      } catch (_) {
        v = null;
      }
      if (v != null) {
        setState(() {
          _selfScore = score;
          _pendingScore = score;
          _verifyMcq = v;
          _verifyPicked = -1;
        });
        return;
      }
    }
    await _commit(score, null);
  }

  Future<void> _submitVerify() async {
    final int score = _pendingScore;
    final McqQuestion? v = _verifyMcq;
    if (score == 0 || v == null || _verifyPicked < 0) return;
    final bool ok = _verifyPicked == v.answer;
    setState(() {
      _verifyMcq = null;
      _pendingScore = 0;
      _verifyPicked = -1;
    });
    await _commit(score, ok);
  }

  Future<void> _commit(int score, bool? verified) async {
    int shown = score;
    if (verified == false && shown >= 3) shown--;
    setState(() {
      _selfScore = shown;
      _selfRated = true;
    });
    try {
      await ref.read(questionRepoProvider).recordAnswer(
            _q.id,
            true,
            selfScore: score,
            verified: verified,
          );
    } catch (_) {
      // 不阻断
    }
  }

  Future<void> _pickReason(int reason) async {
    if (_wrongLogged) return;
    setState(() {
      _failReason = reason;
      _wrongLogged = true;
    });
    try {
      await ref
          .read(questionRepoProvider)
          .recordAnswer(_q.id, false, failReason: reason);
    } catch (_) {}
  }

  Future<void> _skipReason() async {
    if (_wrongLogged) return;
    setState(() => _wrongLogged = true);
    try {
      await ref.read(questionRepoProvider).recordAnswer(_q.id, false);
    } catch (_) {}
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _items.length) {
        _index = _items.length;
      } else {
        _index++;
        _resetForNext();
      }
    });
  }

  bool get _canAdvance {
    if (!_answered) return false;
    if (_verifyMcq != null) return false;
    final bool ok = _picked == _q.answer;
    return ok ? _selfRated : _wrongLogged;
  }

  String _label(int s) {
    switch (s) {
      case 4:
        return '讲清了';
      case 3:
        return '讲了但要停一下';
      case 2:
        return '关键点绕过去了';
      case 1:
        return '讲不出来';
      default:
        return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('到期复习'),
        actions: <Widget>[
          if (!_loading && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_index.clamp(0, _items.length)} / ${_items.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '今天没有到期的选择题。
去把今天该学的学了。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.8,
            ),
          ),
        ),
      );
    }
    if (_index >= _items.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '复习完成',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '共 ${_items.length} 道，答对 $_right 道',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final bool ok = _answered && _picked == _q.answer;

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _q.question,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OptionTile(
                      label: String.fromCharCode(65 + i),
                      text: _q.options[i],
                      selected: _picked == i,
                      correct: _answered && i == _q.answer,
                      wrong: _answered && _picked == i && i != _q.answer,
                      onTap: _answered ? null : () => setState(() => _picked = i),
                    ),
                  ),
                if (_answered && _q.explain != null && _q.explain!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ExplainBox(text: _q.explain!),
                ],
                // 错因卡（答错且未标记）
                if (_answered && !ok && !_wrongLogged) ...[
                  const SizedBox(height: 16),
                  FailReasonCard(onPick: _pickReason, onSkip: _skipReason),
                ],
                // 验证题
                if (_verifyMcq != null && _pendingScore > 0) ...[
                  const SizedBox(height: 16),
                  VerifyCard(
                    mcq: _verifyMcq!,
                    picked: _verifyPicked,
                    onPick: (int i) => setState(() => _verifyPicked = i),
                    onSubmit: _verifyPicked < 0 ? null : _submitVerify,
                  ),
                ],
                // 自评卡（答对且未自评，且不在验证中）
                if (_answered && ok && !_selfRated && _verifyMcq == null) ...[
                  const SizedBox(height: 16),
                  SelfRatingCard(controller: _selfCtrl, onRate: _rate),
                ],
                if (_answered && _selfScore > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '已自评：${_label(_selfScore)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
                    ? (_picked == null ? null : _submit)
                    : (_canAdvance ? _next : null),
                child: Text(
                  !_answered
                      ? '提交'
                      : (_canAdvance
                          ? (_index + 1 >= _items.length ? '完成' : '下一题')
                          : (ok ? '先完成自评' : '先选一个错因（或跳过）')),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
