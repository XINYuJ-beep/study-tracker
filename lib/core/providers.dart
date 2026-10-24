import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repo/checkin_repo.dart';
import '../data/repo/concept_repo.dart';
import '../data/repo/plan_repo.dart';
import '../data/repo/question_repo.dart';
import '../data/repo/stats_repo.dart';
import '../data/seed/seeder.dart';

/// 全局唯一的数据库实例。
///
/// 由 main() 里 ProviderScope(overrides: [...]) 注入，
/// 这样数据库的创建与关闭都在 main 里统一管理，页面层只管读。
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>((ref) {
  throw StateError(
    'databaseProvider 必须由 main() 通过 overrideWithValue 注入，'
    '不要在 provider 内部直接 new AppDatabase()，否则会出现多个连接。',
  );
});

/// 首启导入器。页面里的「清空重导」也用它。
final Provider<Seeder> seederProvider = Provider<Seeder>((ref) {
  return Seeder(ref.watch(databaseProvider));
});

/// 打卡仓库：checkins 表读写、连续天数、今日完成情况。
final Provider<CheckinRepo> checkinRepoProvider = Provider<CheckinRepo>((ref) {
  return CheckinRepo(ref.watch(databaseProvider));
});

/// 计划仓库：modules / weeks / items 的读取与本周进度。
final Provider<PlanRepo> planRepoProvider = Provider<PlanRepo>((ref) {
  return PlanRepo(ref.watch(databaseProvider));
});

/// 问答仓库：复习卡（SRS）与选择题。
final Provider<QuestionRepo> questionRepoProvider = Provider<QuestionRepo>((ref) {
  return QuestionRepo(ref.watch(databaseProvider));
});

/// 概念仓库：概念 / 术语卡，含掌握度等级。
final Provider<ConceptRepo> conceptRepoProvider = Provider<ConceptRepo>((ref) {
  return ConceptRepo(ref.watch(databaseProvider));
});

/// 统计仓库：本周时长、12 周热力图、8 模块进度、掌握度分桶。
final Provider<StatsRepo> statsRepoProvider = Provider<StatsRepo>((ref) {
  return StatsRepo(ref.watch(databaseProvider));
});
