import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'tables.dart';

/// sqflite 数据库封装：10 张表，schemaVersion 1。
///
/// 与原 drift 版保持完全一致的外部契约：
/// - 类名仍是 AppDatabase，无参构造；
/// - 数据库文件名仍是 study_tracker.sqlite，路径仍在应用文档目录；
/// - 打开后执行 PRAGMA foreign_keys = ON；
/// - version = 1，onCreate 建全部表。
///
/// 差异：drift 的 db.select/into/update 语法全部去掉，
/// 改成 sqflite 的 db.query/insert/update/rawQuery。
class AppDatabase {
  AppDatabase();

  Database? _db;

  /// 数据库文件名（升级时必须保持一致，否则老数据会丢）
  static const String fileName = 'study_tracker.sqlite';

  /// schema 版本号
  static const int schemaVersion = 1;

  /// 打开（或复用）底层连接。所有 repo 都通过它拿 Database。
  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    final Database opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final String path = p.join(dir.path, fileName);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (Database db) async {
        // 外键约束必须每次连接都打开，sqlite 默认是关的
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) async {
        final Batch b = db.batch();
        for (final String sql in kCreateTableSql) {
          b.execute(sql);
        }
        await b.commit(noResult: true);
      },
      onUpgrade: (Database db, int from, int to) async {
        // 开发期：schemaVersion 仍是 1，理论上不会走到这里。
        // 正式版前表结构冻结后，在这里补真实迁移。
      },
    );
  }

  /// 关闭连接（main() 里统一管理生命周期时调用）。
  Future<void> close() async {
    final Database? existing = _db;
    _db = null;
    if (existing != null && existing.isOpen) {
      await existing.close();
    }
  }

  // ---------- 方便 repo 调用的薄封装 ----------

  Future<List<Map<String, Object?>>> raw(String sql, [List<Object?>? args]) async {
    final Database db = await database;
    return db.rawQuery(sql, args);
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final Database db = await database;
    return db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.abort,
  }) async {
    final Database db = await database;
    return db.insert(table, values, conflictAlgorithm: conflictAlgorithm);
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final Database db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final Database db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> execute(String sql, [List<Object?>? args]) async {
    final Database db = await database;
    await db.execute(sql, args);
  }

  /// 事务：seeder 清表 + 批量灌数据用。
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final Database db = await database;
    return db.transaction<T>(action);
  }
}