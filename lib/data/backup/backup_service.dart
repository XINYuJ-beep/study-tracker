import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../db/tables.dart';

/// 数据备份与导出的统一出口。
///
/// 三件事都在这里：
/// 1. [exportCheckinsCsv]   把 checkins 表连同 items 的可读字段导出成 CSV。
/// 2. [exportJson]          把 10 张表整体导出成一个 JSON 快照（可读、可回滚）。
/// 3. [pruneAutoBackups]    自动备份只保留最近 N 份，多的删掉。
///
/// 目录约定：所有产物都落在目标目录下的 `study_tracker_backup/`，
/// 与设置页原有的 sqlite 导出同目录，用户在一个地方就能找到全部备份。
class BackupService {
  BackupService(this._db);

  final Database _db;

  /// 子目录名，与 settings_page 的 sqlite 导出一致。
  static const String subDir = 'study_tracker_backup';

  /// 自动备份文件名前缀。
  static const String autoPrefix = 'auto_';

  /// 回滚备份文件名前缀。
  static const String rollbackPrefix = 'rollback_';

  /// 自动备份保留份数。
  static const int keepAutoCount = 4;

  /// 取得（并确保存在）备份目录。
  ///
  /// 优先外部存储，拿不到就退回应用文档目录（与设置页 _export 同口径）。
  static Future<Directory> resolveDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, subDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 时间戳：yyyyMMdd_HHmmss。
  static String stamp([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  /// 日期戳：yyyyMMdd。
  static String dayStamp([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  /// CSV 字段转义。
  ///
  /// 规则三条：
  /// 1. 含逗号 / 双引号 / 换行 / 回车，整体加双引号。
  /// 2. 字段内双引号翻倍。
  /// 3. 其余原样。
  static String csvField(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    final needsQuote =
        s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    if (!needsQuote) return s;
    return '"' + s.replaceAll('"', '""') + '"';
  }

  /// 导出打卡记录 CSV。
  ///
  /// 列：item_id,date,date_text,done,minutes,note,watch,practice,output
  /// - date 为原始毫秒时间戳（忠于库内数据）
  /// - date_text 为 yyyy-MM-dd，方便直接看
  /// - watch/practice/output 来自 items 联查，方便对上是哪一条
  ///
  /// 返回写好的文件。
  Future<File> exportCheckinsCsv({DateTime? now}) async {
    final dir = await resolveDir();
    final rows = await _db.rawQuery('''
      SELECT
        c.item_id   AS item_id,
        c.date      AS date,
        c.done      AS done,
        c.minutes   AS minutes,
        c.note      AS note,
        i.watch     AS watch,
        i.practice  AS practice,
        i.output    AS output
      FROM ${T.checkins} c
      LEFT JOIN ${T.items} i ON i.id = c.item_id
      ORDER BY c.date ASC, c.item_id ASC
    ''');

    final sb = StringBuffer();
    sb.write('item_id,date,date_text,done,minutes,note,watch,practice,output\r\n');
    for (final r in rows) {
      final ms = (r['date'] as num?)?.toInt() ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final dateText = '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
      sb
        ..write(csvField(r['item_id']))
        ..write(',')
        ..write(ms)
        ..write(',')
        ..write(dateText)
        ..write(',')
        ..write((r['done'] as num?)?.toInt() ?? 0)
        ..write(',')
        ..write((r['minutes'] as num?)?.toInt() ?? 0)
        ..write(',')
        ..write(csvField(r['note']))
        ..write(',')
        ..write(csvField(r['watch']))
        ..write(',')
        ..write(csvField(r['practice']))
        ..write(',')
        ..write(csvField(r['output']))
        ..write('\r\n');
    }

    final file = File(p.join(dir.path, 'checkins_${stamp(now)}.csv'));
    await file.writeAsString(sb.toString(), flush: true);
    return file;
  }

  /// 导出 10 张表的 JSON 快照。
  ///
  /// [prefix] 决定文件名前缀：auto_ / rollback_ / 空。
  /// 返回写好的文件。
  Future<File> exportJson({String prefix = '', DateTime? now}) async {
    final dir = await resolveDir();
    final tables = <String, dynamic>{};
    for (final t in kDropTableOrder) {
      tables[t] = await _db.query(t);
    }
    final payload = <String, dynamic>{
      'app': 'study_tracker',
      'schemaVersion': await _schemaVersion(),
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'exportedAtMs': (now ?? DateTime.now()).millisecondsSinceEpoch,
      'tables': tables,
    };
    final name = '$prefix${stamp(now)}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  /// 自动备份：文件名按周一到周日算“一周”，一周内只备一次。
  ///
  /// 判断依据是文件列表里有没有「本周范围内」的 auto_ 文件，
  /// 而不是靠额外存一个时间戳 —— 少一处状态就少一处不一致。
  /// 返回 null 表示本周已经备过，跳过。
  Future<File?> autoBackupIfNeeded({DateTime? now}) async {
    final dir = await resolveDir();
    final current = now ?? DateTime.now();
    final weekStart = _startOfWeek(current);

    final existing = await dir
        .list()
        .where((e) => e is File && p.basename(e.path).startsWith(autoPrefix))
        .cast<File>()
        .toList();

    for (final f in existing) {
      final st = await f.stat();
      if (!st.modified.isBefore(weekStart)) {
        return null; // 本周已有备份
      }
    }

    final file = await exportJson(
      prefix: autoPrefix,
      now: current,
    );
    await pruneAutoBackups();
    return file;
  }

  /// 自动备份只保留最近 [keepAutoCount] 份。
  ///
  /// 只认 auto_ 前缀，rollback_ 与手动备份一律不动。
  /// 按文件名降序（stamp 是定长，天然字典序等于时间序）。
  Future<int> pruneAutoBackups() async {
    final dir = await resolveDir();
    final files = await dir
        .list()
        .where((e) => e is File && p.basename(e.path).startsWith(autoPrefix))
        .cast<File>()
        .toList();
    if (files.length <= keepAutoCount) return 0;

    files.sort((a, b) =>
        p.basename(b.path).compareTo(p.basename(a.path)));
    var deleted = 0;
    for (var i = keepAutoCount; i < files.length; i++) {
      try {
        await files[i].delete();
        deleted++;
      } catch (_) {
        // 单个删不掉不影响其它
      }
    }
    return deleted;
  }

  /// 当前库的 schemaVersion。
  Future<int> _schemaVersion() async {
    final r = await _db.rawQuery('PRAGMA user_version');
    if (r.isEmpty) return 0;
    return (r.first.values.first as num?)?.toInt() ?? 0;
  }

  /// 本周一 00:00:00。
  static DateTime _startOfWeek(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}
