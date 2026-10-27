import 'constants.dart';

/// 4 点日界：把任意时刻归到「学习日」的零点。
///
/// 例：今天是 2026-10-27 03:30，hour=3 < dayBoundaryHour(4)，属于「昨天」，
/// 返回 2026-10-26 00:00。学习日不做跨天切分，凌晨刷题仍算前一天。
DateTime startOfDay(DateTime t) {
  final base = t.hour < AppConstants.dayBoundaryHour
      ? t.subtract(const Duration(days: 1))
      : t;
  return DateTime(base.year, base.month, base.day);
}

/// 自然日零点（无 4 点日界）。仅用于纯日历展示，不参与学习统计。
DateTime startOfNaturalDay(DateTime t) => DateTime(t.year, t.month, t.day);
