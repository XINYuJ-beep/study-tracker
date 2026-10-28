import 'dart:math';

import '../../core/constants.dart';
import '../../core/date_utils.dart';
import '../db/app_database.dart';
import '../db/tables.dart';

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
    final rows = await db.query(
      T.concepts,
      where: 'week IS NOT NULL AND week <= ?',
      whereArgs: <Object?>[currentWeek],
    );
    if (rows.isEmpty) return const <WhiteboardCard>[];
    final pool = rows.map(Concept.fromMap).toList()..shuffle(Random());
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
    final rows = await db.query(
      T.concepts,
      where: 'id = ?',
      whereArgs: <Object?>[conceptId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = Concept.fromMap(rows.first);

    final now = _clock();
    if (level >= 2) {
      final next = _advance(row, now);
      await db.update(
        T.concepts,
        next,
        where: 'id = ?',
        whereArgs: <Object?>[conceptId],
      );
    } else {
      await db.update(
        T.concepts,
        <String, Object?>{
          'due_date': startOfDay(now).add(const Duration(days: 1)).millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[conceptId],
      );
    }
  }

  // ---------- 复习间隔 ----------
  /// 按 reviewIntervals 推进一张概念卡，返回要写回的字段。
  Map<String, Object?> _advance(Concept row, DateTime now) {
    final intervals = AppConstants.reviewIntervals;
    final curLevel = row.level < 0 ? 0 : row.level;
    final nextLevel = curLevel + 1;

    // 毕业：等级达到 reviewGraduatedStage，dueDate 置空不再出现。
    if (nextLevel >= AppConstants.reviewGraduatedStage) {
      return <String, Object?>{
        'level': AppConstants.reviewGraduatedStage,
        'due_date': null,
        'reps': row.reps + 1,
      };
    }

    // 索引即档位：level 与 question_repo 口径一致，同一档取同一间隔。
    final idx = nextLevel < 0 ? 0 : (nextLevel >= intervals.length ? intervals.length - 1 : nextLevel);
    final days = intervals[idx];
    return <String, Object?>{
      'level': nextLevel,
      'due_date': startOfDay(now).add(Duration(days: days)).millisecondsSinceEpoch,
      'reps': row.reps + 1,
    };
  }

  // ---------- 查询 ----------
  /// 今天到期（dueDate <= now）的概念卡，按到期时间正序。
  Future<List<Concept>> dueConcepts({int limit = 0}) async {
    final now = _clock();
    final rows = await db.query(
      T.concepts,
      where: 'due_date IS NOT NULL AND due_date <= ?',
      whereArgs: <Object?>[now.millisecondsSinceEpoch],
      orderBy: 'due_date ASC',
      limit: limit > 0 ? limit : null,
    );
    return rows.map(Concept.fromMap).toList();
  }

  /// 今日到期概念数（今日页角标用）。
  Future<int> dueConceptCount() async {
    final now = _clock();
    final rows = await db.raw(
      'SELECT COUNT(*) AS c FROM ${T.concepts} '
      'WHERE due_date IS NOT NULL AND due_date <= ?',
      <Object?>[now.millisecondsSinceEpoch],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 按周取概念卡（周详情页用）。
  Future<List<Concept>> conceptsByWeek(int week) async {
    final rows = await db.query(
      T.concepts,
      where: 'week = ?',
      whereArgs: <Object?>[week],
      orderBy: 'id ASC',
    );
    return rows.map(Concept.fromMap).toList();
  }

  /// 关键词搜概念（问号词典用），term 模糊匹配。
  Future<List<Concept>> search(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return const <Concept>[];
    final rows = await db.query(
      T.concepts,
      where: 'term LIKE ? OR definition LIKE ?',
      whereArgs: <Object?>['%$k%', '%$k%'],
      limit: 50,
    );
    return rows.map(Concept.fromMap).toList();
  }

  /// 概念题 4 选 1 的题源：随机抽 [count] 张「已学」概念。
  ///
  /// 「已学」口径与 pickWhiteboard 一致：week 非空且 week <= [currentWeek]。
  /// 题干用 definition，正确项用 term，干扰项由页面从同一批池子里取。
  Future<List<Concept>> quizPool(
    int currentWeek, {
    int count = AppConstants.quizPickCount,
  }) async {
    if (count <= 0) return const <Concept>[];
    final rows = await db.query(
      T.concepts,
      where: 'week IS NOT NULL AND week <= ?',
      whereArgs: <Object?>[currentWeek],
    );
    if (rows.isEmpty) return const <Concept>[];
    final pool = rows.map(Concept.fromMap).toList()..shuffle(Random());
    final take = pool.length < count ? pool.length : count;
    return pool.take(take).toList();
  }

  /// 4 选 1 的候选术语池（不含正确项），用于生成干扰项。
  Future<List<String>> otherTerms(Set<int> excludeIds, {int limit = 60}) async {
    final rows = await db.query(T.concepts, orderBy: 'id ASC');
    final out = <String>[];
    for (final r in rows) {
      final id = r['id'] as int;
      if (excludeIds.contains(id)) continue;
      out.add(r['term'] as String);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 全部概念数（自检页用）。
  Future<int> totalCount() async {
    final rows = await db.raw('SELECT COUNT(*) AS c FROM ${T.concepts}');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 全量概念（问号词典 / 全局名词弹卡用）。
  ///
  /// 一次性把 concept 表全部取回，供前端建内存索引做最长匹配。
  /// 当前题库量级约 368 条，单次全量代价可忽略。
  Future<List<Concept>> allConcepts() async {
    final rows = await db.query(T.concepts, orderBy: 'id ASC');
    return rows.map(Concept.fromMap).toList();
  }

}
