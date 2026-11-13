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

/// 错因归因分桶（缺口③）：五类错因各自的题数。
///
/// reason 取值与 mcqs.fail_reason 一致：
///   1 看不懂题 / 2 知识点没记住 / 3 记混了 / 4 想陷了。
/// 0 = 未标记，不计入任何一桶。
class FailReasonBucket {
  const FailReasonBucket({
    required this.cannotParse,
    required this.forgot,
    required this.mixedUp,
    required this.wrongReasoning,
  });

  /// 看不懂题
  final int cannotParse;

  /// 知识点没记住
  final int forgot;

  /// 记混了
  final int mixedUp;

  /// 想陷了
  final int wrongReasoning;

  int get total => cannotParse + forgot + mixedUp + wrongReasoning;

  /// 最大桶的题数，用于画比例条。
  int get maxCount {
    final List<int> v = <int>[cannotParse, forgot, mixedUp, wrongReasoning];
    v.sort();
    return v.last;
  }

  /// 最多的那一类叫什么；全 0 时返回 null。
  String? get dominant {
    if (total == 0) return null;
    final int m = maxCount;
    if (cannotParse == m) return '看不懂题';
    if (forgot == m) return '知识点没记住';
    if (mixedUp == m) return '记混了';
    return '想陷了';
  }
}

/// 一次模考成绩（缺口④留档）。
class MockExamRecord {
  const MockExamRecord({
    required this.finishedAt,
    required this.total,
    required this.rightCount,
    required this.elapsedSeconds,
    required this.timedOut,
  });

  final DateTime finishedAt;
  final int total;
  final int rightCount;
  final int elapsedSeconds;
  final bool timedOut;

  double get ratio => total == 0 ? 0 : rightCount / total;
  int get percent => (ratio * 100).round();
}

/// 掌握度预测：按 SM-2 现有参数往后推，算出还要多久。
class MasteryForecast {
  const MasteryForecast({
    required this.pendingCount,
    required this.graduatedCount,
    required this.daysToFinish,
    required this.reviewsLeft,
  });

  /// 还没毕业的题数
  final int pendingCount;

  /// 已毕业的题数
  final int graduatedCount;

  /// 按每天 [dailyQuota] 题、且之后全对，估算还需多少天
  final int daysToFinish;

  /// 还需要多少次日复习
  final int reviewsLeft;

  int get totalCount => pendingCount + graduatedCount;

  double get progress =>
      totalCount == 0 ? 0 : graduatedCount / totalCount;
}

/// 时间黑洞：花时间多但掌握度没上来的知识点（item 级）。
class TimeSink {
  const TimeSink({
    required this.itemId,
    required this.minutes,
    required this.level,
    required this.label,
    required this.accuracy,
  });

  final String itemId;
  final int minutes;

  /// 代理掌握度：0 红（正确率 <60%）/ 1 黄（60~80%）
  final int level;

  /// 展示用的名字（打卡项标题，取不到时是「第 N 周」）
  final String label;

  /// 该 item 所属周的选择题正确率 0~1
  final double accuracy;
}

/// 今日复习配额（缺口⑦）。
///
/// 断更回来那天，队列会堆出几百道题，人看到直接关 App。
/// 配额把炸弹拆开：今天做 [doToday] 道，剩下顺延，不永久沉底。
class ReviewQuota {
  const ReviewQuota({
    required this.dueCount,
    required this.doToday,
    required this.deferred,
  });

  final int dueCount;
  final int doToday;
  final int deferred;
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

  /// 错因归因分布（缺口③）。只统计答错过的题，按 fail_reason 分桶。
  Future<FailReasonBucket> failReasonBuckets() async {
    final rows = await db.query(
      T.mcqs,
      columns: <String>['fail_reason'],
      where: 'fail_reason > ?',
      whereArgs: <Object?>[0],
    );
    var p1 = 0;
    var p2 = 0;
    var p3 = 0;
    var p4 = 0;
    for (final r in rows) {
      switch (r['fail_reason'] as int? ?? 0) {
        case 1:
          p1++;
          break;
        case 2:
          p2++;
          break;
        case 3:
          p3++;
          break;
        case 4:
          p4++;
          break;
        default:
          break;
      }
    }
    return FailReasonBucket(
      cannotParse: p1,
      forgot: p2,
      mixedUp: p3,
      wrongReasoning: p4,
    );
  }

  // ---------- 缺口③/④ 新增：趋势与预测 ----------

  /// 模考成绩趋势（缺口④留档），按时间正序给最近 [limit] 条。
  Future<List<MockExamRecord>> mockTrend({int limit = 20}) async {
    final rows = await db.query(
      kTableMockExams,
      orderBy: 'finished_at DESC',
      limit: limit,
    );
    final out = <MockExamRecord>[];
    for (final r in rows) {
      out.add(MockExamRecord(
        finishedAt: DateTime.fromMillisecondsSinceEpoch(
          (r['finished_at'] as int?) ?? 0,
        ),
        total: (r['total'] as int?) ?? 0,
        rightCount: (r['right_count'] as int?) ?? 0,
        elapsedSeconds: (r['elapsed_seconds'] as int?) ?? 0,
        timedOut: ((r['timed_out'] as int?) ?? 0) == 1,
      ));
    }
    return out.reversed.toList();
  }

