/// 全局业务常量。
/// 数值来源：SPEC 第 4 节页面逻辑 + 第 6 节折叠屏断点。
class AppConstants {
  AppConstants._();

  // ---------- 折叠屏断点（SPEC 第 6 节）----------
  /// 小于 600dp：单栏（手机外屏 / 普通手机）
  static const double breakpointNarrow = 600.0;
  /// 600 ~ 840dp：单栏加宽（内屏展开但不算宽）
  static const double breakpointDual = 840.0;
  /// 双栏时左栏固定宽度 280dp
  static const double leftPaneWidth = 280.0;
  /// 铰链避让距离 20dp（不放大按钮和输入框）
  static const double hingeGap = 20.0;

  // ---------- 今日页（SPEC 4.1）----------
  /// 默认每日目标条数
  static const int dailyGoalDefault = 3;
  /// 推荐队列最多展示条数
  static const int recommendLimit = 6;
  /// 每日时间预算（分钟）
  static const int dailyBudgetMinutes = 90;
  /// 推荐队列累计分钟上限 = 预算 × 系数
  static const double budgetFactor = 1.2;

  // ---------- 打卡（SPEC 4.6）----------
  /// 撤销窗口（秒）
  static const int undoWindowSeconds = 5;

  // ---------- 跨天边界 ----------
  /// 以凌晨 04:00 作为一天的起点，避免熬夜党被判成第二天
  static const int dayBoundaryHour = 4;

  // ---------- 周 ----------
  static const int daysPerWeek = 7;
  /// 周目标分钟数 = 每日时间预算 × 每周天数（SPEC 4.1 的 90 分钟/天）
  static const int weekGoalMinutes = dailyBudgetMinutes * daysPerWeek;

  // ---------- 学习计划总量（自检页基准值）----------
  /// 模块数
  static const int expectedModules = 8;
  /// 周数
  static const int expectedWeeks = 92;
  /// 条目数
  static const int expectedItems = 644;
  /// 记忆卡片数
  static const int expectedCards = 736;
  /// 选择题数
  static const int expectedMcqs = 4293;
  /// 概念词条数
  static const int expectedConcepts = 368;
  /// 阶段（直播/课程）数
  static const int expectedStages = 8;
  /// 主播清单数
  static const int expectedStreams = 6;

  // ---------- 数据版本（首启导入判断）----------
  /// 当前内置数据的版本号，JSON 有改动就 +1，首启比对后决定是否重导
  static const int dataVersion = 11;
  /// app_settings 表里存数据版本号的 key
  static const String keyDataVersion = 'data_version';

  // ---------- 测试解锁阈值 ----------
  /// 周完成度达到该比例，解锁该周选择题
  static const double weekUnlockRatio = 0.6;
  /// 模块完成度达到该比例，解锁阶段听力
  static const double moduleUnlockRatio = 0.8;

  // ---------- 错题与记忆 ----------
  /// 答对多少次移出错题本
  static const int rightStreakToClear = 2;
  /// 连续答错多少次进强化
  static const int wrongCountToFocus = 2;

  // ---------- 间隔重复（艾宾浩斯档位，单位：天）----------
  /// 各档位的间隔天数。索引即档位（0-6），共 7 档。
  ///
  /// 口径（唯一，question_repo 与 concept_repo 必须一致）：
  ///   stage = 0 -> 1 天
  ///   stage = 1 -> 2 天
  ///   stage = 2 -> 4 天
  ///   stage = 3 -> 7 天
  ///   stage = 4 -> 15 天
  ///   stage = 5 -> 30 天
  ///   stage = 6 -> 60 天
  ///   达到 reviewGraduatedStage(7) 即毕业，due_date 置空不再出现。
  /// 列表长度 = reviewGraduatedStage，故按 stage 直接下标不会越界。
  static const List<int> reviewIntervals = <int>[1, 2, 4, 7, 15, 30, 60];
  /// 毕业档位（达到即不再安排复习）。同时等于 reviewIntervals 的长度。
  static const int reviewGraduatedStage = 7;
  /// 初始难度因子
  static const double initialEase = 2.5;
  /// 答错一次扣减的难度因子
  static const double easePenalty = 0.2;
  /// 难度因子下限（低于此值不再扣，防止题目难度爆炸）
  static const double easeMin = 1.3;

  // ---------- 白板抽背 ----------
  /// 每轮抽几个概念
  static const int whiteboardCount = 10;
  /// 每个概念限时（秒）
  static const int whiteboardSeconds = 60;

  /// 概念题 4 选 1：抽题数量与通过线（10 题 8 过）。
  static const int quizPickCount = 10;
  static const int quizPassCount = 8;

  /// 旧题抽查：抽题数量与通过线（10 题 7 过）。
  static const int spotCheckCount = 10;
  static const int spotCheckPassCount = 7;

  /// 白板抽背：绿卡通过线（绿 >= 7 过）。
  static const int whiteboardPassCount = 7;

  // ---------- 每日提醒（SPEC 第 14 章）----------
  /// 默认提醒时刻：20:00
  static const int reminderHourDefault = 20;
  static const int reminderMinuteDefault = 0;
  /// 通知里估算「预计 X 分钟」时，单条目按多少分钟折算。
  /// 取计划里条目分钟数的中位数口径，宁高不宁低，避免用户觉得被低估。
  static const int avgMinutesPerItem = 55;
  /// app_settings 里存提醒开关的 key
  static const String keyReminderEnabled = 'reminder_enabled';
  /// app_settings 里存提醒时刻的 key（格式 HH:mm）
  static const String keyReminderTime = 'reminder_time';
  /// app_settings 里存「最后一次推送成功的学习日」的 key（去重用）
  static const String keyLastNotifiedDay = 'last_notified_day';
}

/// 应用展示名
const String kAppName = '学习打卡';

/// 资产路径
class AssetPaths {
  AssetPaths._();
  static const String plan = 'assets/data/plan.json';
  static const String questions = 'assets/data/questions.json';
  static const String concepts = 'assets/data/concepts.json';
  static const String stages = 'assets/data/stages.json';
}
