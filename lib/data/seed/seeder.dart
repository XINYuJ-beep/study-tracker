import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, DatabaseExecutor;

import '../../core/constants.dart';
import '../db/app_database.dart';
import '../db/tables.dart';

/// 首启导入结果。同时充当自检页的数据源。
class SeedResult {
  const SeedResult({
    this.modules = 0,
    this.weeks = 0,
    this.items = 0,
    this.cards = 0,
    this.mcqs = 0,
    this.concepts = 0,
    this.stages = 0,
    this.streams = 0,
    this.skipped = const <String>[],
    this.fatalError,
  });

  /// 硬错误：整批回滚，什么都不写。
  const SeedResult.failed(String message)
      : modules = 0,
        weeks = 0,
        items = 0,
        cards = 0,
        mcqs = 0,
        concepts = 0,
        stages = 0,
        streams = 0,
        skipped = const <String>[],
        fatalError = message;

  final int modules;
  final int weeks;
  final int items;
  final int cards;
  final int mcqs;
  final int concepts;
  final int stages;
  final int streams;

  /// 软错误：跳过的记录及原因（如选择题选项不是 4 个）。
  final List<String> skipped;

  /// 非空表示硬错误，导入已回滚。
  final String? fatalError;

  bool get ok => fatalError == null && failures().isEmpty;

  /// 逐项对比基准值，返回不符项说明。空列表表示全部达标。
  List<String> failures() {
    final out = <String>[];
    void check(String name, int actual, int expected) {
      if (actual != expected) {
        out.add('$name 期望 $expected 实际 $actual');
      }
    }

    check('模块', modules, AppConstants.expectedModules);
    check('周', weeks, AppConstants.expectedWeeks);
    check('条目', items, AppConstants.expectedItems);
    check('记忆卡', cards, AppConstants.expectedCards);
    check('选择题', mcqs, AppConstants.expectedMcqs);
    check('概念', concepts, AppConstants.expectedConcepts);
    check('阶段', stages, AppConstants.expectedStages);
    check('主播', streams, AppConstants.expectedStreams);
    return out;
  }

  @override
  String toString() =>
      'SeedResult(modules: $modules, weeks: $weeks, items: $items, '
      'cards: $cards, mcqs: $mcqs, concepts: $concepts, stages: $stages, '
      'streams: $streams, skipped: ${skipped.length}, '
      'fatalError: $fatalError)';
}

/// 首启数据导入器。
///
/// 流程：读 4 个 asset JSON -> 解析 -> 硬校验 -> 事务内清表+批量插入 -> 写版本号。
/// 硬错误整批回滚；软错误跳过单条并记录进 [SeedResult.skipped]。

class Seeder {
  /// 把 JSON 里的 day 字段统一成 1..7（周一=1）。
  ///
  /// plan.json 给的是中文（'周一'..'周日'），
  /// 但 items.day 列是 INTEGER，直接 as int 会抛类型转换异常。
  /// 兼容数字、数字字符串与中文三种写法，认不出的一律当周一。
  int _dayIndex(Object? raw) {
    if (raw is int) return raw >= 1 && raw <= 7 ? raw : 1;
    final String s = raw?.toString().trim() ?? '';
    const Map<String, int> table = <String, int>{
      '1': 1, '一': 1, '周一': 1, '星期一': 1,
      '2': 2, '二': 2, '周二': 2, '星期二': 2,
      '3': 3, '三': 3, '周三': 3, '星期三': 3,
      '4': 4, '四': 4, '周四': 4, '星期四': 4,
      '5': 5, '五': 5, '周五': 5, '星期五': 5,
      '6': 6, '六': 6, '周六': 6, '星期六': 6,
      '7': 7, '日': 7, '天': 7, '周日': 7, '周天': 7, '星期日': 7, '星期天': 7,
    };
    return table[s] ?? 1;
  }
  Seeder(this.db);

  final AppDatabase db;