  /// 错因历史分布（缺口③）：最近 [days] 天的 fail_events 分桶。
  ///
  /// 与 failReasonBuckets() 的区别：那个看「现在每题最新标的是什么」，
  /// 这个看「这段时间一共标了多少次」，能看出改善趋势。
  Future<FailReasonBucket> failReasonHistory({int days = 30}) async {
    final since = _clock()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      kTableFailEvents,
      columns: <String>['reason'],
      where: 'answered_at >= ?',
      whereArgs: <Object?>[since],
    );
    var p1 = 0;
    var p2 = 0;
    var p3 = 0;
    var p4 = 0;
    for (final r in rows) {
      switch (r['reason'] as int? ?? 0) {
        case 1:
          p1++;
          break;
        case 2:
          p2++;
          break;
        case 3:
          p3++;
          break;
        case 4:
          p4++;
          break;
        default:
          break;
      }
    }
    return FailReasonBucket(
      cannotParse: p1,
      forgot: p2,
      mixedUp: p3,
      wrongReasoning: p4,
    );
  }

  /// 掌握度预测（缺口⑥）：按 SM-2 现有参数往后推。
  ///
  /// 口径：假设之后每次复习都答对、且每天复习量不超过 [dailyQuota] 题。
  /// 这是**乐观下限**——真实会更久。页面上要标注「按全对推算」。
  Future<MasteryForecast> masteryForecast({int dailyQuota = 30}) async {
    final rows = await db.query(
      T.mcqs,
      columns: <String>['stage'],
    );
    if (rows.isEmpty) {
      return const MasteryForecast(
        pendingCount: 0,
        graduatedCount: 0,
        daysToFinish: 0,
        reviewsLeft: 0,
      );
    }
    final int grad = AppConstants.reviewGraduatedStage;
    var pending = 0;
    var graduated = 0;
    var reviewsLeft = 0;
    for (final r in rows) {
      final int stage = (r['stage'] as int?) ?? 0;
      if (stage >= grad) {
        graduated++;
      } else {
        pending++;
        // 从当前档走到毕业档还差几次复习
        reviewsLeft += (grad - stage).clamp(1, grad);
      }
    }
    final int days = dailyQuota <= 0
        ? 0
        : (reviewsLeft / dailyQuota).ceil();
    return MasteryForecast(
      pendingCount: pending,
      graduatedCount: graduated,
      daysToFinish: days,
      reviewsLeft: reviewsLeft,
    );
  }

  /// 今日复习配额（缺口⑦）：今日到期的题，加上从昨天及更早顺延下来的。
  ///
  /// 返回 (今天该做多少, 顺延到明天多少)。顺延的题下一轮优先。
  Future<ReviewQuota> todayQuota({int limit = 30}) async {
    final today = startOfDay(_effectiveToday());
    final endMs = today.add(const Duration(days: 1)).millisecondsSinceEpoch;
    final rows = await db.query(
      T.mcqs,
      columns: <String>['id'],
      where: 'due_date IS NOT NULL AND due_date < ?',
      whereArgs: <Object?>[endMs],
    );
    final int due = rows.length;
    final int doToday = due > limit ? limit : due;
    final int deferred = due > limit ? due - limit : 0;
    return ReviewQuota(dueCount: due, doToday: doToday, deferred: deferred);
  }

  /// 时间黑洞（第 8 项）：花时间最多、但该周选择题正确率还没上来的 item。
  ///
  /// 口径说明：items 表里只有周/日/时长，没有「掌握度」字段；
  /// concepts 表也没有 item_id，两表实际关联不上。
  /// 所以这里用「该 item 所属周的选择题正确率」作为掌握度代理：
  ///   - 该周没做过选择题 -> 视为未验证，排除（没有数据就不下结论）；
  ///   - 正确率 < 80% -> 算没掌握，进入榜单。
  Future<List<TimeSink>> timeSinks({int limit = 5}) async {
    final checkins = await db.query(
      T.checkins,
      where: 'done = ?',
      whereArgs: <Object?>[1],
    );
    if (checkins.isEmpty) return const <TimeSink>[];

    final items = await db.query(T.items);
    final minutesOf = <String, int>{
      for (final it in items) it['id'] as String: it['minutes'] as int? ?? 0,
    };
    final weekOf = <String, int>{
      for (final it in items) it['id'] as String: it['week'] as int? ?? 0,
    };
    final practiceOf = <String, String>{
      for (final it in items)
        it['id'] as String: (it['practice'] as String? ?? ''),
    };

    // 按周累计选择题正确率
    final mcqs = await db.query(T.mcqs);
    final rightByWeek = <int, int>{};
    final totalByWeek = <int, int>{};
    for (final m in mcqs) {
      final int? w = m['week'] as int?;
      if (w == null) continue;
      final int wrong = (m['wrong_count'] as int?) ?? 0;
      final int stage = (m['stage'] as int?) ?? 0;
      totalByWeek[w] = (totalByWeek[w] ?? 0) + 1;
      // stage 达到毕业档或至少推过一档，宽松算作对过
      if (wrong == 0 || stage > 0) {
        rightByWeek[w] = (rightByWeek[w] ?? 0) + 1;
      }
    }

    final accum = <String, int>{};
    for (final c in checkins) {
      final String iid = c['item_id'] as String;
      accum[iid] = (accum[iid] ?? 0) + (minutesOf[iid] ?? 0);
    }

    final out = <TimeSink>[];
    accum.forEach((String iid, int min) {
      if (min <= 0) return;
      final int w = weekOf[iid] ?? 0;
      final int tot = totalByWeek[w] ?? 0;
      if (tot == 0) return; // 这周没题，不下结论
      final int right = rightByWeek[w] ?? 0;
      final double rate = right / tot;
      if (rate >= 0.8) return; // 已经拿到 80%，不算黑洞
      out.add(TimeSink(
        itemId: iid,
        minutes: min,
        level: rate < 0.6 ? 0 : 1,
        label: (practiceOf[iid] ?? '').isNotEmpty
            ? practiceOf[iid]!
            : '第 $w 周',
        accuracy: rate,
      ));
    });
    out.sort((a, b) => b.minutes.compareTo(a.minutes));
    return out.take(limit).toList();
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
