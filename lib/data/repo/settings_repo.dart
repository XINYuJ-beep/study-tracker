/// app_settings 表的读写封装。
///
/// 表结构是 key / value 两列纯文本，所有设置项都走这里，
/// 不额外建表，避免 schema 频繁迁移。
///
/// 约定：value 一律存字符串，布尔用 '1'/'0'，数字与时刻直接存文本。
library;

import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../db/app_database.dart';
import '../db/tables.dart';

/// 设置项读写。
class SettingsRepo {
  SettingsRepo(this._db);

  final AppDatabase _db;

  // ---------- 底层 ----------

  /// 读原始字符串；不存在返回 null。
  Future<String?> getRaw(String key) async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.query(
      T.appSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// 写原始字符串；存在则覆盖。
  Future<void> setRaw(String key, String value) async {
    final Database db = await _db.database;
    await db.insert(
      T.appSettings,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读布尔，缺省 [fallback]。
  Future<bool> getBool(String key, {bool fallback = false}) async {
    final String? v = await getRaw(key);
    if (v == null) return fallback;
    return v == '1';
  }

  /// 写布尔。
  Future<void> setBool(String key, bool value) async {
    await setRaw(key, value ? '1' : '0');
  }

  /// 读整数，缺省 [fallback]。
  Future<int> getInt(String key, {int fallback = 0}) async {
    final String? v = await getRaw(key);
    if (v == null) return fallback;
    return int.tryParse(v) ?? fallback;
  }

  /// 写整数。
  Future<void> setInt(String key, int value) async {
    await setRaw(key, value.toString());
  }

  // ---------- 每日目标 ----------

  /// 每日目标条目数（SPEC 默认 3，可改）。
  Future<int> dailyGoal() async {
    return getInt('daily_goal', fallback: AppConstants.dailyGoalDefault);
  }

  /// 写每日目标条目数。
  Future<void> setDailyGoal(int goal) async {
    await setInt('daily_goal', goal);
  }

  // ---------- 提醒 ----------

  /// 提醒开关（默认开）。
  Future<bool> reminderEnabled() async {
    return getBool(AppConstants.keyReminderEnabled, fallback: true);
  }

  /// 写提醒开关。
  Future<void> setReminderEnabled(bool enabled) async {
    await setBool(AppConstants.keyReminderEnabled, enabled);
  }

  /// 提醒时刻（默认 20:00）。返回 (hour, minute)。
  Future<(int, int)> reminderTime() async {
    final String? v = await getRaw(AppConstants.keyReminderTime);
    if (v == null) {
      return (AppConstants.reminderHourDefault, AppConstants.reminderMinuteDefault);
    }
    final List<String> parts = v.split(':');
    if (parts.length != 2) {
      return (AppConstants.reminderHourDefault, AppConstants.reminderMinuteDefault);
    }
    final int h = int.tryParse(parts[0]) ?? AppConstants.reminderHourDefault;
    final int m = int.tryParse(parts[1]) ?? AppConstants.reminderMinuteDefault;
    if (h < 0 || h > 23 || m < 0 || m > 59) {
      return (AppConstants.reminderHourDefault, AppConstants.reminderMinuteDefault);
    }
    return (h, m);
  }

  /// 写提醒时刻。
  Future<void> setReminderTime(int hour, int minute) async {
    final String hh = hour.toString().padLeft(2, '0');
    final String mm = minute.toString().padLeft(2, '0');
    await setRaw(AppConstants.keyReminderTime, hh + ':' + mm);
  }

  /// 最后一次推送成功的学习日（yyyy-MM-dd），用于每天最多一条。
  Future<String?> lastNotifiedDay() async {
    return getRaw(AppConstants.keyLastNotifiedDay);
  }

  /// 记录最后一次推送日。
  Future<void> setLastNotifiedDay(String day) async {
    await setRaw(AppConstants.keyLastNotifiedDay, day);
  }

  // ---------- 提醒文案用到的统计 ----------

  /// 全计划中尚未打卡的条目数。
  /// 口径：items 全表减去 checkins 里 done=1 的去重 item_id。
  Future<int> remainingItemCount() async {
    final Database db = await _db.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${T.items} '
      'WHERE id NOT IN ('
      'SELECT item_id FROM ${T.checkins} WHERE done = 1'
      ')',
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
