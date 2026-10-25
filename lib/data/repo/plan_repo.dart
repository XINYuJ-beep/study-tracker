import '../../core/constants.dart';
import '../db/app_database.dart';
import '../db/tables.dart';

/// 今天（以凌晨 4 点为日界）。
DateTime effectiveToday() {
  final now = DateTime.now();
  return now.hour < AppConstants.dayBoundaryHour
      ? now.subtract(const Duration(days: 1))
      : now;
}

DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

class WeekProgress {
  const WeekProgress({
    required this.week,
    required this.doneItems,
    required this.totalItems,
    required this.doneMinutes,
  });

  final int week;
  final int doneItems;
  final int totalItems;
  final int doneMinutes;

  double get itemRatio => totalItems == 0 ? 0 : doneItems / totalItems;

  double get weekRatio => doneMinutes / AppConstants.weekGoalMinutes;

  int get remainingMinutes {
    final left = AppConstants.weekGoalMinutes - doneMinutes;
    return left < 0 ? 0 : left;
  }
}

class PlanRepo {
  PlanRepo(this.db);

  final AppDatabase db;

  Future<List<Module>> allModules() async {
    final rows = await db.query(T.modules, orderBy: 'id ASC');
    return rows.map(Module.fromMap).toList();
  }

  Future<Module?> moduleById(String id) async {
    final rows = await db.query(
      T.modules,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Module.fromMap(rows.first);
  }

  Future<List<Week>> allWeeks() async {
    final rows = await db.query(T.weeks, orderBy: 'week ASC');
    return rows.map(Week.fromMap).toList();
  }

  Future<Week?> weekByNumber(int week) async {
    final rows = await db.query(
      T.weeks,
      where: 'week = ?',
      whereArgs: [week],
      limit: 1,
    );
    return rows.isEmpty ? null : Week.fromMap(rows.first);
  }

  Future<List<Item>> itemsOfWeek(int week) async {
    final rows = await db.query(
      T.items,
      where: 'week = ?',
      whereArgs: [week],
      orderBy: 'day ASC',
    );
    return rows.map(Item.fromMap).toList();
  }

  Future<List<Item>> allItems() async {
    final rows = await db.query(T.items, orderBy: 'week ASC, day ASC');
    return rows.map(Item.fromMap).toList();
  }

  Future<Set<String>> doneItemIdsOfDay(DateTime day) async {
    final d = _startOfDay(day);
    final rows = await db.query(
      T.checkins,
      columns: ['item_id'],
      where: 'date = ? AND done = ?',
      whereArgs: [d.millisecondsSinceEpoch, 1],
    );
    return rows.map((r) => r['item_id'] as String).toSet();
  }

  Future<Set<String>> allDoneItemIds() async {
    final rows = await db.query(
      T.checkins,
      columns: ['item_id'],
      where: 'done = ?',
      whereArgs: [1],
    );
    return rows.map((r) => r['item_id'] as String).toSet();
  }

  Future<int> progressiveCursorWeek() async {
    final done = await allDoneItemIds();
    if (done.isEmpty) return 1;
    final items = await allItems();
    int cursor = 1;
    for (var w = 1; w <= AppConstants.expectedWeeks; w++) {
      final ofWeek = items.where((i) => i.week == w).toList();
      if (ofWeek.isEmpty) break;
      final allDone = ofWeek.every((i) => done.contains(i.id));
      if (!allDone) break;
      cursor = w + 1;
    }
    return cursor > AppConstants.expectedWeeks
        ? AppConstants.expectedWeeks
        : cursor;
  }

  Future<List<Item>> todayRecommendation(
      {int limit = AppConstants.recommendLimit}) async {
    final today = effectiveToday();
    final doneToday = await doneItemIdsOfDay(today);
    final doneAll = await allDoneItemIds();
    final cursor = await progressiveCursorWeek();
    final items = await allItems();

    final pool = <Item>[];
    for (final it in items) {
      if (doneAll.contains(it.id)) continue;
      if (doneToday.contains(it.id)) continue;
      if (it.week < cursor) continue;
      pool.add(it);
    }
    pool.sort((a, b) {
      final c = a.week.compareTo(b.week);
      return c != 0 ? c : a.day.compareTo(b.day);
    });

    final budget =
        (AppConstants.dailyBudgetMinutes * AppConstants.budgetFactor).round();
    final out = <Item>[];
    var used = 0;
    for (final it in pool) {
      if (out.length >= limit) break;
      if (out.isNotEmpty && used + it.minutes > budget) break;
      out.add(it);
      used += it.minutes;
    }
    return out;
  }

  Future<WeekProgress> weekProgress(int week) async {
    final items = await itemsOfWeek(week);
    final done = await allDoneItemIds();
    var cnt = 0;
    var minutes = 0;
    for (final it in items) {
      if (done.contains(it.id)) {
        cnt++;
        minutes += it.minutes;
      }
    }
    return WeekProgress(
      week: week,
      doneItems: cnt,
      totalItems: items.length,
      doneMinutes: minutes,
    );
  }

  Future<int> totalDoneItems() async {
    final done = await allDoneItemIds();
    return done.length;
  }

  Future<int> totalDoneMinutes() async {
    final done = await allDoneItemIds();
    final items = await allItems();
    var m = 0;
    for (final it in items) {
      if (done.contains(it.id)) m += it.minutes;
    }
    return m;
  }

  Future<List<bool>> lastNDaysStreak(int days) async {
    final today = effectiveToday();
    final result = <bool>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = _startOfDay(today.subtract(Duration(days: i)));
      final rows = await db.query(
        T.checkins,
        columns: ['item_id'],
        where: 'date = ? AND done = ?',
        whereArgs: [d.millisecondsSinceEpoch, 1],
        limit: 1,
      );
      result.add(rows.isNotEmpty);
    }
    return result;
  }

  Future<int> currentStreak() async {
    final done = await allDoneItemIds();
    if (done.isEmpty) return 0;
    final all = await db.query(
      T.checkins,
      columns: ['date'],
      where: 'done = ?',
      whereArgs: [1],
    );
    final dates = all
        .map((r) => _startOfDay(
            DateTime.fromMillisecondsSinceEpoch(r['date'] as int)))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) return 0;

    final today = _startOfDay(effectiveToday());
    final newest = dates.first;
    if (newest.difference(today).inDays.abs() > 1) return 0;

    var streak = 1;
    var prev = newest;
    for (var i = 1; i < dates.length; i++) {
      final gap = prev.difference(dates[i]).inDays;
      if (gap == 1) {
        streak++;
        prev = dates[i];
      } else if (gap == 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }
}
