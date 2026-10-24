import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../db/app_database.dart';

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

    final cards = await (db.select(db.cards)
          ..where((t) =>
              t.stage.isSmallerThanValue(AppConstants.reviewGraduatedStage) &
              (t.dueDate.isNull() | t.dueDate.isSmallerThanValue(end))))
        .get();

    final concepts = await (db.select(db.concepts)
          ..where((c) =>
              c.level.isSmallerThanValue(AppConstants.reviewGraduatedStage) &
              (c.dueDate.isNull() | c.dueDate.isSmallerThanValue(end))))
        .get();

    final out = <ReviewEntry>[
      for (final c in cards)
        ReviewEntry(
          source: ReviewSource.card,
          id: c.id,
          front: c.front,
          back: c.back,
          stage: c.stage,
          dueDate: c.dueDate,
          week: c.week,
          module: c.module,
        ),
      for (final c in concepts)
        ReviewEntry(
          source: ReviewSource.concept,
          id: c.id.toString(),
          front: c.term,
          back: c.definition,
          stage: c.level,
          dueDate: c.dueDate,
          week: c.week,
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
      final row = await (db.select(db.cards)
            ..where((t) => t.id.equals(entry.id)))
          .getSingleOrNull();
      if (row == null) return;

      var stage = row.stage;
      stage = passed ? stage + 1 : (stage > 0 ? stage - 1 : 0);
      final graduated = stage >= AppConstants.reviewGraduatedStage;

      await (db.update(db.cards)..where((t) => t.id.equals(entry.id))).write(
        CardsCompanion(
          stage: Value(stage),
          dueDate: Value(graduated ? null : _nextDue(stage)),
        ),
      );
      return;
    }

    final cid = int.tryParse(entry.id);
    if (cid == null) return;
    final crow = await (db.select(db.concepts)
          ..where((c) => c.id.equals(cid)))
        .getSingleOrNull();
    if (crow == null) return;

    var level = crow.level;
    level = passed ? level + 1 : (level > 0 ? level - 1 : 0);
    final graduated = level >= AppConstants.reviewGraduatedStage;

    await (db.update(db.concepts)..where((c) => c.id.equals(cid))).write(
      ConceptsCompanion(
        level: Value(level),
        reps: Value(crow.reps + 1),
        dueDate: Value(graduated ? null : _nextDue(level)),
      ),
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
    final q = db.select(db.mcqs);
    if (week != null) {
      q.where((t) => t.week.equals(week));
    }
    final rows = await q.get();
    return rows.map(_toMcq).toList();
  }

  /// 按模块取选择题。
  Future<List<McqQuestion>> mcqsByModule(String module) async {
    final rows = await (db.select(db.mcqs)
          ..where((t) => t.module.equals(module)))
        .get();
    return rows.map(_toMcq).toList();
  }

  McqQuestion _toMcq(Mcq row) {
    var opts = <String>[];
    try {
      final decoded = jsonDecode(row.options);
      if (decoded is List) {
        opts = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      opts = <String>[];
    }
    return McqQuestion(
      id: row.id,
      question: row.question,
      options: opts,
      answer: row.answer,
      wrongCount: row.wrongCount,
      rightStreak: row.rightStreak,
      week: row.week,
      module: row.module,
      explain: row.explain,
    );
  }

  // ---------- 错题 ----------

  /// 错题本：错过的且还没被「连续答对 N 次」清出的题。
  Future<List<McqQuestion>> focusedMcqs({int? week}) async {
    final q = db.select(db.mcqs)
      ..where((t) =>
          t.wrongCount.isBiggerThanValue(0) &
          t.rightStreak.isSmallerThanValue(AppConstants.rightStreakToClear));
    if (week != null) {
      q.where((t) => t.week.equals(week));
    }
    final rows = await q.get();
    return rows.map(_toMcq).toList();
  }

  /// 记录一次作答：对则 rightStreak+1（达到阈值后清出错题本），错则 wrongCount+1 且连对清零。
  Future<void> recordAnswer(String mcqId, bool correct) async {
    final row = await (db.select(db.mcqs)
          ..where((t) => t.id.equals(mcqId)))
        .getSingleOrNull();
    if (row == null) return;

    if (correct) {
      final streak = row.rightStreak + 1;
      await (db.update(db.mcqs)..where((t) => t.id.equals(mcqId))).write(
        McqsCompanion(rightStreak: Value(streak)),
      );
    } else {
      await (db.update(db.mcqs)..where((t) => t.id.equals(mcqId))).write(
        McqsCompanion(
          wrongCount: Value(row.wrongCount + 1),
          rightStreak: const Value(0),
        ),
      );
    }
  }

  // ---------- 解锁判断 ----------

  /// 周是否已解锁测试：该周条目完成比例 >= weekUnlockRatio。
  Future<bool> isWeekTestUnlocked(int week) async {
    final items = await (db.select(db.items)
          ..where((t) => t.week.equals(week)))
        .get();
    if (items.isEmpty) return false;

    final done = await (db.select(db.checkins)
          ..where((t) =>
              t.done.equals(true) &
              t.itemId.isIn(items.map((e) => e.id).toList())))
        .get();

    final ratio = done.length / items.length;
    return ratio >= AppConstants.weekUnlockRatio;
  }

  /// 模块是否已解锁阶段听力：该模块周区间内条目完成比例 >= moduleUnlockRatio。
  ///
  /// Items 表没有 module 字段，模块归属只能按 Modules 顺序累加 weeks
  /// 推出周区间，再用 Items.week 落入区间反查。
  Future<bool> isModuleListeningUnlocked(String module) async {
    final mods = await db.select(db.modules).get();
    if (mods.isEmpty) return false;

    // 按 id 的数值排序，保证 01..08 顺序累加不会因字符串排序错位
    final sorted = mods.toList()
      ..sort((a, b) => _moduleOrder(a.id).compareTo(_moduleOrder(b.id)));

    var startWeek = 1;
    int? from;
    int? to;
    for (final m in sorted) {
      final span = m.weeks;
      final endWeek = startWeek + (span <= 0 ? 0 : span) - 1;
      if (m.id == module) {
        from = startWeek;
        to = endWeek;
        break;
      }
      startWeek = endWeek + 1;
    }
    if (from == null || to == null) return false;

    final items = await (db.select(db.items)
          ..where((t) => t.week.isBetweenValues(from!, to!)))
        .get();
    if (items.isEmpty) return false;

    final done = await (db.select(db.checkins)
          ..where((t) =>
              t.done.equals(true) &
              t.itemId.isIn(items.map((e) => e.id).toList())))
        .get();

    final ratio = done.length / items.length;
    return ratio >= AppConstants.moduleUnlockRatio;
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

DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
