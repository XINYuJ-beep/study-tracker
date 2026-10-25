import 'dart:convert';

import '../../core/constants.dart';
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
    final end = _startOfDay(today).add(const Duration(days: 1));
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
    final passed = score >= 3;

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
      var stage = oldStage;
      stage = passed ? stage + 1 : (stage > 0 ? stage - 1 : 0);
      final graduated = stage >= AppConstants.reviewGraduatedStage;

      await db.update(
        T.cards,
        {
          'stage': stage,
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
    var level = oldLevel;
    level = passed ? level + 1 : (level > 0 ? level - 1 : 0);
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

  /// 按 [stage] 取下一次到期时间；越界时取最后一个间隔。
  DateTime _nextDue(int stage) {
    final list = AppConstants.reviewIntervals;
    final idx = stage < 0
        ? 0
        : (stage >= list.length ? list.length - 1 : stage);
    final days = list[idx];
    return _startOfDay(effectiveToday()).add(Duration(days: days));
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
    );
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

  /// 记录一次作答：对则 rightStreak+1（达到阈值后清出错题本），错则 wrongCount+1 且连对清零。
  Future<void> recordAnswer(String mcqId, bool correct) async {
    final rows = await db.query(
      T.mcqs,
      where: 'id = ?',
      whereArgs: [mcqId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;

    if (correct) {
      final streak = (row['right_streak'] as int) + 1;
      await db.update(
        T.mcqs,
        {'right_streak': streak},
        where: 'id = ?',
        whereArgs: [mcqId],
      );
    } else {
      await db.update(
        T.mcqs,
        {
          'wrong_count': (row['wrong_count'] as int) + 1,
          'right_streak': 0,
        },
        where: 'id = ?',
        whereArgs: [mcqId],
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

  /// 抹掉时分秒，只留当天零点。
  /// 注意：本方法为库私有（`_` 开头），跨文件不可见，
  /// 所以此处保留一份类内实现；后续统一抽到 core/date_utils.dart。
  DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
}

DateTime? _msToDt(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
