import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../db/app_database.dart';

/// 白板抽到的一张概念卡（随判分结果进入次日复习或推进等级）。
class WhiteboardCard {
  const WhiteboardCard({
    required this.id,
    required this.term,
    required this.definition,
    this.week,
  });

  final int id;
  final String term;
  final String definition;
  final int? week;
}

/// 概念卡：白板抽题、判分排期、复习间隔推进。
class ConceptRepo {
  ConceptRepo(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  // ---------- 白板 ----------
  /// 随机抽 [count] 张「已学」概念卡。
  ///
  /// 已学 = week 非空且 week <= [currentWeek]。
  /// seeder 一次性灌入 92 周概念，若不加周过滤，第 1 周就会抽到末期概念。
  Future<List<WhiteboardCard>> pickWhiteboard(
    int currentWeek, {
    int count = AppConstants.whiteboardCount,
  }) async {
    if (count <= 0) return const <WhiteboardCard>[];
    final rows = await (db.select(db.concepts)
          ..where((t) => t.week.isNotNull() & t.week.isSmallerOrEqualValue(currentWeek)))
        .get();
    if (rows.isEmpty) return const <WhiteboardCard>[];
    final pool = rows.toList()..shuffle(Random());
    final take = pool.length < count ? pool.length : count;
    return pool.take(take).map((e) => WhiteboardCard(
          id: e.id,
          term: e.term,
          definition: e.definition,
          week: e.week,
        )).toList();
  }

  // ---------- 判分 ----------
  /// 白板判分：绿卡推进等级，红/黄卡次日重来。
  ///
  /// [level]：0=红（不会）、1=黄（模糊）、2=绿（掌握）。
  /// 说明：红黄都排到次日，但红卡不清零等级（保持当前 level 不变），
  /// 黄卡同样不清零，只有绿卡推进 —— 这样「蒙对一次」不会白赚 30 天间隔。
  Future<void> gradeWhiteboard(int conceptId, int level) async {
    final row = await (db.select(db.concepts)
          ..where((t) => t.id.equals(conceptId)))
        .getSingleOrNull();
    if (row == null) return;

    final now = _clock();
    if (level >= 2) {
      final next = await _advance(row, now);
      await (db.update(db.concepts)..where((t) => t.id.equals(conceptId)))
          .write(next);
    } else {
      await (db.update(db.concepts)..where((t) => t.id.equals(conceptId))).write(
        ConceptsCompanion(
          dueDate: Value(_startOfDay(now).add(const Duration(days: 1))),
        ),
      );
    }
  }

  // ---------- 复习间隔 ----------
  /// 按 reviewIntervals 推进一张概念卡，返回要写回的字段。
  Future<ConceptsCompanion> _advance(Concepts row, DateTime now) async {
    final intervals = AppConstants.reviewIntervals;
    final curLevel = row.level < 0 ? 0 : row.level;
    final nextLevel = curLevel + 1;

    // 毕业：等级达到 reviewGraduatedStage，dueDate 置空不再出现。
    if (nextLevel >= AppConstants.reviewGraduatedStage) {
      return ConceptsCompanion(
        level: Value(AppConstants.reviewGraduatedStage),
        dueDate: const Value(null),
        reps: Value(row.reps + 1),
      );
    }

    final idx = nextLevel - 1;
    final days = intervals[idx < 0 ? 0 : (idx >= intervals.length ? intervals.length - 1 : idx)];
    return ConceptsCompanion(
      level: Value(nextLevel),
      dueDate: Value(_startOfDay(now).add(Duration(days: days))),
      reps: Value(row.reps + 1),
    );
  }

  // ---------- 查询 ----------
  /// 今天到期（dueDate <= now）的概念卡，按到期时间正序。
  Future<List<Concept>> dueConcepts({int limit = 0}) async {
    final now = _clock();
    final q = db.select(db.concepts)
      ..where((t) => t.dueDate.isNotNull() & t.dueDate.isSmallerOrEqualValue(now))
      ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]);
    if (limit > 0) q.limit(limit);
    return q.get();
  }

  /// 今日到期概念数（今日页角标用）。
  Future<int> dueConceptCount() async {
    final now = _clock();
    final c = db.concepts.id.count();
    final q = db.selectOnly(db.concepts)
      ..addColumns([c])
      ..where(db.concepts.dueDate.isNotNull() &
          db.concepts.dueDate.isSmallerOrEqualValue(now));
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  /// 按周取概念卡（周详情页用）。
  Future<List<Concept>> conceptsByWeek(int week) async {
    return (db.select(db.concepts)
          ..where((t) => t.week.equals(week))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// 关键词搜概念（问号词典用），term 模糊匹配。
  Future<List<Concept>> search(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return const <Concept>[];
    return (db.select(db.concepts)
          ..where((t) => t.term.like('%$k%') | t.definition.like('%$k%'))
          ..limit(50))
        .get();
  }

  /// 全部概念数（自检页用）。
  Future<int> totalCount() async {
    final c = db.concepts.id.count();
    final q = db.selectOnly(db.concepts)..addColumns([c]);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  // ---------- 工具 ----------
  /// 4 点日界：把时间归到「学习日」的零点。
  /// 例：今天 03:30 属于昨天，返回昨天 00:00。
  DateTime _startOfDay(DateTime t) {
    final shifted = t.hour < AppConstants.dayBoundaryHour
        ? t.subtract(const Duration(days: 1))
        : t;
    return DateTime(shifted.year, shifted.month, shifted.day);
  }
}
