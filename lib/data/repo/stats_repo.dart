import '../../core/constants.dart';
import '../../core/date_utils.dart';
import '../db/app_database.dart';
import '../db/tables.dart';

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

  final String id;
  final String title;
  final String color;
  final int doneItems;
  final int totalItems;
  final int doneMinutes;

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
    final today = startOfDay(_effectiveToday());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final rows = await db.query(
      T.checkins,
      where: 'done = ? AND date >= ? AND date <= ?',
      whereArgs: [
        1,
        monday.millisecondsSinceEpoch,
        sunday.millisecondsSinceEpoch,
      ],
    );
    if (rows.isEmpty) return 0;

    final ids = <String>{
      for (final r in rows) r['item_id'] as String,
    }.toList();
    final items = ids.isEmpty
        ? const <Map<String, Object?>>[]
        : await db.query(
            T.items,
            where: 'id IN (${List<String>.filled(ids.length, '?').join(', ')})',
            whereArgs: ids,
          );
    final minutesOf = <String, int>{
      for (final it in items) it['id'] as String: it['minutes'] as int? ?? 0,
    };

    var sum = 0;
    for (final r in rows) {
      sum += minutesOf[r['item_id'] as String] ?? 0;
    }
    return sum;
  }

  // ---------- 热力图 ----------
  /// 最近 [weeks] 周（默认 12）的每日打卡条数，末尾对齐到今天。
  ///
  /// 返回长度为 weeks * 7 的列表，第一天是 (weeks-1) 周前的周一。
  Future<List<HeatCell>> heatmap({int weeks = 12}) async {
    if (weeks <= 0) return const <HeatCell>[];

    final today = startOfDay(_effectiveToday());
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final first = thisMonday.subtract(Duration(days: (weeks - 1) * 7));
    final last = today;

    final rows = await db.query(
      T.checkins,
      where: 'done = ? AND date >= ? AND date <= ?',
      whereArgs: [
        1,
        first.millisecondsSinceEpoch,
        last.millisecondsSinceEpoch,
      ],
    );

    final counter = <DateTime, int>{};
    for (final r in rows) {
      final key = startOfDay(_msToDt(r['date'] as int?) ?? first);
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
    final modules = await db.query(T.modules, orderBy: 'id ASC');
    if (modules.isEmpty) return const <ModuleProgress>[];

    final items = await db.query(T.items);
    final doneRows = await db.query(
      T.checkins,
      where: 'done = ?',
      whereArgs: [1],
    );
    final doneIds = <String>{
      for (final r in doneRows) r['item_id'] as String,
    };

    final out = <ModuleProgress>[];
    var cursor = 1;
    for (final m in modules) {
      final span = (m['weeks'] as int? ?? 0) <= 0 ? 0 : (m['weeks'] as int);
      final from = cursor;
      final to = span == 0 ? cursor - 1 : cursor + span - 1;
      cursor = to + 1;

      var doneItems = 0;
      var doneMinutes = 0;
      var totalItems = 0;
      for (final it in items) {
        final week = it['week'] as int? ?? 0;
        if (week < from || week > to) continue;
        totalItems++;
        if (doneIds.contains(it['id'] as String)) {
          doneItems++;
          doneMinutes += it['minutes'] as int? ?? 0;
        }
      }

      out.add(ModuleProgress(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        color: m['color'] as String? ?? '',
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
    final rows = await db.query(T.concepts);
    var red = 0;
    var yellow = 0;
    var green = 0;
    for (final c in rows) {
      final raw = c['level'] as int? ?? 0;
      final lv = raw < 0 ? 0 : raw;
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

}

DateTime? _msToDt(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