  /// 版本一致就跳过，版本变了或首次安装才真正导入。
  Future<SeedResult> seedIfNeeded() async {
    try {
      final rows = await db.query(
        T.appSettings,
        where: 'key = ?',
        whereArgs: <Object?>[AppConstants.keyDataVersion],
        limit: 1,
      );
      final installed =
          int.tryParse((rows.isEmpty ? null : rows.first['value'] as String?) ?? '') ?? 0;
      if (installed >= AppConstants.dataVersion) {
        // 已是最新版本，不重复导入。
        return const SeedResult();
      }
      return await run();
    } catch (e) {
      return SeedResult.failed('$e');
    }
  }

  /// 无条件执行一次完整导入（自检页「清空重导」会直接调它）。
  Future<SeedResult> run() async {
    try {
      final planRaw = await rootBundle.loadString(AssetPaths.plan);
      final questionsRaw = await rootBundle.loadString(AssetPaths.questions);
      final conceptsRaw = await rootBundle.loadString(AssetPaths.concepts);
      final stagesRaw = await rootBundle.loadString(AssetPaths.stages);

      final plan = jsonDecode(planRaw) as Map<String, dynamic>;
      final questions = jsonDecode(questionsRaw) as Map<String, dynamic>;
      final concepts = jsonDecode(conceptsRaw) as List<dynamic>;
      final stages = jsonDecode(stagesRaw) as Map<String, dynamic>;

      final modulesJson = (plan['modules'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      // ---------- 硬校验 ----------
      final moduleIds = <String>{};
      for (final m in modulesJson) {
        final id = m['id'] as String;
        if (!moduleIds.add(id)) {
          return SeedResult.failed('模块 id 重复：$id');
        }
      }

      final weekRows = <Map<String, Object?>>[];
      final itemRows = <Map<String, Object?>>[];
      final weekSeen = <int>{};
      final itemIds = <String>{};

      for (final m in modulesJson) {
        final moduleId = m['id'] as String;
        final weeks = (m['weeks'] as List<dynamic>).cast<Map<String, dynamic>>();
        for (final w in weeks) {
          final weekNo = w['week'] as int;
          if (!weekSeen.add(weekNo)) {
            return SeedResult.failed('周号重复：$weekNo');
          }
          weekRows.add(<String, Object?>{
            'week': weekNo,
            'title': w['title'] as String?,
            'goal': w['goal'] as String?,
            'review': w['review'] as String?,
          });

          final items = (w['items'] as List<dynamic>).cast<Map<String, dynamic>>();
          for (final it in items) {
            final itemId = it['id'] as String;
            if (!itemIds.add(itemId)) {
              return SeedResult.failed('条目 id 重复：$itemId');
            }
            itemRows.add(<String, Object?>{
              'id': itemId,
              'week': weekNo,
              'day': _dayIndex(it['day']),
              'watch': it['watch'] as String?,
              'practice': it['practice'] as String?,
              'output': it['output'] as String?,
              'minutes': it['minutes'] as int?,
            });
          }
        }
      }

      if (weekRows.length != AppConstants.expectedWeeks) {
        return SeedResult.failed(
            '周数不符：期望 ${AppConstants.expectedWeeks} 实际 ${weekRows.length}');
      }
      for (var i = 1; i <= AppConstants.expectedWeeks; i++) {
        if (!weekSeen.contains(i)) {
          return SeedResult.failed('缺少第 $i 周');
        }
      }

      // ---------- 解析（软错误跳过） ----------
      final skipped = <String>[];

      final moduleRows = modulesJson.map((m) {
        return <String, Object?>{
          'id': m['id'] as String,
          'title': m['title'] as String,
          'sub': m['sub'] as String?,
          'color': m['color'] as String?,
          'goal': m['goal'] as String?,
          'accept': m['accept'] as String?,
          'weeks': ((m['weeks'] as List<dynamic>?) ?? const []).length,
        };
      }).toList();

      final cardRows = <Map<String, Object?>>[];
      final recall = ((questions['recall'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();
      for (final r in recall) {
        cardRows.add(<String, Object?>{
          'id': r['id'] as String,
          'week': r['week'] as int,
          'module': r['module'] as String,
          'front': r['front'] as String,
          'back': r['back'] as String,
          'type': r['type'] as String?,
        });
      }

      final mcqRows = <Map<String, Object?>>[];
      final mcq = ((questions['mcq'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();
      for (final q in mcq) {
        final id = q['id'] as String;
        final options = (q['options'] as List<dynamic>?)?.cast<String>() ??
            const <String>[];
        final answer = q['answer'] as int?;
        if (options.length != 4) {
          skipped.add('选择题 $id 选项数 ${options.length} != 4');
          continue;
        }
        if (answer == null || answer < 0 || answer > 3) {
          skipped.add('选择题 $id 答案越界：$answer');
          continue;
        }
        mcqRows.add(<String, Object?>{
          'id': id,
          'week': q['week'] as int,
          'module': q['module'] as String,
          'question': q['question'] as String,
          'options': jsonEncode(options),
          'answer': answer,
        });
      }

      final conceptRows = <Map<String, Object?>>[];
      for (final c in concepts.cast<Map<String, dynamic>>()) {
        final term = (c['term'] as String?)?.trim() ?? '';
        final definition = (c['definition'] as String?)?.trim() ?? '';
        if (term.isEmpty || definition.isEmpty) {
          skipped.add('概念 term/definition 为空：（$term）');
          continue;
        }
        conceptRows.add(<String, Object?>{
          'term': term,
          'definition': definition,
          'week': c['week'] as int?,
        });
      }

      final stageRows = <Map<String, Object?>>[];
      final stageList = ((stages['stages'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();
      for (final s in stageList) {
        final moduleId = s['module'] as String;
        if (!moduleIds.contains(moduleId)) {
          skipped.add('阶段 ${s['title']} 的模块 $moduleId 不存在');
          continue;
        }
        stageRows.add(<String, Object?>{
          'module': moduleId,
          'week': s['week'] as int,
          'title': s['title'] as String,
          'where_at': s['where'] as String?, // JSON 的 where 对列 where_at
          'task': s['task'] as String?,
          'pass': s['pass'] as String?,
        });
      }

      final streamRows = <Map<String, Object?>>[];
      final streamList = ((stages['streams'] as List<dynamic>?) ?? const [])
          .cast<String>();
      for (final name in streamList) {
        streamRows.add(<String, Object?>{'name': name});
      }

      final result = SeedResult(
        modules: moduleRows.length,
        weeks: weekRows.length,
        items: itemRows.length,
        cards: cardRows.length,
        mcqs: mcqRows.length,
        concepts: conceptRows.length,
        stages: stageRows.length,
        streams: streamRows.length,
        skipped: skipped,
      );

      // ---------- 事务内清表 + 批量插入 ----------
      await db.transaction((txn) async {
        // 删表顺序严格照抄原实现（子表先删，父表后删），不得调整。
        await txn.delete(T.checkins);
        await txn.delete(T.cards);
        await txn.delete(T.mcqs);
        await txn.delete(T.concepts);
        await txn.delete(T.stages);
        await txn.delete(T.streams);
        await txn.delete(T.items);
        await txn.delete(T.weeks);
        await txn.delete(T.modules);

        await _insertAll(txn, T.modules, moduleRows);
        await _insertAll(txn, T.weeks, weekRows);
        await _insertAll(txn, T.items, itemRows);
        await _insertAll(txn, T.cards, cardRows);
        await _insertAll(txn, T.mcqs, mcqRows);
        await _insertAll(txn, T.concepts, conceptRows);
        await _insertAll(txn, T.stages, stageRows);
        await _insertAll(txn, T.streams, streamRows);

        await txn.insert(
          T.appSettings,
          <String, Object?>{
            'key': AppConstants.keyDataVersion,
            'value': AppConstants.dataVersion.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      return result;
    } catch (e) {
      return SeedResult.failed('$e');
    }
  }

  /// 逐条插入。事务内批量写，比逐条自动提交快得多；
  /// 用 INSERT OR REPLACE 保证重复导入时覆盖而非冲突。
  Future<void> _insertAll(
    DatabaseExecutor txn,
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    for (final row in rows) {
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
