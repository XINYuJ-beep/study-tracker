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
import 'qa_extra_page.dart';
import '../widgets/concept_popup.dart';
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
  /// 【P3】当前到期（due_date 已到）的选择题条数，用于 UI 展示今日到期量。
  int _mcqDueCount = 0;
  List<McqQuestion> _mcqList = const [];
  int _mcqIndex = 0;
  int? _mcqPicked;
  bool _mcqAnswered = false;
  int _mcqRight = 0;
  bool _mcqFinished = false;
  bool _mcqLoaded = false;

  // ---------- 缺口²「用自己的话讲一遍」（自评磍点）----------
  /// 当前题是否已经做完自评。答对后必须自评才能继续，答错直接过。
  bool _mcqSelfRated = true;
  /// 当前题的自评结果：0=未评，1=讲不出来，2=卡壳，3=讲清了。
  int _mcqSelfScore = 0;
  final TextEditingController _mcqSelfCtrl = TextEditingController();

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

  /// 【P3】按天投放：到期队列优先，新题补位。
  ///
  /// 取题分两条腿：
  ///   1) SM-2 到期队列 —— dueMcqs() 返回 due_date 已到的题，按 due_date 升序，
  ///      内部顺序原样保留（越早到期越先考），不再二次打乱。
  ///   2) 新题补位 —— due_date 为 NULL 的题永远进不了到期队列，
  ///      所以到期题不够 [goal] 条时，从已学周次随机抽题补足，错题优先。
  ///
  /// 每日条数取 settings 的 daily_goal（与打卡目标同源），缺省 3。
  Future<void> _loadMcq() async {
    final planRepo = ref.read(planRepoProvider);
    final qRepo = ref.read(questionRepoProvider);
    int week = 0;
    try {
      week = await planRepo.progressiveCursorWeek();
    } catch (_) {
      week = 0;
    }

    final goal = await _readMcqDailyGoal();

    // 第 1 条腿：SM-2 到期队列，按 due_date 升序原样保留。
    final due = <McqQuestion>[];
    try {
      due.addAll(await qRepo.dueMcqs());
    } catch (_) {
      // 到期队列读失败不阻断，走补位。
    }
    final picked = <McqQuestion>[];
    final used = <String>{};
    for (final q in due) {
      if (picked.length >= goal) break;
      if (used.add(q.id)) picked.add(q);
    }

    // 第 2 条腿：到期不够 goal 时，用已学周次的新题补位（错题优先）。
    if (picked.length < goal && week > 0) {
      final pool = <McqQuestion>[];
      final seen = <String>{};
      try {
        final focused = await qRepo.focusedMcqs();
        for (final q in focused) {
          if (seen.add(q.id)) pool.add(q);
        }
        for (var w = 1; w <= week; w++) {
          final list = await qRepo.mcqsByWeek(w);
          for (final q in list) {
            if (seen.add(q.id)) pool.add(q);
          }
        }
      } catch (_) {
        // 兜底：保持已有结果。
      }
      pool.removeWhere((q) => used.contains(q.id));
      pool.shuffle();
      // 错题前置：只在补位段内生效。
      pool.sort((a, b) {
        final aWrong = a.rightStreak < AppConstants.rightStreakToClear ? 0 : 1;
        final bWrong = b.rightStreak < AppConstants.rightStreakToClear ? 0 : 1;
        return aWrong.compareTo(bWrong);
      });
      for (final q in pool) {
        if (picked.length >= goal) break;
        if (used.add(q.id)) picked.add(q);
      }
    }

    if (!mounted) return;
    setState(() {
      _learnedWeek = week;
      _mcqDueCount = due.length;
      _mcqList = picked;
      _mcqIndex = 0;
      _mcqPicked = null;
      _mcqAnswered = false;
      _mcqRight = 0;
      _mcqFinished = picked.isEmpty;
      _mcqLoaded = true;
    });
  }

  /// 每日投放条数：读 settings.daily_goal，缺省 AppConstants.dailyGoalDefault。
  Future<int> _readMcqDailyGoal() async {
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
      // 答对 -> 停下来等他自评「用自己的话讲一遍」；答错 -> 直接过，不需自评。
      _mcqSelfRated = !correct;
      _mcqSelfScore = 0;
      _mcqSelfCtrl.clear();
      if (correct) _mcqRight++;
    });
    if (!correct) {
      try {
        await ref.read(questionRepoProvider).recordAnswer(q.id, false);
      } catch (_) {
        // 记账失败不阻断。
      }
    }
  }

  /// 自评提交：三档接 SM-2。
  ///   3 讲清了   -> 正常升档
  ///   2 卡壳     -> 升档但间隔取中间值（升幅减半）
  ///   1 讲不出来 -> 判忘了，降档；同时把答错计数 +1（因为实际是没真懂）
  Future<void> _submitSelfRating(int score) async {
    if (_mcqSelfRated) return;
    final q = _mcqList[_mcqIndex];
    setState(() {
      _mcqSelfScore = score;
      _mcqSelfRated = true;
    });
    try {
      await ref.read(questionRepoProvider)
          .recordAnswer(q.id, true, selfScore: score);
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
        _mcqSelfRated = true;
        _mcqSelfScore = 0;
        _mcqSelfCtrl.clear();
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

  String _selfScoreLabel(int score) {
    switch (score) {
      case 3:
        return '讲清了';
      case 2:
        return '讲了但卡壳';
      case 1:
        return '讲不出来';
      default:
        return '-';
    }
  }

  @override
  void dispose() {
    _mcqSelfCtrl.dispose();
    super.dispose();
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

  Widget _buildMcq(ThemeData theme) {
    if (!_mcqLoaded) {
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
            _learnedWeek == 0 ? '尚未开始学习' : ('已学第 1~$_learnedWeek 周' + (_mcqDueCount > 0 ? ' - $_mcqDueCount 道到期' : '')),
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
              // source_ref 标签已含「第 N 周 第 M 天」，此处不再重复显示周数。
              SourceTag.ref(q.sourceRef),
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
                  ConceptTappable(
                    text: q.explain!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ],
          // 缺口²：答对后的「用自己的话讲一遍」自评卡。不进 AI，全靠你自己判断。
          if (_mcqAnswered && !_mcqSelfRated) ...[
            const SizedBox(height: 18),
            _SelfRatingCard(
              controller: _mcqSelfCtrl,
              onRate: _submitSelfRating,
            ),
          ],
          // 自评完成后回显刚选的结果（只读）。
          if (_mcqAnswered && _mcqSelfScore > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '已自评：${_selfScoreLabel(_mcqSelfScore)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
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
          else if (_mcqSelfRated)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _nextMcq,
                child: Text(
                  _mcqIndex + 1 >= _mcqList.length ? '交卷' : '下一题',
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: null,
                child: const Text('先完成自评'),
              ),
            ),
        ],
      ),
    );
  }
}

