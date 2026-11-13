import 'dart:convert';
import 'dart:math' show Random;

import '../../core/constants.dart';
import '../../core/date_utils.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import 'plan_repo.dart';

/// 复习条目来源：闪卡 或 概念卡。
enum ReviewSource { card, concept }

/// 复习队列里的一个条目（把 cards 与 concepts 归一化后的视图对象）。
class ReviewEntry {
  const ReviewEntry({
    required this.source,
    required this.id,
    required this.front,
    required this.back,
    required this.stage,
    required this.dueDate,
    this.week,
    this.module,
  });

  final ReviewSource source;
  final String id;
  final String front;
  final String back;
  final int stage;
  final DateTime? dueDate;
  final int? week;
  final String? module;

  bool get isGraduated => stage >= AppConstants.reviewGraduatedStage;
}

/// 一道选择题（把库里的 options JSON 解码成列表）。
class McqQuestion {
  const McqQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.answer,
    required this.wrongCount,
    required this.rightStreak,
    this.week,
    this.module,
    this.explain,
    this.sourceRef = '',
  });

  final String id;
  final String question;
  final List<String> options;
  final int answer;
  final int wrongCount;
  final int rightStreak;
  final int? week;
  final String? module;
  final String? explain;

  /// 题目出处，形如 `builtin:questions` / `outline:xxx.md` / `manual`。
  /// 空串表示未知，UI 侧按内置题库兜底。
  final String sourceRef;
}

/// 复习 / 选择题 / 错题 / 解锁判断。
class QuestionRepo {
  QuestionRepo(this.db);

  final AppDatabase db;

  // ---------- 复习队列 ----------

  /// 到期或未排期的闪卡 + 概念卡，合并成一条队列。
  /// [limit] 为 0 表示不限条数。
  Future<List<ReviewEntry>> dueReview({int limit = 0}) async {
    final today = effectiveToday();
    final end = startOfDay(today).add(const Duration(days: 1));
    final endMs = end.millisecondsSinceEpoch;
    final graduate = AppConstants.reviewGraduatedStage;

    final cardRows = await db.query(
      T.cards,
      where: 'stage < ? AND due_date IS NOT NULL AND due_date < ?',
      whereArgs: [graduate, endMs],
    );

    final conceptRows = await db.query(
      T.concepts,
      where: 'level < ? AND due_date IS NOT NULL AND due_date < ?',
      whereArgs: [graduate, endMs],
    );

    final out = <ReviewEntry>[
      for (final r in cardRows)
        ReviewEntry(
          source: ReviewSource.card,
          id: r['id'] as String,
          front: r['front'] as String,
          back: r['back'] as String,
          stage: r['stage'] as int,
          dueDate: _msToDt(r['due_date'] as int?),
          week: r['week'] as int?,
          module: r['module'] as String?,
        ),
      for (final r in conceptRows)
        ReviewEntry(
          source: ReviewSource.concept,
          id: (r['id'] as int).toString(),
          front: r['term'] as String,
          back: r['definition'] as String,
          stage: r['level'] as int,
          dueDate: _msToDt(r['due_date'] as int?),
          week: r['week'] as int?,
        ),
    ];

    out.sort((a, b) {
      final da = a.dueDate;
      final dbb = b.dueDate;
      if (da == null && dbb == null) return a.id.compareTo(b.id);
      if (da == null) return -1;
      if (dbb == null) return 1;
      return da.compareTo(dbb);
    });

    if (limit > 0 && out.length > limit) {
      return out.sublist(0, limit);
    }
    return out;
  }

