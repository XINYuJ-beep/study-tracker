/// 测试页 P1 补充：概念题 / 旧题抽查 / 白板抽背 / 阶段听力。
/// 对应 SPEC 4.3 后四条。
///
/// 设计口径：
///   - 本文件只做 UI 与流程控制，不写 SQL，全部走 repo。
///   - 概念题：concepts 随机 10 题 4 选 1，8 题过。
///   - 旧题抽查：错题优先 10 题，7 题过。
///   - 白板抽背：已学概念随机 10 个，60 秒/个，自评红黄绿，绿 >= 7 过。
///   - 阶段听力：8 个阶段，模块完成率 >= 80% 解锁（判定在 QuestionRepo）。
///
/// 【概念题判分口径】
/// 4 选 1 答对只是抽认命中，不等于白板能默写，所以：
///   - 答错：按 gradeWhiteboard(id, 0) 记为红卡，排到次日重现；
///   - 答对：不动 concepts 的 SRS 档位（不推进）。
/// 避免一次抽认命中就白赚一个复习间隔。
library;

// 本文件用到 Timer；hide Stream 避免与 tables.dart 的 Stream 模型名冲突。
import 'dart:async' hide Stream;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/providers.dart';
import '../../data/db/tables.dart';
import '../../data/repo/concept_repo.dart';
import '../../data/repo/question_repo.dart';

/// 四个模块各自的阶段。
enum _Phase { idle, running, finished }

// ============================================================
// 壳：四个模块的 Tab 入口
// ============================================================
class QaExtraPage extends ConsumerStatefulWidget {
  const QaExtraPage({super.key});

  @override
  ConsumerState<QaExtraPage> createState() => _QaExtraPageState();
}

class _QaExtraPageState extends ConsumerState<QaExtraPage> {
  int _tab = 0;

