import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../db/app_database.dart';

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

  Future<List<Modules>> allModules() {
    return (db.select(db.modules)..orderBy([
          (t) => OrderingTerm(expression: t.id),
        ]))
        .get();
  }

  Future<Modules?> moduleById(String id) {
    return (db.select(db.modules)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<Weeks>> allWeeks() {
    return (db.select(db.weeks)..orderBy([
          (t) => OrderingTerm(expression: t.week),
        ]))
        .get();
  }

  Future<Weeks?> weekByNumber(int week) {
    return (db.select(db.weeks)..where((t) => t.week.equals(week)))
        .getSingleOrNull();
  }

  Future<List<Items>> itemsOfWeek(int week) {
    return (db.select(db.items)
          ..where((t) => t.week.equals(week))
          ..orderBy([(t) => OrderingTerm(expression: t.day)]))
        .get();
  }

  Future<List<Items>> allItems() {
    return (db.select(db.items)
          ..orderBy([
            (t) => OrderingTerm(expression: t.week),
            (t) => OrderingTerm(expression: t.day),
          ]))
        .get();
  }

  Future<Set<String>> doneItemIdsOfDay(DateTime day) async {
    final d = _startOfDay(day);
    final rows = await (db.select(db.checkins)
          ..where((t) => t.date.equals(d) & t.done.equals(true)))
        .get();
    return rows.map((r) => r.itemId).toSet();
  }

  Future<Set<String>> allDoneItemIds() async {
    final rows = await (db.select(db.checkins)
          ..where((t) => t.done.equals(true)))
        .get();
    return rows.map((r) => r.itemId).toSet();
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

  Future<List<Items>> todayRecommendation({int limit = AppConstants.recommendLimit}) async {
    final today = effectiveToday();
    final doneToday = await doneItemIdsOfDay(today);
    final doneAll = await allDoneItemIds();
    final cursor = await progressiveCursorWeek();
    final items = await allItems();

    final pool = <Items>[];
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

    final budget = (AppConstants.dailyBudgetMinutes * AppConstants.budgetFactor).round();
    final out = <Items>[];
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
      final rows = await (db.select(db.checkins)
            ..where((t) => t.date.equals(d) & t.done.equals(true)))
          .get();
      result.add(rows.isNotEmpty);
    }
    return result;
  }

  Future<int> currentStreak() async {
    final done = await allDoneItemIds();
    if (done.isEmpty) return 0;
    final all = await (db.select(db.checkins)..where((t) => t.done.equals(true))).get();
    final dates = all.map((r) => _startOfDay(r.date)).toSet().toList()
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
