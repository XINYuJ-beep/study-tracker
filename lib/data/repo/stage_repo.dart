import '../db/app_database.dart';
import '../db/tables.dart';

/// 阶段任务（听力自测）数据读取。
///
/// 职责边界：只读 `stages` 与 `streams` 两张表，不判分、不解锁、不写表。
/// 「哪些阶段听力已解锁」一律由 QuestionRepo.isModuleListeningUnlocked
/// 判定（按模块完成率 >= AppConstants.moduleUnlockRatio），本类不重复实现。
class StageRepo {
  StageRepo(this.db);

  final AppDatabase db;

  // ---------- stages ----------

  /// 全部阶段任务（按周升序，同周按 id 升序）。
  Future<List<Stage>> allStages() async {
    final rows = await db.query(
      T.stages,
      orderBy: 'week ASC, id ASC',
    );
    return rows.map(Stage.fromMap).toList();
  }

  /// 按模块取阶段任务。module 形如 '01' / '02'。
  Future<List<Stage>> stagesByModule(String module) async {
    final rows = await db.query(
      T.stages,
      where: 'module = ?',
      whereArgs: <Object?>[module],
      orderBy: 'week ASC, id ASC',
    );
    return rows.map(Stage.fromMap).toList();
  }

  /// 按周取阶段任务。
  Future<List<Stage>> stagesByWeek(int week) async {
    final rows = await db.query(
      T.stages,
      where: 'week = ?',
      whereArgs: <Object?>[week],
      orderBy: 'id ASC',
    );
    return rows.map(Stage.fromMap).toList();
  }

  /// 单条阶段任务；id 不存在返回 null。
  Future<Stage?> stageById(int id) async {
    final rows = await db.query(
      T.stages,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Stage.fromMap(rows.first);
  }

  /// 阶段任务总数（自检页用，应等于 AppConstants.expectedStages）。
  Future<int> stageCount() async {
    final rows = await db.raw('SELECT COUNT(*) AS c FROM ${T.stages}');
    return (rows.first['c'] as int?) ?? 0;
  }

  // ---------- streams ----------

  /// 全部主播列表（按 id 升序）。
  Future<List<Stream>> allStreams() async {
    final rows = await db.query(T.streams, orderBy: 'id ASC');
    return rows.map(Stream.fromMap).toList();
  }

  /// 单条主播；id 不存在返回 null。
  Future<Stream?> streamById(int id) async {
    final rows = await db.query(
      T.streams,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Stream.fromMap(rows.first);
  }

  /// 主播总数（自检页用，应等于 AppConstants.expectedStreams）。
  Future<int> streamCount() async {
    final rows = await db.raw('SELECT COUNT(*) AS c FROM ${T.streams}');
    return (rows.first['c'] as int?) ?? 0;
  }
}