// ================= 组件 =================

/// 缺口²：答对后的「用自己的话讲一遍」自评卡。
///
/// 设计口径（方案 A）：
///   - 不自评就不放行，逼你真的讲一遍；
///   - 三档结果直接接 SM-2，不调任何 AI；
///   - 输入框内容不作判定，只当作你自己讲一遍的载体（不入库）。
class _SelfRatingCard extends StatelessWidget {
  const _SelfRatingCard({required this.controller, required this.onRate});

  final TextEditingController controller;
  final Future<void> Function(int score) onRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.record_voice_over_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text('用自己的话讲一遍', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '选对了不等于真懂了。用自己的话把这道题的道理讲出来，再给自己定罪。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            decoration: InputDecoration(
              hintText: '例如：这题考的是 …，因为 …，所以选 …',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '讲得怎么样？',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RateButton(
                  label: '讲清了',
                  sub: '正常推进',
                  color: const Color(0xFF34C759),
                  onTap: () => onRate(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RateButton(
                  label: '卡壳',
                  sub: '升幅减半',
                  color: const Color(0xFFFF9500),
                  onTap: () => onRate(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RateButton(
                  label: '讲不出来',
                  sub: '降档重来',
                  color: const Color(0xFFFF3B30),
                  onTap: () => onRate(1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


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
