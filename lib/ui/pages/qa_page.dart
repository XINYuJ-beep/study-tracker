/// 问答页（测试页）—— 第 4 轮。
/// 对应 SPEC 4.3。
///
/// 本轮实现两个模块：
///   1. 自检卡：从 cards + concepts 合并队列中抽到期条目，翻面自评三档。
///   2. 选择题：只出已学周次（由 PlanRepo.progressiveCursorWeek 圈定），10 题 8 题算过，
///      错题自动进错题本（mcqs.wrong_count / right_streak）。
///
/// 本轮未实现（P1）：概念题 4选1、旧题抽查、白板抽背、阶段听力。
///
/// 【SRS 口径校准记录】
/// SPEC 4.3 字面写「记得/模糊/忘了」，repo 侧已按此校准为三档语义：
///   记得（score 4）：档位 +1，间隔按新档位查表；
///   模糊（score 3）：档位不变，只把 due_date 按当前档位间隔重置；
///   忘了（score 1/2）：档位 -1，下限 0。
/// 间隔表 AppConstants.reviewIntervals = [1,2,4,7,15,30,60] 共 7 档（索引即档位），
/// 档位达到 AppConstants.reviewGraduatedStage（7）即毕业，due_date 置空不再进队列。
/// UI 层分数映射：记得 = 4，模糊 = 3，忘了 = 1，与 repo._nextStage 判据一致。
///
/// 数据全部走 repo，页面里不写 SQL。
/// 跨天以凌晨 4 点为界，统一用 effectiveToday()。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/repo/plan_repo.dart';
import '../../data/repo/question_repo.dart';
import '../../core/providers.dart';
import 'qa_extra_page.dart';
import '../widgets/qa_widgets.dart';

/// 页面内两个模块。
enum _QaTab { review, mcq, extra }

/// 自检卡正反面。
enum _CardPhase { front, back }

class QaPage extends ConsumerStatefulWidget {
  const QaPage({super.key});

  @override
  ConsumerState<QaPage> createState() => _QaPageState();
}

class _QaPageState extends ConsumerState<QaPage> {
  _QaTab _tab = _QaTab.review;

  // ---------- 自检卡状态 ----------
  List<ReviewEntry> _reviewQueue = const [];
  int _reviewIndex = 0;
  _CardPhase _cardPhase = _CardPhase.front;
  bool _reviewLoaded = false;
  bool _reviewDone = false;
  int _reviewRemembered = 0;
  bool _grading = false;