  static const List<String> _labels = <String>[
    '概念题',
    '旧题抽查',
    '白板抽背',
    '阶段听力',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < _labels.length; i++) ...<Widget>[
                _Chip(
                  label: _labels[i],
                  selected: _tab == i,
                  onTap: () => setState(() => _tab = i),
                ),
                if (i != _labels.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const <Widget>[
              _ConceptQuizView(),
              _SpotCheckView(),
              _WhiteboardView(),
              _ListeningView(),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 1. 概念题 4 选 1
// ============================================================
class _QuizItem {
  const _QuizItem({
    required this.conceptId,
    required this.prompt,
    required this.options,
    required this.answer,
    this.week,
  });

  final int conceptId;
  final String prompt;
  final List<String> options;
  final int answer;
  final int? week;
}

class _ConceptQuizView extends ConsumerStatefulWidget {
  const _ConceptQuizView();

  @override
  ConsumerState<_ConceptQuizView> createState() => _ConceptQuizViewState();
}

class _ConceptQuizViewState extends ConsumerState<_ConceptQuizView> {
  _Phase _phase = _Phase.idle;
  bool _loading = false;
  String? _error;

  List<_QuizItem> _items = const <_QuizItem>[];
  int _index = 0;
  int _picked = -1;
  bool _answered = false;
  int _right = 0;
  int _currentWeek = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_start);
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _items = const <_QuizItem>[];
    });

    int week;
    List<_QuizItem> items;
    try {
      final planRepo = ref.read(planRepoProvider);
      final conceptRepo = ref.read(conceptRepoProvider);
      week = await planRepo.progressiveCursorWeek();
      final concepts =
          await conceptRepo.quizPool(week, count: AppConstants.quizPickCount);
      if (concepts.length < 4) {
        throw StateError('已学概念不足 4 个，凑不出 4 选 1');
      }
      final exclude = concepts.map((e) => e.id).toSet();
      final distractors = await conceptRepo.otherTerms(exclude, limit: 80);
      if (distractors.length < 3) {
        throw StateError('可作干扰项的概念不足 3 个');
      }

      final rnd = Random();
      items = <_QuizItem>[];
      for (final c in concepts) {
        final opts = <String>[c.term];
        final pool = List<String>.of(distractors)..shuffle(rnd);
        for (final d in pool) {
          if (opts.length >= 4) break;
          if (opts.contains(d)) continue;
          opts.add(d);
        }
        opts.shuffle(rnd);
        items.add(_QuizItem(
          conceptId: c.id,
          prompt: c.definition,
          options: opts,
          answer: opts.indexOf(c.term),
          week: c.week,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _phase = _Phase.idle;
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = items;
      _currentWeek = week;
      _index = 0;
      _picked = -1;
      _answered = false;
      _right = 0;
      _phase = _Phase.running;
    });
  }

  Future<void> _submit() async {
    if (_answered || _picked < 0) return;
    final item = _items[_index];
    final ok = _picked == item.answer;
    setState(() {
      _answered = true;
      if (ok) _right++;
    });
    if (!ok) {
      try {
        await ref.read(conceptRepoProvider).gradeWhiteboard(item.conceptId, 0);
      } catch (_) {
        // 记账失败不阻断答题流程。
      }
    }
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _items.length) {
        _phase = _Phase.finished;
      } else {
        _index++;
        _picked = -1;
        _answered = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _HintBlock(
        icon: Icons.help_outline,
        title: '暂不可用',
        subtitle: _error!,
        actionLabel: '重新加载',
        onAction: _start,
      );
    }
    if (_phase == _Phase.finished) {
      final total = _items.length;
      final pass = _right >= AppConstants.quizPassCount;
      return _ResultBlock(
        pass: pass,
        title: pass ? '通过' : '未通过',
        detail: '答对 $_right / $total，通过线 ${AppConstants.quizPassCount} 题',
        note: '答错的概念已记为红卡，明日重现',
        actionLabel: '再来一组',
        onAction: _start,
      );
    }
    if (_phase == _Phase.idle) {
      return _HintBlock(
        icon: Icons.quiz_outlined,
        title: '概念题',
        subtitle: '从已学概念随机抽 ${AppConstants.quizPickCount} 题做 4 选 1，'
            '答对 ${AppConstants.quizPassCount} 题算过',
        actionLabel: '开始',
        onAction: _start,
      );
    }

    final item = _items[_index];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              Text('已学至第 $_currentWeek 周', style: theme.textTheme.bodySmall),
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
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('这条解释说的是哪个概念？', style: theme.textTheme.labelMedium),
                const SizedBox(height: 10),
                Text(
                  item.prompt,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < item.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(
                label: String.fromCharCode(65 + i),
                text: item.options[i],
                selected: _picked == i,
                correct: _answered && i == item.answer,
                wrong: _answered && _picked == i && i != item.answer,
                onTap: _answered ? null : () => setState(() => _picked = i),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _answered ? _next : (_picked < 0 ? null : _submit),
              child: Text(
                !_answered
                    ? '提交'
                    : (_index + 1 >= _items.length ? '交卷' : '下一题'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 2. 旧题抽查（错题优先，10 题 7 过）
// ============================================================
class _SpotCheckView extends ConsumerStatefulWidget {
  const _SpotCheckView();

  @override
  ConsumerState<_SpotCheckView> createState() => _SpotCheckViewState();
}

class _SpotCheckViewState extends ConsumerState<_SpotCheckView> {
  _Phase _phase = _Phase.idle;
  bool _loading = false;
  String? _error;

  List<McqQuestion> _items = const <McqQuestion>[];
  int _index = 0;
  int _picked = -1;
  bool _answered = false;
  int _right = 0;
  int _wrongPoolSize = 0;
  int _currentWeek = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_start);
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _items = const <McqQuestion>[];
    });

    List<McqQuestion> picked;
    int wrongPool;
    int week;
    try {
      final planRepo = ref.read(planRepoProvider);
      final qRepo = ref.read(questionRepoProvider);
      week = await planRepo.progressiveCursorWeek();

      // 错题池：wrong_count > 0 且 right_streak 未达清除阈值。
      final focused = await qRepo.focusedMcqs();
      wrongPool = focused.length;

      final seen = <String>{};
      picked = <McqQuestion>[];
      for (final q in focused) {
        if (seen.add(q.id)) picked.add(q);
        if (picked.length >= AppConstants.spotCheckCount) break;
      }

      // 错题不足时，用已学周次的普通题补齐，排名靠后的放后面。
      if (picked.length < AppConstants.spotCheckCount) {
        final extra = <McqQuestion>[];
        for (var w = 1; w <= week; w++) {
          final list = await qRepo.mcqsByWeek(w);
          for (final q in list) {
            if (seen.add(q.id)) extra.add(q);
          }
        }
        extra.shuffle();
        for (final q in extra) {
          if (picked.length >= AppConstants.spotCheckCount) break;
          picked.add(q);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _phase = _Phase.idle;
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = picked;
      _wrongPoolSize = wrongPool;
      _currentWeek = week;
      _index = 0;
      _picked = -1;
      _answered = false;
      _right = 0;
      _phase = picked.isEmpty ? _Phase.idle : _Phase.running;
      if (picked.isEmpty) _error = '还没有可抽查的题，先把已学周次的选择题做过一遍';
    });
  }

  Future<void> _submit() async {
    if (_answered || _picked < 0) return;
    final q = _items[_index];
    final ok = _picked == q.answer;
    setState(() {
      _answered = true;
      if (ok) _right++;
    });
    try {
      await ref.read(questionRepoProvider).recordAnswer(q.id, ok);
    } catch (_) {
      // 记账失败不阻断流程。
    }
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _items.length) {
        _phase = _Phase.finished;
      } else {
        _index++;
        _picked = -1;
        _answered = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _HintBlock(
        icon: Icons.filter_alt_outlined,
        title: '旧题抽查',
        subtitle: _error!,
        actionLabel: '重新检查',
        onAction: _start,
      );
    }
    if (_phase == _Phase.finished) {
      final total = _items.length;
      final pass = _right >= AppConstants.spotCheckPassCount;
      return _ResultBlock(
        pass: pass,
        title: pass ? '通过' : '未通过',
        detail: '答对 $_right / $total，通过线 ${AppConstants.spotCheckPassCount} 题',
        note: '连对 ${AppConstants.rightStreakToClear} 次的题会自动退出错题本',
        actionLabel: '再抽一轮',
        onAction: _start,
      );
    }
    if (_phase == _Phase.idle) {
      return _HintBlock(
        icon: Icons.filter_alt_outlined,
        title: '旧题抽查',
        subtitle: '错题优先抽 ${AppConstants.spotCheckCount} 题，'
            '答对 ${AppConstants.spotCheckPassCount} 题算过',
        actionLabel: '开始',
        onAction: _start,
      );
    }

    final q = _items[_index];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              Text('错题池 $_wrongPoolSize 题', style: theme.textTheme.bodySmall),
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
          const SizedBox(height: 20),
          Text(
            q.question,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionTile(
                label: String.fromCharCode(65 + i),
                text: q.options[i],
                selected: _picked == i,
                correct: _answered && i == q.answer,
                wrong: _answered && _picked == i && i != q.answer,
                onTap: _answered ? null : () => setState(() => _picked = i),
              ),
            ),
          if (_answered && q.explain != null && q.explain!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _ExplainBox(text: q.explain!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _answered ? _next : (_picked < 0 ? null : _submit),
              child: Text(
                !_answered
                    ? '提交'
                    : (_index + 1 >= _items.length ? '交卷' : '下一题'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 3. 白板抽背（10 个 / 60 秒 / 绿 >= 7 过）
// ============================================================
class _WhiteboardView extends ConsumerStatefulWidget {
  const _WhiteboardView();

  @override
  ConsumerState<_WhiteboardView> createState() => _WhiteboardViewState();
}

class _WhiteboardViewState extends ConsumerState<_WhiteboardView> {
  _Phase _phase = _Phase.idle;
  bool _loading = false;
  String? _error;

  List<WhiteboardCard> _cards = const <WhiteboardCard>[];
  int _index = 0;
  bool _revealed = false;
  int _green = 0;
  int _yellow = 0;
  int _red = 0;

  Timer? _timer;
  int _left = AppConstants.whiteboardSeconds;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_loading) return;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _cards = const <WhiteboardCard>[];
    });

    List<WhiteboardCard> cards;
    try {
      final week = await ref.read(planRepoProvider).progressiveCursorWeek();
      cards = await ref
          .read(conceptRepoProvider)
          .pickWhiteboard(week, count: AppConstants.whiteboardCount);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _phase = _Phase.idle;
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _cards = cards;
      _index = 0;
      _revealed = false;
      _green = 0;
      _yellow = 0;
      _red = 0;
      _left = AppConstants.whiteboardSeconds;
      _phase = cards.isEmpty ? _Phase.idle : _Phase.running;
      if (cards.isEmpty) _error = '还没有已学概念，先在计划页把本周条目学完';
    });
    if (cards.isNotEmpty) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _left--;
        if (_left <= 0) {
          _left = 0;
          t.cancel();
        }
      });
    });
  }