  /// 提交复习结果。
  /// score >= 3 视为记住，stage 前进一级；否则退回一级（最低 0）。
  /// 到达毕业 stage 后不再排期（dueDate 置 null）。
  Future<void> gradeReview(ReviewEntry entry, int score) async {

    if (entry.source == ReviewSource.card) {
      final rows = await db.query(
        T.cards,
        where: 'id = ?',
        whereArgs: [entry.id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;

      final oldStage = row['stage'] as int;
      final stage = _nextStage(oldStage, score);
      final graduated = stage >= AppConstants.reviewGraduatedStage;

      await db.update(
        T.cards,
        {
          'stage': stage,
          'reps': (row['reps'] as int? ?? 0) + 1,
          'due_date': graduated ? null : _nextDue(stage).millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      return;
    }

    final cid = int.tryParse(entry.id);
    if (cid == null) return;
    final crowRows = await db.query(
      T.concepts,
      where: 'id = ?',
      whereArgs: [cid],
      limit: 1,
    );
    if (crowRows.isEmpty) return;
    final crow = crowRows.first;

    final oldLevel = crow['level'] as int;
    final level = _nextStage(oldLevel, score);
    final graduated = level >= AppConstants.reviewGraduatedStage;

    await db.update(
      T.concepts,
      {
        'level': level,
        'reps': (crow['reps'] as int) + 1,
        'due_date': graduated ? null : _nextDue(level).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [cid],
    );
  }

  /// 三档打分 -> 新档位。
  /// score >= 4（记得）：升一档；
  /// score == 3（模糊）：档位不变，只重置当前档间隔；
  /// score <= 2（忘了）：降一档，下限 0。
  int _nextStage(int stage, int score) {
    final cur = stage < 0 ? 0 : stage;
    if (score >= 4) return cur + 1;
    if (score == 3) return cur;
    return cur > 0 ? cur - 1 : 0;
  }

  /// 按 [stage] 取下一次到期时间；越界时取最后一个间隔。
  DateTime _nextDue(int stage) {
    final list = AppConstants.reviewIntervals;
    final idx = stage < 0
        ? 0
        : (stage >= list.length ? list.length - 1 : stage);
    final days = list[idx];
    return startOfDay(effectiveToday()).add(Duration(days: days));
  }

  /// 今日到期的复习条数（用于首页角标）。
  Future<int> dueReviewCount() async {
    final list = await dueReview();
    return list.length;
  }

  // ---------- 选择题 ----------

  /// 按周取选择题；[week] 为 null 时取全部。
  Future<List<McqQuestion>> mcqsByWeek(int? week) async {
    final rows = await db.query(
      T.mcqs,
      where: week == null ? null : 'week = ?',
      whereArgs: week == null ? null : [week],
    );
    return rows.map(_toMcq).toList();
  }
/// 按模块取选择题。
  Future<List<McqQuestion>> mcqsByModule(String module) async {
    final rows = await db.query(
      T.mcqs,
      where: 'module = ?',
      whereArgs: [module],
    );
    return rows.map(_toMcq).toList();
  }

  /// 【按天投放】取某个条目（= 某周某天）名下的全部选择题。
  ///
  /// 这是「剥夺用户挑题权」的核心入口：UI 只调这一个，
  /// 用户看到的就是 W(n)Dk 那天的固定 6 道，不能提前、不能跨天。
  /// 返回按 id 排序，保证每次打开顺序一致（选项位置在数据侧已打散）。
  Future<List<McqQuestion>> mcqsByItem(String itemId) async {
    if (itemId.isEmpty) return const <McqQuestion>[];
    final rows = await db.query(
      T.mcqs,
      where: 'item_id = ?',
      whereArgs: <Object?>[itemId],
      orderBy: 'id ASC',
    );
    return rows.map(_toMcq).toList();
  }

  /// 【按天投放 + 进度】取某周某天（day 1..7）的题目。
  ///
  /// 给「本周课表」用：一次拿到周一..周日每天的题量与已完成量。
  Future<List<McqQuestion>> mcqsByWeekDay(int week, int day) async {
    if (day < 1 || day > 7) return const <McqQuestion>[];
    final rows = await db.query(
      T.mcqs,
      where: 'week = ? AND day = ?',
      whereArgs: <Object?>[week, day],
      orderBy: 'id ASC',
    );
    return rows.map(_toMcq).toList();
  }

  /// 【SM-2】取今日到期的选择题（含从未答过、stage 未毕业、due_date 已到）。
  ///
  /// 口径与 dueReview() 一致：due_date 为空的老题不进复习队列，
  /// 只有真正答过一次、被写入首次 due_date 之后才进入 SM-2 循环。
  Future<List<McqQuestion>> dueMcqs({int limit = 0}) async {
    final today = effectiveToday();
    final end = startOfDay(today).add(const Duration(days: 1));
    final endMs = end.millisecondsSinceEpoch;
    final rows = await db.raw(
      'SELECT * FROM ${T.mcqs} '
      'WHERE stage < ? AND due_date IS NOT NULL AND due_date < ? '
      'ORDER BY due_date ASC, id ASC',
      <Object?>[AppConstants.reviewGraduatedStage, endMs],
    );
    final list = rows.map(_toMcq).toList();
    if (limit > 0 && list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  /// 【SM-2】今日到期选择题数量（首页角标用，不拉全量）。
  Future<int> dueMcqCount() async {
    final today = effectiveToday();
    final end = startOfDay(today).add(const Duration(days: 1));
    final endMs = end.millisecondsSinceEpoch;
    final rows = await db.raw(
      'SELECT COUNT(*) AS c FROM ${T.mcqs} '
      'WHERE stage < ? AND due_date IS NOT NULL AND due_date < ?',
      <Object?>[AppConstants.reviewGraduatedStage, endMs],
    );
    return (rows.first['c'] as int?) ?? 0;
  }


  McqQuestion _toMcq(Map<String, Object?> r) {
    var opts = <String>[];
    try {
      final decoded = jsonDecode(r['options'] as String);
      if (decoded is List) {
        opts = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      opts = <String>[];
    }
    return McqQuestion(
      id: r['id'] as String,
      question: r['question'] as String,
      options: opts,
      answer: r['answer'] as int,
      wrongCount: r['wrong_count'] as int,
      rightStreak: r['right_streak'] as int,
      week: r['week'] as int?,
      module: r['module'] as String?,
      explain: r['explain'] as String?,
      sourceRef: (r['source_ref'] as String?) ?? '',
    );
  }

  /// 限时模考抽题（缺口④）：从已学范围（week <= maxWeek）随机取 [limit] 道。
  ///
  /// 两条硬约束：
  ///   - 范围严格限在已学周，不出现还没学的题；
  ///   - 随机洗牌在 Dart 侧做，不依赖 SQLite 的 random()（不同平台实现不一致）。
  /// 模考不写 SM-2，故本方法只读，不改任何表。
  Future<List<McqQuestion>> randomWithinWeeks(
    int maxWeek, {
    int limit = 30,
    int? seed,
  }) async {
    if (maxWeek <= 0) return const <McqQuestion>[];
    final rows = await db.query(
      T.mcqs,
      where: 'week IS NOT NULL AND week <= ?',
      whereArgs: <Object?>[maxWeek],
    );
    if (rows.isEmpty) return const <McqQuestion>[];
    final list = rows.map(_toMcq).toList();
    list.shuffle(seed == null ? null : _SeededRandom(seed));
    return list.take(limit).toList();
  }

  /// 缺口②第二道关卡：给自评抽一道「同周不同题」的验证题。
  ///
  /// 返回 null 表示没得验（同周只剩这一道），此时调用方按「未验证」处理，
  /// 自评结果照常生效，不做降级。
  Future<McqQuestion?> pickVerifyMcq(String excludeId, {int? week}) async {
    final rows = await db.query(
      T.mcqs,
      where: week == null
          ? 'id != ?'
          : 'id != ? AND week = ?',
      whereArgs: <Object?>[excludeId, if (week != null) week],
      limit: 60,
    );
    if (rows.isEmpty) return null;
    final list = rows.map(_toMcq).toList()..shuffle();
    return list.first;
  }

  /// 缺口④：模考交卷后落一条成绩。只存结果，不存答题明细。
  Future<void> saveMockExam({
    required int total,
    required int rightCount,
    required int elapsedSeconds,
    required bool timedOut,
  }) async {
    await db.insert(kTableMockExams, <String, Object?>{
      'finished_at': DateTime.now().millisecondsSinceEpoch,
      'total': total,
      'right_count': rightCount,
      'elapsed_seconds': elapsedSeconds,
      'timed_out': timedOut ? 1 : 0,
    });
  }

  /// 批量取这些题的累计错题次数（缺口④模考诊断用）。
  ///
  /// 返回 id -> wrong_count，没记录到的 id 不在 map 里。
  Future<Map<String, int>> wrongCountsFor(List<String> ids) async {
    if (ids.isEmpty) return const <String, int>{};
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    final rows = await db.query(
      T.mcqs,
      columns: <String>['id', 'wrong_count'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final out = <String, int>{};
    for (final r in rows) {
      out[r['id'] as String] = (r['wrong_count'] as int?) ?? 0;
    }
    return out;
  }

  /// 今日考核（按「周-天」投放）：取第 [week] 周第 [day] 天的全部题目。
  ///
  /// 这是「打卡前置考核」的数据源：
  ///   用户听完当天视频 → 打开 App → 点当天 → 做题 → 做完才算打卡。
  /// 返回列表顺序按 id 升序，不洗牌（同一题池重复进入顺序稳定）。
  Future<List<McqQuestion>> todayExam(int week, int day) async {
    if (week <= 0 || day <= 0) return const <McqQuestion>[];
    final rows = await db.query(
      T.mcqs,
      where: 'week = ? AND day = ?',
      whereArgs: <Object?>[week, day],
      orderBy: 'id ASC',
    );
    return rows.map(_toMcq).toList();
  }

  /// 今日考核的完成度：返回 (总题数, 已答对题数, 已答题数)。
  ///
  /// 「已答」口径：self_score > 0（自评过）或 wrong_count > 0（错过）。
  /// 因为打卡要求做完，所以只要每道题都碰过就算完成，不要求全对。
  Future<DayExamProgress> dayExamProgress(int week, int day) async {
    final rows = await db.query(
      T.mcqs,
      columns: <String>['id', 'self_score', 'wrong_count', 'stage'],
      where: 'week = ? AND day = ?',
      whereArgs: <Object?>[week, day],
    );
    var total = 0;
    var touched = 0;
    var right = 0;
    for (final r in rows) {
      total++;
      final int ss = (r['self_score'] as int?) ?? 0;
      final int wc = (r['wrong_count'] as int?) ?? 0;
      final int st = (r['stage'] as int?) ?? 0;
      if (ss > 0 || wc > 0) touched++;
      // 从没错过且已经推过至少一档 = 答对过
      if (wc == 0 && st > 0) right++;
    }
    return DayExamProgress(total: total, touched: touched, right: right);
  }

  // ---------- 错题 ----------

  /// 错题本：错过的且还没被「连续答对 N 次」清出的题。
  Future<List<McqQuestion>> focusedMcqs({int? week}) async {
    final where = week == null
        ? 'wrong_count > ? AND right_streak < ?'
        : 'wrong_count > ? AND right_streak < ? AND week = ?';
    final args = <Object?>[
      0,
      AppConstants.rightStreakToClear,
      if (week != null) week,
    ];
    final rows = await db.query(T.mcqs, where: where, whereArgs: args);
    return rows.map(_toMcq).toList();
  }

  /// 记录一次作答，并推进 SM-2 排程。
  ///
  /// 口径（全库唯一，与 cards / concepts 一致）：
  /// - 答对：right_streak + 1；stage + 1（上限毕业档）；
  ///   stage 达到 7 -> due_date 置空即毕业，不再进入复习队列；
  ///   否则 due_date = 今天 + reviewIntervals[stage-1] 天。
  /// - 答错：wrong_count + 1；right_streak 清零；ease - 0.2（下限 1.3）；
  ///   stage 退回 0（重新从 1 天间隔起步，避免难句越滚越远）。
  ///
  /// 首次作答（stage=0 且 due_date 为空）同样走这条路径，
  /// 于是新题答对第一次就会排到明天，进入复习闭环。
  /// [selfScore] 缺口²「用自己的话讲一遍」自评（方案 A：影响 SM-2）：
  ///   0 / null = 本次没有自评（老调用点、以及走查/复习页不强制自评），行为与改动前完全一致；
  ///   3 讲清了   = 正常升档（同答对既有路径）；
  ///   2 卡壳     = 判「模糊」：档位照常 +1，但 due 间隔取「上一档间隔」与「目标档间隔」
  ///                的中间值，等于升幅减半（升了，但下一次复习提前拉近）；
  ///   1 讲不出来 = 判「忘了」：走答错路径（stage 归 0、ease -0.2、明天再来）。
  /// 只有答对才会传非 0 自评；答错时自评一律按忘了处理，不重复扣分。
  /// [verified] 缺口②第二道关卡：自评结果是否被验证题确认。
  ///   true  = 验证题答对，自评可信，按正常间隔走；
  ///   false = 验证题答错，自评偏乐观，自评档位降一级；
  ///   null  = 没跑验证（同周次题目不足或老调用点）。
  Future<void> recordAnswer(
    String mcqId,
    bool correct, {
    int? selfScore,
    int? failReason,
    bool? verified,
  }) async {
    final rows = await db.query(
      T.mcqs,
      where: 'id = ?',
      whereArgs: <Object?>[mcqId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;

    final int wrongCount = (row['wrong_count'] as int?) ?? 0;
    final int rightStreak = (row['right_streak'] as int?) ?? 0;
    final int stage = (row['stage'] as int?) ?? 0;
    final double ease = (row['ease'] as num?)?.toDouble() ??
        AppConstants.initialEase;

    // 自评档位（v7 四档）：0/空 = 未自评；1 讲不出来；2 关键点绕过；
    // 3 讲了但要停一下；4 讲清了。旧值 3（原「讲清了」）语义向后兼容。
    final int score = (selfScore ?? 0).clamp(0, 4);
    // 实际判定用的「对错」：答对但自评讲不出来 -> 视为忘了。
    // 验证题降级：自评说「讲清了」但验证题答错 -> 降到「要停一下」。
    // 验证题答对不升级（不因为一次碰对就当成完全掌握）。
    int rawScore = score;
    if (verified == false && rawScore >= 3) rawScore = rawScore - 1;
    final int effScore = rawScore;

    final bool effectiveCorrect = correct && effScore != 1;
    // 模糊：答对但自评 2（关键点绕过）或 3（要停一下）-> 升幅打折。
    // 2 = 打五折（间隔取上一档与目标档的中值）；3 = 打八折。
    final bool fuzzy = correct && (effScore == 2 || effScore == 3);
    // 模糊折扣系数：2 -> 0.5，3 -> 0.8，其余 1.0。
    final double fuzzyFactor = effScore == 2
        ? 0.5
        : (effScore == 3 ? 0.8 : 1.0);
    final Map<String, Object?> selfPatch = score == 0
        ? const <String, Object?>{}
        : <String, Object?>{
            'self_score': effScore,
            if (verified != null) 'self_verified': verified ? 1 : 0,
          };

    // 错因归因（缺口③）：0 = 未标记；1 看不懂题 / 2 知识点没记住 / 3 记混了 / 4 想陷了。
    // 只记录，不参与 SM-2 排程（方案 A）——它是诊断数据，不是排程因子。
    final int reason = (failReason ?? 0).clamp(0, 4);
    final Map<String, Object?> reasonPatch = reason == 0
        ? const <String, Object?>{}
        : <String, Object?>{'fail_reason': reason};

    // 缺口③历史累积：每次选了错因就追加一条事件，不覆盖旧记录。
    // mcqs.fail_reason 保留作「最新一次」快查，两者各司其职。
    if (!effectiveCorrect && reason > 0) {
      await db.insert(kTableFailEvents, <String, Object?>{
        'mcq_id': mcqId,
        'reason': reason,
        'week': row['week'],
        'module': row['module'],
        'answered_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    if (effectiveCorrect) {
      final int nextStreak = rightStreak + 1;
      final int nextStage = stage + 1;
      if (nextStage >= AppConstants.reviewGraduatedStage) {
        // 毕业：不再排期
        await db.update(
          T.mcqs,
          <String, Object?>{
            'right_streak': nextStreak,
            'stage': AppConstants.reviewGraduatedStage,
            'due_date': null,
            ...selfPatch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[mcqId],
        );
      } else {
        // 档位越界保护：reviewIntervals 长度 = reviewGraduatedStage
        // 卡壳（fuzzy）：档位只 +1（不减半跳级），间隔取上一档与目标档的中间值，
        // 等价于「升幅减半」：升了，但把下一次复习提前拉近。
        final int idx = nextStage - 1;
        final int full = AppConstants.reviewIntervals[idx];
        final int prev = stage <= 0
            ? 1
            : AppConstants.reviewIntervals[(stage - 1).clamp(
                0,
                AppConstants.reviewIntervals.length - 1)];
        // 模糊折扣：按 fuzzyFactor 在「上一档间隔 → 目标档间隔」之间插值，
        // 2 → 取中点，3 → 取 80% 处，不模糊 → 取满值。
        final int days = fuzzy
            ? (prev + ((full - prev) * fuzzyFactor).round()).clamp(1, full)
            : full;
        final int dueMs = startOfDay(
          effectiveToday(),
        ).add(Duration(days: days)).millisecondsSinceEpoch;
        await db.update(
          T.mcqs,
          <String, Object?>{
            'right_streak': nextStreak,
            'stage': nextStage,
            'due_date': dueMs,
            ...selfPatch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[mcqId],
        );
      }
    } else {
      final double nextEase = (ease - AppConstants.easePenalty) <
              AppConstants.easeMin
          ? AppConstants.easeMin
          : ease - AppConstants.easePenalty;
      final int dueMs = startOfDay(
        effectiveToday(),
      ).add(const Duration(days: 1)).millisecondsSinceEpoch;
      await db.update(
        T.mcqs,
        <String, Object?>{
          'wrong_count': wrongCount + 1,
          'right_streak': 0,
          'stage': 0,
          'ease': nextEase,
          'due_date': dueMs,
          ...selfPatch,
          ...reasonPatch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[mcqId],
      );
    }
  }

  // ---------- 解锁判断 ----------

  /// 周是否已解锁测试：该周条目完成比例 >= weekUnlockRatio。
  Future<bool> isWeekTestUnlocked(int week) async {
    final items = await db.query(
      T.items,
      where: 'week = ?',
      whereArgs: [week],
    );
    if (items.isEmpty) return false;

    final ids = items.map((e) => e['id'] as String).toList();
    final doneCount = await _doneCountOf(ids);

    final ratio = doneCount / items.length;
    return ratio >= AppConstants.weekUnlockRatio;
  }

  /// 模块是否已解锁阶段听力：该模块周区间内条目完成比例 >= moduleUnlockRatio。
  ///
  /// Items 表没有 module 字段，模块归属只能按 Modules 顺序累加 weeks
  /// 推出周区间，再用 Items.week 落入区间反查。
  /// 模块完成率（0.0 ~ 1.0）：该模块周区间内 items 的打卡比例。
  ///
  /// 阶段听力的解锁判定与进度展示共用这一个口径，避免两处各算一套。
  Future<double> moduleProgress(String module) async {
    final mods = await db.query(T.modules, orderBy: 'id ASC');
    if (mods.isEmpty) return 0;
    final sorted = mods.toList()
      ..sort((a, b) => _moduleOrder(a['id'] as String)
          .compareTo(_moduleOrder(b['id'] as String)));
    var startWeek = 1;
    int? from;
    int? to;
    for (final m in sorted) {
      final span = m['weeks'] as int;
      final endWeek = startWeek + (span <= 0 ? 0 : span) - 1;
      if (m['id'] as String == module) {
        from = startWeek;
        to = endWeek;
        break;
      }
      startWeek = endWeek + 1;
    }
    if (from == null || to == null) return 0;
    final items = await db.query(
      T.items,
      where: 'week >= ? AND week <= ?',
      whereArgs: [from, to],
    );
    if (items.isEmpty) return 0;
    final ids = items.map((e) => e['id'] as String).toList();
    final doneCount = await _doneCountOf(ids);
    return doneCount / items.length;
  }

  Future<bool> isModuleListeningUnlocked(String module) async {
    final mods = await db.query(T.modules, orderBy: 'id ASC');
    if (mods.isEmpty) return false;

    // 按 id 的数值排序，保证 01..08 顺序累加不会因字符串排序错位
    final sorted = mods.toList()
      ..sort((a, b) => _moduleOrder(a['id'] as String)
          .compareTo(_moduleOrder(b['id'] as String)));

    var startWeek = 1;
    int? from;
    int? to;
    for (final m in sorted) {
      final span = m['weeks'] as int;
      final endWeek = startWeek + (span <= 0 ? 0 : span) - 1;
      if (m['id'] as String == module) {
        from = startWeek;
        to = endWeek;
        break;
      }
      startWeek = endWeek + 1;
    }
    if (from == null || to == null) return false;

    final items = await db.query(
      T.items,
      where: 'week >= ? AND week <= ?',
      whereArgs: [from, to],
    );
    if (items.isEmpty) return false;

    final ids = items.map((e) => e['id'] as String).toList();
    final doneCount = await _doneCountOf(ids);

    final ratio = doneCount / items.length;
    return ratio >= AppConstants.moduleUnlockRatio;
  }

  /// 统计一批 item id 里已打卡（done=1）的条数。
  /// 空列表直接返回 0，避免拼出 `IN ()` 这种非法 SQL。
  Future<int> _doneCountOf(List<String> itemIds) async {
    if (itemIds.isEmpty) return 0;
    final placeholders = List<String>.filled(itemIds.length, '?').join(', ');
    final rows = await db.raw(
      'SELECT COUNT(*) AS c FROM ${T.checkins} '
      'WHERE done = ? AND item_id IN ($placeholders)',
      [1, ...itemIds],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 模块 id 转排序键：纯数字按数值，非数字退化为极大值排到末尾。
  static int _moduleOrder(String id) {
    final n = int.tryParse(id);
    if (n != null) return n;
    final digits = RegExp(r'\d+').firstMatch(id)?.group(0);
    final m = digits == null ? null : int.tryParse(digits);
    return m ?? 9999;
  }

}

DateTime? _msToDt(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

/// 极简可复现随机源：只为了模考抽题能固定种子（测试/复现用）。
/// 不传种子时走 list.shuffle(null)，用的是 Random 默认实现。
class _SeededRandom implements Random {
  _SeededRandom(int seed) : _r = Random(seed);

  final Random _r;

  @override
  bool nextBool() => _r.nextBool();

  @override
  double nextDouble() => _r.nextDouble();

  @override
  int nextInt(int max) => _r.nextInt(max);
}

/// 某一天考核的完成度。
class DayExamProgress {
  const DayExamProgress({
    required this.total,
    required this.touched,
    required this.right,
  });

  /// 这一天共有多少题
  final int total;

  /// 已经碰过的题数（自评过或错过）
  final int touched;

  /// 答对过的题数（没错过且至少推过一档）
  final int right;

  bool get done => total > 0 && touched >= total;
  int get percent => total == 0 ? 0 : (touched / total * 100).round();
}