  // ---------- 选择题状态 ----------
  int _learnedWeek = 0;
  List<McqQuestion> _mcqList = const [];
  int _mcqIndex = 0;
  int? _mcqPicked;
  bool _mcqAnswered = false;
  int _mcqRight = 0;
  bool _mcqFinished = false;
  bool _mcqLoaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadReview);
  }

  // ================= 数据加载 =================

  Future<void> _loadReview() async {
    List<ReviewEntry> list;
    try {
      list = await ref.read(questionRepoProvider).dueReview(limit: 50);
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    setState(() {
      _reviewQueue = list;
      _reviewIndex = 0;
      _cardPhase = _CardPhase.front;
      _reviewRemembered = 0;
      _reviewDone = list.isEmpty;
      _reviewLoaded = true;
    });
  }

  Future<void> _loadMcq() async {
    final planRepo = ref.read(planRepoProvider);
    final qRepo = ref.read(questionRepoProvider);
    int week = 0;
    try {
      week = await planRepo.progressiveCursorWeek();
    } catch (_) {
      week = 0;
    }

    // 已学周次：第 1 ~ week 周。
    final all = <McqQuestion>[];
    final seen = <String>{};
    try {
      final focused = await qRepo.focusedMcqs();
      for (final q in focused) {
        if (seen.add(q.id)) all.add(q);
      }
      for (var w = 1; w <= week; w++) {
        final list = await qRepo.mcqsByWeek(w);
        for (final q in list) {
          if (seen.add(q.id)) all.add(q);
        }
      }
    } catch (_) {
      // 兜底：保持已有结果。
    }

    all.shuffle();
    // 错题前置。
    all.sort((a, b) {
      final aWrong = a.rightStreak < AppConstants.rightStreakToClear ? 0 : 1;
      final bWrong = b.rightStreak < AppConstants.rightStreakToClear ? 0 : 1;
      return aWrong.compareTo(bWrong);
    });
    final picked = all.take(10).toList();

    if (!mounted) return;
    setState(() {
      _learnedWeek = week;
      _mcqList = picked;
      _mcqIndex = 0;
      _mcqPicked = null;
      _mcqAnswered = false;
      _mcqRight = 0;
      _mcqFinished = picked.isEmpty;
      _mcqLoaded = true;
    });
  }

  // ================= 自检卡交互 =================

  /// score: 记得 4 / 模糊 3 / 忘了 1。
  Future<void> _gradeCard(int score) async {
    if (_grading) return;
    final entry = _reviewQueue[_reviewIndex];
    setState(() {
      _grading = true;
      if (score >= 4) _reviewRemembered++;
    });
    try {
      await ref.read(questionRepoProvider).gradeReview(entry, score);
    } catch (_) {
      // 记账失败不阻断推进。
    }
    if (!mounted) return;
    setState(() {
      _grading = false;
      if (_reviewIndex + 1 >= _reviewQueue.length) {
        _reviewDone = true;
      } else {
        _reviewIndex++;
        _cardPhase = _CardPhase.front;
      }
    });
  }

  void _flipCard() {
    setState(() {
      _cardPhase = _cardPhase == _CardPhase.front
          ? _CardPhase.back
          : _CardPhase.front;
    });
  }

  // ================= 选择题交互 =================

  Future<void> _answerMcq() async {
    if (_mcqAnswered || _mcqPicked == null) return;
    final q = _mcqList[_mcqIndex];
    final correct = _mcqPicked == q.answer;
    setState(() {
      _mcqAnswered = true;
      if (correct) _mcqRight++;
    });
    try {
      await ref.read(questionRepoProvider).recordAnswer(q.id, correct);
    } catch (_) {
      // 记账失败不阻断。
    }
  }

  void _nextMcq() {
    setState(() {
      if (_mcqIndex + 1 >= _mcqList.length) {
        _mcqFinished = true;
      } else {
        _mcqIndex++;
        _mcqPicked = null;
        _mcqAnswered = false;
      }
    });
  }

  void _switchTab(_QaTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (tab == _QaTab.mcq && !_mcqLoaded) {
      Future<void>.microtask(_loadMcq);
    }
    if (tab == _QaTab.review && !_reviewLoaded) {
      Future<void>.microtask(_loadReview);
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('问答'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _TabChip(
                  label: '自检卡',
                  selected: _tab == _QaTab.review,
                  onTap: () => _switchTab(_QaTab.review),
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: '选择题',
                  selected: _tab == _QaTab.mcq,
                  onTap: () => _switchTab(_QaTab.mcq),
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: '进阶',
                  selected: _tab == _QaTab.extra,
                  onTap: () => _switchTab(_QaTab.extra),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: switch (_tab) {
          _QaTab.review => _buildReview(theme),
          _QaTab.mcq => _buildMcq(theme),
          _QaTab.extra => const QaExtraPage(),
        },
      ),
    );
  }

  // ---------- 自检卡 ----------

  Widget _buildReview(ThemeData theme) {
    if (!_reviewLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildReviewHeader(theme),
        const Divider(height: 1),
        Expanded(child: _buildReviewBody(theme)),
      ],
    );
  }

  Widget _buildReviewHeader(ThemeData theme) {
    final total = _reviewQueue.length;
    final shown = _reviewDone ? total : _reviewIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Text(
            '待复习 $total / $total',
            style: theme.textTheme.titleSmall,
          ),
          const Spacer(),
          Text(
            '已评 $shown · 记得 $_reviewRemembered',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBody(ThemeData theme) {
    if (_reviewQueue.isEmpty) {
      return EmptyHint(
        icon: Icons.check_circle_outline,
        title: '今天没有到期的自检卡',
        subtitle: '到期条目由卡片与概念的复习档位自动排期',
        actionLabel: '重新检查',
        onAction: () {
          setState(() => _reviewLoaded = false);
          Future<void>.microtask(_loadReview);
        },
      );
    }

    if (_reviewDone) {
      final total = _reviewQueue.length;
      final rate = total == 0 ? 0 : (_reviewRemembered * 100 / total).round();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('本轮自检完成', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '共 $total 张 · 记得 $_reviewRemembered 张 · 记得率 $rate%',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                setState(() => _reviewLoaded = false);
                Future<void>.microtask(_loadReview);
              },
              child: const Text('再抽一轮'),
            ),
          ],
        ),
      );
    }

    final entry = _reviewQueue[_reviewIndex];
    final isFront = _cardPhase == _CardPhase.front;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${_reviewIndex + 1} / ${_reviewQueue.length} 张',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SourceTag(
                      label: entry.source == ReviewSource.card ? '卡片' : '概念',
                    ),
                    const SizedBox(width: 8),
                    if (entry.week != null)
                      Text('第 ${entry.week} 周', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  isFront ? entry.front : entry.back,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
                ),
                if (isFront) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _flipCard,
                    icon: const Icon(Icons.flip_to_back, size: 18),
                    label: const Text('显示答案'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '当前档位 ${entry.stage} / ${AppConstants.reviewGraduatedStage}'
            '${entry.stage >= AppConstants.reviewGraduatedStage ? ' · 已毕业' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          if (isFront)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _flipCard,
                child: const Text('翻面'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: GradeButton(
                    label: '忘了',
                    hint: '退一级',
                    color: theme.colorScheme.error,
                    onTap: _grading ? null : () => _gradeCard(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GradeButton(
                    label: '模糊',
                    hint: '重置本档',
                    color: const Color(0xFFFF9500),
                    onTap: _grading ? null : () => _gradeCard(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GradeButton(
                    label: '记得',
                    hint: '进一级',
                    color: const Color(0xFF34C759),
                    onTap: _grading ? null : () => _gradeCard(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---------- 选择题 ----------

  Widget _buildMcq(ThemeData theme) {
    if (!_mcqLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMcqHeader(theme),
        const Divider(height: 1),
        Expanded(child: _buildMcqBody(theme)),
      ],
    );
  }

  Widget _buildMcqHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Text('共 ${_mcqList.length} 题', style: theme.textTheme.titleSmall),
          const Spacer(),
          Text(
            _learnedWeek == 0 ? '尚未开始学习' : '已学第 1~$_learnedWeek 周',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMcqBody(ThemeData theme) {
    if (_mcqList.isEmpty) {
      return EmptyHint(
        icon: Icons.quiz_outlined,
        title: _learnedWeek == 0 ? '还没有可出的题' : '本周没有可用题目',
        subtitle: _learnedWeek == 0
            ? '先在计划页完成打卡，学过的周次才会出题'
            : '已学周次内没有匹配的选择题',
        actionLabel: '重新加载',
        onAction: () {
          setState(() => _mcqLoaded = false);
          Future<void>.microtask(_loadMcq);
        },
      );
    }

    if (_mcqFinished) {
      final total = _mcqList.length;
      final pass = total > 0 && _mcqRight / total >= 0.8;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pass ? Icons.verified : Icons.error_outline,
              size: 56,
              color: pass
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              pass ? '通过' : '未通过',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '答对 $_mcqRight / $total（阈值 80%）',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '答错的题已进入错题本',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                setState(() => _mcqLoaded = false);
                Future<void>.microtask(_loadMcq);
              },
              child: const Text('再来一组'),
            ),
          ],
        ),
      );
    }

    final q = _mcqList[_mcqIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '第 ${_mcqIndex + 1} / ${_mcqList.length} 题',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              if (q.week != null)
                Text('第 ${q.week} 周', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _mcqList.isEmpty
                  ? 0
                  : (_mcqIndex + 1) / _mcqList.length,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            q.question,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OptionTile(
                label: String.fromCharCode(65 + i),
                text: q.options[i],
                selected: _mcqPicked == i,
                correct: _mcqAnswered && i == q.answer,
                wrong: _mcqAnswered && _mcqPicked == i && i != q.answer,
                onTap: _mcqAnswered
                    ? null
                    : () => setState(() => _mcqPicked = i),
              ),
            ),
          if (_mcqAnswered && q.explain != null && q.explain!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('解析', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    q.explain!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (!_mcqAnswered)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _mcqPicked == null ? null : _answerMcq,
                child: const Text('提交'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _nextMcq,
                child: Text(
                  _mcqIndex + 1 >= _mcqList.length ? '交卷' : '下一题',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ================= 组件 =================

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}