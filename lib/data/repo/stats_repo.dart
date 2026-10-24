import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../db/app_database.dart';

/// 单日热力图格子：一天打卡了几条。
class HeatCell {
  const HeatCell({required this.day, required this.count});

  final DateTime day;
  final int count;
}

/// 一个模块的进度：第几模块、总条目、已完成、已完成分钟。
class ModuleProgress {
  const ModuleProgress({
    required this.id,
    required this.title,
    required this.color,
    required this.doneItems,
    required this.totalItems,
    required this.doneMinutes,
  });

  /// 0.0 ~ 1.0，总条目为 0 时返回 0。
  double get ratio => totalItems == 0 ? 0.0 : doneItems / totalItems;
}

/// 掌握度三色分桶：红=不会、黄=模糊、绿=掌握。
class MasteryBuckets {
  const MasteryBuckets({
    required this.red,
    required this.yellow,
    required this.green,
  });

  final int red;
  final int yellow;
  final int green;

  int get total => red + yellow + green;
}

/// 统计页数据源（SPEC 4.4）。
///
/// 本类只读，不改任何表；所有方法都从 Checkins / Items / Concepts / Modules
/// 现算，保证「统计数字与打卡记录一致」。
class StatsRepo {
  StatsRepo(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _clock;

  // ---------- 今日 / 周 ----------
  /// 本周已打卡分钟数。周以周一为第一天。
  Future<int> weekMinutes() async {
    final today = _startOfDay(_effectiveToday());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final rows = await (db.select(db.checkins)
          ..where((t) =>
              t.done.equals(true) &
              t.date.isBiggerOrEqualValue(monday) &
              t.date.isSmallerOrEqualValue(sunday)))
        .get();
    if (rows.isEmpty) return 0;

    final ids = rows.map((r) => r.itemId).toSet().toList();
    final items = await (db.select(db.items)
          ..where((t) => t.id.isIn(ids)))
        .get();
    final minutesOf = {for (final it in items) it.id: it.minutes};

    var sum = 0;
    for (final r in rows) {
      sum += minutesOf[r.itemId] ?? 0;
    }
    return sum;
  }

  // ---------- 热力图 ----------
  /// 最近 [weeks] 周（默认 12）的每日打卡条数，末尾对齐到今天。
  ///
  /// 返回长度为 weeks * 7 的列表，第一天是 (weeks-1) 周前的周一。
  Future<List<HeatCell>> heatmap({int weeks = 12}) async {
    if (weeks <= 0) return const <HeatCell>[];

    final today = _startOfDay(_effectiveToday());
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final first = thisMonday.subtract(Duration(days: (weeks - 1) * 7));
    final last = today;

    final rows = await (db.select(db.checkins)
          ..where((t) =>
              t.done.equals(true) &
              t.date.isBiggerOrEqualValue(first) &
              t.date.isSmallerOrEqualValue(last)))
        .get();

    final counter = <DateTime, int>{};
    for (final r in rows) {
      final key = _startOfDay(r.date);
      counter[key] = (counter[key] ?? 0) + 1;
    }

    final out = <HeatCell>[];
    for (var i = 0; i < weeks * 7; i++) {
      final d = first.add(Duration(days: i));
      out.add(HeatCell(day: d, count: counter[d] ?? 0));
    }
    return out;
  }

  // ---------- 模块进度 ----------
  /// 8 个模块的进度条数据，按模块 id 升序。
  ///
  /// Modules.weeks 存的是「该模块包含几个周」，所以按 id 顺序累加即可
  /// 还原出每模块的周区间（01:1-12、02:13-24……08:85-92）。
  Future<List<ModuleProgress>> moduleProgress() async {
    final modules = await (db.select(db.modules)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (modules.isEmpty) return const <ModuleProgress>[];

    final items = await db.select(db.items).get();
    final doneRows = await (db.select(db.checkins)
          ..where((t) => t.done.equals(true)))
        .get();
    final doneIds = doneRows.map((r) => r.itemId).toSet();

    final out = <ModuleProgress>[];
    var cursor = 1;
    for (final m in modules) {
      final span = m.weeks <= 0 ? 0 : m.weeks;
      final from = cursor;
      final to = span == 0 ? cursor - 1 : cursor + span - 1;
      cursor = to + 1;

      var doneItems = 0;
      var doneMinutes = 0;
      var totalItems = 0;
      for (final it in items) {
        if (it.week < from || it.week > to) continue;
        totalItems++;
        if (doneIds.contains(it.id)) {
          doneItems++;
          doneMinutes += it.minutes;
        }
      }

      out.add(ModuleProgress(
        id: m.id,
        title: m.title,
        color: m.color,
        doneItems: doneItems,
        totalItems: totalItems,
        doneMinutes: doneMinutes,
      ));
    }
    return out;
  }

  // ---------- 掌握度 ----------
  /// 掌握度三色分桶（与 concept_repo.gradeWhiteboard 的 level 口径一致）：
  /// level 0 = 红（不会）、1 = 黄（模糊）、>= 2 = 绿（掌握或已推进）。
  Future<MasteryBuckets> masteryBuckets() async {
    final rows = await db.select(db.concepts).get();
    var red = 0;
    var yellow = 0;
    var green = 0;
    for (final c in rows) {
      final lv = c.level < 0 ? 0 : c.level;
      if (lv == 0) {
        red++;
      } else if (lv == 1) {
        yellow++;
      } else {
        green++;
      }
    }
    return MasteryBuckets(red: red, yellow: yellow, green: green);
  }

  // ---------- 内部 ----------
  /// 04:00 日界：凌晨 4 点前算前一天。
  DateTime _effectiveToday() {
    final now = _clock();
    final shifted = now.hour < AppConstants.dayBoundaryHour
        ? now.subtract(const Duration(days: 1))
        : now;
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
}