  Future<void> _grade(int level) async {
    if (_phase != _Phase.running) return;
    final card = _cards[_index];
    setState(() {
      if (level >= 2) {
        _green++;
      } else if (level == 1) {
        _yellow++;
      } else {
        _red++;
      }
    });
    if (_index + 1 >= _cards.length) {
      _timer?.cancel();
      setState(() => _phase = _Phase.finished);
    } else {
      setState(() {
        _index++;
        _revealed = false;
        _left = AppConstants.whiteboardSeconds;
      });
      _startTimer();
    }
    try {
      await ref.read(conceptRepoProvider).gradeWhiteboard(card.id, level);
    } catch (_) {
      // 记账失败不阻断推进。
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cards.isEmpty) {
      return _HintBlock(
        icon: Icons.edit_note,
        title: '白板抽背',
        subtitle: _error!,
        actionLabel: '重新抽题',
        onAction: _start,
      );
    }
    if (_phase == _Phase.finished) {
      final total = _cards.length;
      final pass = _green >= AppConstants.whiteboardPassCount;
      return _ResultBlock(
        pass: pass,
        title: pass ? '通过' : '未通过',
        detail: '绿 $_green · 黄 $_yellow · 红 $_red（共 $total 个）',
        note: '绿卡通过线 ${AppConstants.whiteboardPassCount} 个，绿卡会推进复习档位',
        actionLabel: '再抽一轮',
        onAction: _start,
      );
    }
    if (_phase == _Phase.idle) {
      return _HintBlock(
        icon: Icons.edit_note,
        title: '白板抽背',
        subtitle: '已学概念随机 ${AppConstants.whiteboardCount} 个，'
            '每个 ${AppConstants.whiteboardSeconds} 秒，'
            '自评红黄绿，绿 >= ${AppConstants.whiteboardPassCount} 个算过',
        actionLabel: '开始',
        onAction: _start,
      );
    }

    final card = _cards[_index];
    final ratio = _left / AppConstants.whiteboardSeconds;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '第 ${_index + 1} / ${_cards.length} 个',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                '$_left 秒',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: _left <= 10 ? theme.colorScheme.error : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: ratio, minHeight: 6),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('白板题', style: theme.textTheme.labelMedium),
                    const SizedBox(width: 8),
                    if (card.week != null)
                      Text('第 ${card.week} 周', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  card.term,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (_revealed)
                  Text(
                    card.definition,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                  )
                else
                  TextButton.icon(
                    onPressed: () => setState(() => _revealed = true),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('看答案'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: _GradeButton(
                  label: '红',
                  hint: '不会',
                  color: theme.colorScheme.error,
                  onTap: () => _grade(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GradeButton(
                  label: '黄',
                  hint: '模糊',
                  color: const Color(0xFFFF9500),
                  onTap: () => _grade(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _GradeButton(
                  label: '绿',
                  hint: '掌握',
                  color: const Color(0xFF34C759),
                  onTap: () => _grade(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '本轮 绿 $_green · 黄 $_yellow · 红 $_red',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 4. 阶段听力（8 个阶段，模块完成率 >= 80% 解锁）
// ============================================================
class _StageEntry {
  const _StageEntry({
    required this.stage,
    required this.moduleTitle,
    required this.progress,
    required this.unlocked,
  });

  final Stage stage;
  final String moduleTitle;
  final double progress;
  final bool unlocked;
}

class _ListeningView extends ConsumerStatefulWidget {
  const _ListeningView();

  @override
  ConsumerState<_ListeningView> createState() => _ListeningViewState();
}

class _ListeningViewState extends ConsumerState<_ListeningView> {
  bool _loading = true;
  String? _error;
  List<_StageEntry> _entries = const <_StageEntry>[];
  List<Stream> _streams = const <Stream>[];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    List<_StageEntry> entries;
    List<Stream> streams;
    try {
      final stageRepo = ref.read(stageRepoProvider);
      final qRepo = ref.read(questionRepoProvider);
      final planRepo = ref.read(planRepoProvider);

      final stages = await stageRepo.allStages();
      final modules = await planRepo.allModules();
      streams = await stageRepo.allStreams();

      final titleOf = <String, String>{};
      for (final m in modules) {
        titleOf[m.id] = m.title;
      }

      final progressOf = <String, double>{};
      entries = <_StageEntry>[];
      for (final st in stages) {
        final key = st.module;
        var p = progressOf[key];
        if (p == null) {
          p = await qRepo.moduleProgress(key);
          progressOf[key] = p;
        }
        final unlocked = await qRepo.isModuleListeningUnlocked(key);
        entries.add(_StageEntry(
          stage: st,
          moduleTitle: titleOf[key] ?? '模块 $key',
          progress: p,
          unlocked: unlocked,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries = entries;
      _streams = streams;
    });
  }

  void _openDetail(_StageEntry e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _StageSheet(
        entry: e,
        streams: _streams,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _HintBlock(
        icon: Icons.headphones_outlined,
        title: '阶段听力',
        subtitle: _error!,
        actionLabel: '重新加载',
        onAction: _load,
      );
    }
    if (_entries.isEmpty) {
      return _HintBlock(
        icon: Icons.headphones_outlined,
        title: '没有阶段任务',
        subtitle: '数据源缺少 stages 内容，检查导入是否完成',
        actionLabel: '重新加载',
        onAction: _load,
      );
    }

    final unlockedCount = _entries.where((e) => e.unlocked).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '已解锁 $unlockedCount / ${_entries.length}',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            Text(
              '解锁线 ${(AppConstants.moduleUnlockRatio * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final e in _entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StageTile(
              entry: e,
              onTap: e.unlocked ? () => _openDetail(e) : null,
            ),
          ),
        if (_streams.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text('主播列表（共 ${_streams.length}）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final s in _streams)
                Chip(
                  label: Text(s.name),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ============================================================
// 组件层
// ============================================================
class _Chip extends StatelessWidget {
  const _Chip({
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

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.text,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var border = theme.colorScheme.outlineVariant;
    var bg = Colors.transparent;
    if (correct) {
      border = theme.colorScheme.primary;
      bg = theme.colorScheme.primary.withValues(alpha: 0.08);
    } else if (wrong) {
      border = theme.colorScheme.error;
      bg = theme.colorScheme.error.withValues(alpha: 0.08);
    } else if (selected) {
      border = theme.colorScheme.primary;
      bg = theme.colorScheme.primary.withValues(alpha: 0.05);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
          color: bg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Text(label, style: theme.textTheme.labelSmall),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String hint;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.08),
        ),
        child: Column(
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(hint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ExplainBox extends StatelessWidget {
  const _ExplainBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('解析', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _HintBlock extends StatelessWidget {
  const _HintBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({
    required this.pass,
    required this.title,
    required this.detail,
    required this.note,
    required this.actionLabel,
    required this.onAction,
  });

  final bool pass;
  final String title;
  final String detail;
  final String note;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              pass ? Icons.verified : Icons.error_outline,
              size: 56,
              color: pass ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              note,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.entry, this.onTap});

  final _StageEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = entry.stage;
    final unlocked = entry.unlocked;
    final percent = (entry.progress * 100).clamp(0, 100).toStringAsFixed(0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unlocked
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
          color: unlocked
              ? theme.colorScheme.primary.withValues(alpha: 0.04)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  unlocked ? '可测' : '未解锁',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: unlocked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    st.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '第 ${st.week} 周 · ${entry.moduleTitle}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: entry.progress.clamp(0.0, 1.0),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              unlocked
                  ? '模块完成 $percent%'
                  : '模块完成 $percent%，达 '
                      '${(AppConstants.moduleUnlockRatio * 100).round()}% 解锁',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StageSheet extends StatelessWidget {
  const _StageSheet({required this.entry, required this.streams});

  final _StageEntry entry;
  final List<Stream> streams;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = entry.stage;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(st.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '第 ${st.week} 周 · ${entry.moduleTitle}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            _SheetField(label: '在哪里听', value: st.whereAt),
            _SheetField(label: '任务', value: st.task),
            _SheetField(label: '通过标准', value: st.pass),
            if (streams.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text('可选主播', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final s in streams)
                    Chip(
                      label: Text(s.name),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
