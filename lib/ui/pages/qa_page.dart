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
import '../../data/repo/question_repo.dart';
import '../../core/providers.dart';
import 'mock_exam_page.dart';
import 'qa_extra_page.dart';
import '../widgets/concept_popup.dart';
import 'mcq_review_page.dart';
import '../widgets/qa_widgets.dart';

/// 页面内两个模块。
enum _QaTab { review, extra }

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


  // ---------- 缺口③错因归因 ----------
  /// 当前题选中的错因：0=未选，1 看不懂题 / 2 知识点没记住 / 3 记混了 / 4 想陷了。
  /// 答错时是否已经记过账（避免重复 recordAnswer）。

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

  @override
  void dispose() {
    super.dispose();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('问答'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const McqReviewPage(),
              ),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('到期题'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const MockExamPage(),
              ),
            ),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('模考'),
          ),
          const SizedBox(width: 8),
        ],
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
          _QaTab.extra => const QaExtraPage(),
        },
      ),
    );
  }

  // ---------- 自检卡 ----------

  Widget _buildReview(ThemeData theme) {
    if (!_reviewLoaded) {
      return Center(
        child: Semantics(
          label: '正在加载…',
          child: const CircularProgressIndicator(),
        ),
      );
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
                    SourceTag(
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
