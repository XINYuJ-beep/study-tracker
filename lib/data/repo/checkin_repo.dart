import '../../core/constants.dart';
import '../db/app_database.dart';
import '../db/tables.dart';
import 'plan_repo.dart';

/// 某一天（以凌晨 4 点为日界）的打卡汇总。
class DaySummary {
  const DaySummary({
    required this.day,
    required this.doneItems,
    required this.doneMinutes,
  });

  final DateTime day;
  final int doneItems;
  final int doneMinutes;

  bool get isEmpty => doneItems == 0;
}

/// 打卡数据访问：勾选/取消勾选、按日查询、区间统计。
class CheckinRepo {
  CheckinRepo(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  // ---------- 写入 ----------

  /// 勾选或取消勾选某个条目（某一日）。
  ///
  /// checkins 是 (item_id, date) 联合主键，没有自增 id，
  /// 所以必须走 INSERT ... ON CONFLICT REPLACE，重复调用不会插重复行。
  /// [day] 会先被归一化到「4 点日界当天」的零点。
  Future<void> setDone(
    String itemId,
    DateTime day, {
    required bool done,
  }) async {
    final stamp = _startOfDay(_normalize(day));
    await db.insert(
      T.checkins,
      <String, Object?>{
        'item_id': itemId,
        'date': stamp.millisecondsSinceEpoch,
        'done': done ? 1 : 0,
        'completed_at': done ? _clock().millisecondsSinceEpoch : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 勾选，等价于 setDone(..., done: true)。
  Future<void> check(String itemId, DateTime day) =>
      setDone(itemId, day, done: true);

  /// 取消勾选，等价于 setDone(..., done: false)。
  Future<void> uncheck(String itemId, DateTime day) =>
      setDone(itemId, day, done: false);

  /// 切换勾选状态，返回切换后的状态。
  Future<bool> toggle(String itemId, DateTime day) async {
    final cur = await isDone(itemId, day);
    final next = !cur;
    await setDone(itemId, day, done: next);
    return next;
  }

  // ---------- 单点查询 ----------

  /// 某条目在某天是否已勾选。
  Future<bool> isDone(String itemId, DateTime day) async {
    final stamp = _startOfDay(_normalize(day));
    final rows = await db.query(
      T.checkins,
      where: 'item_id = ? AND date = ?',
      whereArgs: <Object?>[itemId, stamp.millisecondsSinceEpoch],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return Checkin.fromMap(rows.first).done;
  }

  /// 某天已勾选的条目 id 集合。
  Future<Set<String>> doneIdsOfDay(DateTime day) async {
    final stamp = _startOfDay(_normalize(day));
    final rows = await db.query(
      T.checkins,
      columns: <String>['item_id'],
      where: 'date = ? AND done = ?',
      whereArgs: <Object?>[stamp.millisecondsSinceEpoch, 1],
    );
    return rows.map((e) => e['item_id'] as String).toSet();
  }

  // ---------- 区间统计 ----------

  /// 某个区间的打卡汇总，按天从早到晚返回。
  /// 只返回有打卡记录的天，没记录的天不会补空行。
  Future<List<DaySummary>> summariesBetween(
      DateTime from, DateTime to) async {
    final a = _startOfDay(_normalize(from));
    final b = _startOfDay(_normalize(to));
    if (b.isBefore(a)) return const [];

    final rows = await db.query(
      T.checkins,
      where: 'date >= ? AND date <= ? AND done = ?',
      whereArgs: <Object?>[
        a.millisecondsSinceEpoch,
        b.millisecondsSinceEpoch,
        1,
      ],
    );
    if (rows.isEmpty) return const [];

    // 一次查出涉及的条目分钟数，避免逐条再查库。
    final ids = rows.map((e) => e['item_id'] as String).toSet().toList();
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final itemRows = await db.query(
      T.items,
      columns: <String>['id', 'minutes'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final minutesOf = <String, int>{
      for (final it in itemRows)
        it['id'] as String: (it['minutes'] as int?) ?? 0,
    };

    final bucketItems = <DateTime, int>{};
    final bucketMinutes = <DateTime, int>{};
    for (final r in rows) {
      final checkin = Checkin.fromMap(r);
      final key = _startOfDay(checkin.date);
      bucketItems[key] = (bucketItems[key] ?? 0) + 1;
      bucketMinutes[key] =
          (bucketMinutes[key] ?? 0) + (minutesOf[checkin.itemId] ?? 0);
    }

    final keys = bucketItems.keys.toList()..sort();
    return [
      for (final k in keys)
        DaySummary(
          day: k,
          doneItems: bucketItems[k] ?? 0,
          doneMinutes: bucketMinutes[k] ?? 0,
        ),
    ];
  }

  /// 最近 [days] 天（含今天）每天的打卡汇总，从早到晚，缺数据补 0。
  Future<List<DaySummary>> recentDays({int days = 14}) async {
    if (days <= 0) return const [];
    final today = _startOfDay(_normalize(_clock()));
    final from = today.subtract(Duration(days: days - 1));
    final rawList = await summariesBetween(from, today);
    final byDay = {for (final s in rawList) s.day: s};

    final out = <DaySummary>[];
    for (var i = 0; i < days; i++) {
      final d = from.add(Duration(days: i));
      out.add(byDay[d] ??
          DaySummary(day: d, doneItems: 0, doneMinutes: 0));
    }
    return out;
  }

  // ---------- 今日快取 ----------

  /// 今天已打卡条数。
  Future<int> todayCount() async {
    final ids = await doneIdsOfDay(_clock());
    return ids.length;
  }

  /// 今天已打卡分钟数（按 items.minutes 累加）。
  Future<int> todayMinutes() async {
    final ids = await doneIdsOfDay(_clock());
    if (ids.isEmpty) return 0;
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final rows = await db.query(
      T.items,
      columns: <String>['minutes'],
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
    var total = 0;
    for (final r in rows) {
      total += (r['minutes'] as int?) ?? 0;
    }
    return total;
  }

  /// 总打卡条目数（同一 item_id 多日打卡只算一次）。
  Future<int> totalDoneItems() async {
    final rows = await db.query(
      T.checkins,
      columns: <String>['item_id'],
      where: 'done = ?',
      whereArgs: <Object?>[1],
    );
    return rows.map((e) => e['item_id'] as String).toSet().length;
  }

  // ---------- 内部 ----------

  /// 把任意时间点归一化到「凌晨 4 点日界」所属的那一天。
  DateTime _normalize(DateTime t) =>
      t.hour < AppConstants.dayBoundaryHour
          ? t.subtract(const Duration(days: 1))
          : t;

  DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
}