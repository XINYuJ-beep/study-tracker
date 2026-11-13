/// 十张本地表的建表 SQL 与表名常量（sqflite 版，已移除 drift）。
///
/// 说明：
/// - 表结构完全等价于原 drift 定义；schemaVersion 现为 4（v3 到 v4 的迁移见 kMigrateV3ToV4）。
/// - review_queue 不是表，也不是视图；它是 cards 与 concepts
///   在 Dart 层合并后的逻辑队列（见 question_repo.dueReview）。
/// ====================================
/// 表名常量
class T {
  T._();

  static const String modules = 'modules';
  static const String weeks = 'weeks';
  static const String items = 'items';
  static const String checkins = 'checkins';
  static const String cards = 'cards';
  static const String mcqs = 'mcqs';
  static const String concepts = 'concepts';
  static const String stages = 'stages';
  static const String streams = 'streams';
  static const String appSettings = 'app_settings';
}

/// ====================================
/// 建表顺序：按外键依赖从上游到下游
const List<String> kCreateTableOrder = <String>[
  T.modules,
  T.weeks,
  T.items,
  T.checkins,
  T.cards,
  T.mcqs,
  T.concepts,
  T.stages,
  T.streams,
  T.appSettings,
];

/// ====================================
/// 表 1: modules
/// id: A1..A8 / title / sub / color / goal / accept / weeks
const String sqlCreateModules = '''
CREATE TABLE IF NOT EXISTS modules (
  id      TEXT NOT NULL PRIMARY KEY,
  title   TEXT NOT NULL,
  sub     TEXT NOT NULL,
  color   TEXT NOT NULL,
  goal    TEXT NOT NULL,
  accept  TEXT NOT NULL,
  weeks   INTEGER NOT NULL
)''';

/// ====================================
/// 表 2: weeks (第 1..92 周)
/// review 可为 null；completedAt 为 null 表示未完成
const String sqlCreateWeeks = '''
CREATE TABLE IF NOT EXISTS weeks (
  week          INTEGER NOT NULL PRIMARY KEY,
  title         TEXT NOT NULL,
  goal          TEXT NOT NULL,
  review        TEXT,
  completed_at  INTEGER
)''';

/// ====================================
/// 表 3: items (644 条 = 92 周 x 7 天)
/// 注意：这里没有 done 字段，完成与否完全由 checkins 推导
const String sqlCreateItems = '''
CREATE TABLE IF NOT EXISTS items (
  id        TEXT NOT NULL PRIMARY KEY,
  week      INTEGER NOT NULL,
  day       INTEGER NOT NULL,
  watch     TEXT NOT NULL,
  practice  TEXT NOT NULL,
  output    TEXT NOT NULL,
  minutes   INTEGER NOT NULL DEFAULT 0
)''';

/// ====================================
/// 表 4: checkins（打卡记录）
/// 复合主键 (item_id, date)
/// done 默认 1，未撤销的行即代表已打卡
/// completed_at 供 5 秒撤销窗口使用
/// date 存当天 00:00（本地时区）；04:00 日界规则在 repo 层处理，不在这里
///
/// minutes：本条实际用时（分钟）。打卡面板可改，默认取 items.minutes。
///          统计「今日用时 / 本周时长」以它为准，而不是 items 的预估。
/// note：   选填备注，最多 200 字，空串表示没写。
const String sqlCreateCheckins = '''
CREATE TABLE IF NOT EXISTS checkins (
  item_id       TEXT NOT NULL,
  date          INTEGER NOT NULL,
  done          INTEGER NOT NULL DEFAULT 1,
  completed_at  INTEGER,
  minutes       INTEGER NOT NULL DEFAULT 0,
  note          TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (item_id, date),
  FOREIGN KEY (item_id) REFERENCES items (id)
)''';

/// schemaVersion 1 -> 2 的迁移语句。
///
/// 老库（v1）的 checkins 没有 minutes / note，必须 ALTER 补上，
/// 否则升级后所有读这两列的 SQL 都会报 no such column。
/// ALTER TABLE 加 NOT NULL 列必须带默认值。
const List<String> kMigrateV1ToV2 = <String>[
  "ALTER TABLE checkins ADD COLUMN minutes INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE checkins ADD COLUMN note TEXT NOT NULL DEFAULT ''",
];
/// schemaVersion 2 -> 3 的迁移语句。
///
/// 新增 source_ref：记录每张卡 / 每道选择题的原始出处，格式「类型:定位符」，
/// 例如 builtin:questions、outline:docs/大纲/模块01.md。
/// 老库数据没有出处信息，统一回填 builtin:questions。
const List<String> kMigrateV2ToV3 = <String>[
  "ALTER TABLE cards ADD COLUMN source_ref TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE mcqs ADD COLUMN source_ref TEXT NOT NULL DEFAULT ''",
  "UPDATE cards SET source_ref = 'builtin:questions' WHERE source_ref = ''",
  "UPDATE mcqs SET source_ref = 'builtin:questions' WHERE source_ref = ''",
];

/// schemaVersion 3 -> 4 的迁移语句。
///
/// 为 mcqs 接入「按天投放 + SM-2 复习」，追加 6 列：
/// - item_id：所属条目（如 M01W01D1），按天投放靠它精确定位到某天的 6 道题
/// - day：周一..周日 = 1..7，冗余存一份，避免每次 JOIN items 取 day
/// - question_type：single/multi/judge/reverse，标题型（单选/多选/判断/反向）
/// - stage：SM-2 档位 0..7，7 = 毕业不再复习（与 cards 完全一致）
/// - due_date：下次到期时间（毫秒），null = 还没排期
/// - ease：SM-2 难度因子，默认 2.5，答错 -0.2，下限 1.3
///
/// 老数据（v3 阶段基数 276 道；现题库 321 道）回填规则：
/// - question_type = 'single'（旧题全是四选一）
/// - stage = 0、ease = 2.5（从零开始排程，首次答题即进入 SM-2）
/// - item_id 空串（旧题只有 week 维度，无条目级归属；按天投放不会取到它们，
///   它们仍然可以通过 mcqsByWeek 按周练习，行为不变）
/// - day = 0（表示「无天归属」）
const List<String> kMigrateV3ToV4 = <String>[
  "ALTER TABLE mcqs ADD COLUMN item_id TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE mcqs ADD COLUMN day INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE mcqs ADD COLUMN question_type TEXT NOT NULL DEFAULT 'single'",
  "ALTER TABLE mcqs ADD COLUMN stage INTEGER NOT NULL DEFAULT 0",
  "ALTER TABLE mcqs ADD COLUMN due_date INTEGER",
  "ALTER TABLE mcqs ADD COLUMN ease REAL NOT NULL DEFAULT 2.5",
  "UPDATE mcqs SET question_type = 'single' WHERE question_type = ''",
];

/// v4 -> v5: add self_score for speak-back self rating.
/// 0 = not rated (old rows), 1 = cannot explain, 2 = faltered, 3 = explained clearly.
const List<String> kMigrateV4ToV5 = <String>[
  "ALTER TABLE mcqs ADD COLUMN self_score INTEGER NOT NULL DEFAULT 0",
];

/// v5 -> v6: add fail_reason for wrong-answer attribution (gap 3).
/// 0 = not marked, 1 = cannot parse the question, 2 = forgot the point,
/// 3 = mixed two points up, 4 = reasoned down the wrong path.
const List<String> kMigrateV5ToV6 = <String>[
  "ALTER TABLE mcqs ADD COLUMN fail_reason INTEGER NOT NULL DEFAULT 0",
];

/// v6 -> v7：缺口②自评拆为四档，并新增错因事件表与模考成绩表。
///
/// self_score 取值口径升级（旧值兼容）：
///   0 未评 / 1 讲不出来 / 2 讲了但关键点绕过 / 3 讲了但要停一下 / 4 讲清了
///   旧库里的 3（讲清了）保持不变；旧 2（卡壳）语义与新的 2 一致，不迁移。
const List<String> kMigrateV6ToV7 = <String>[
  "CREATE TABLE IF NOT EXISTS fail_events ("
      "id INTEGER PRIMARY KEY AUTOINCREMENT, "
      "mcq_id TEXT NOT NULL, "
      "reason INTEGER NOT NULL, "
      "week INTEGER, "
      "module TEXT, "
      "answered_at INTEGER NOT NULL)",
  "ALTER TABLE mcqs ADD COLUMN self_verified INTEGER NOT NULL DEFAULT -1",
  "CREATE INDEX IF NOT EXISTS idx_fail_events_at ON fail_events(answered_at)",
  "CREATE TABLE IF NOT EXISTS mock_exams ("
      "id INTEGER PRIMARY KEY AUTOINCREMENT, "
      "finished_at INTEGER NOT NULL, "
      "total INTEGER NOT NULL, "
      "right_count INTEGER NOT NULL, "
      "elapsed_seconds INTEGER NOT NULL, "
      "timed_out INTEGER NOT NULL DEFAULT 0)",
];

/// fail_events 表名（不在 T 常量类里，单独给一个）。
const String kTableFailEvents = 'fail_events';

/// mock_exams 表名。
const String kTableMockExams = 'mock_exams';

/// v7 -> v8：mcqs 补 day（第几天），把题库挂到「周-天」上。
///
/// 意义：打卡不再是自己点勾，而是「做完当天考核才算打卡」。
/// 4293 道题按「每周题数 ÷ 该周天数」顺序均分到每天，
/// 已核实每周只属一个模块、且题目顺序与课程顺序一致。
/// day 为 NULL = 未分配（历史遗留数据），这些题不进日考核，只进 SM-2 复习。
///
/// 注意：day 列在 kMigrateV3ToV4 里已经加过一次。SQLite 不支持
/// ADD COLUMN IF NOT EXISTS，这里不能再写一次，否则 v3 老库升到 v8
/// 会直接撞 duplicate column name: day。此处只补索引。
const List<String> kMigrateV7ToV8 = <String>[
  "CREATE INDEX IF NOT EXISTS idx_mcqs_week_day ON mcqs(week, day)",
];

/// 性能索引（SPEC 第 16 节：checkins(item_id)、checkins(date) 建索引）
const List<String> kCreateIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_checkins_item ON checkins (item_id)',
  'CREATE INDEX IF NOT EXISTS idx_checkins_date ON checkins (date)',
  'CREATE INDEX IF NOT EXISTS idx_cards_due ON cards (due_date)',
  'CREATE INDEX IF NOT EXISTS idx_items_week ON items (week)',
  // 按天投放：WHERE item_id = ?（每天 6 道题）
  'CREATE INDEX IF NOT EXISTS idx_mcqs_item ON mcqs (item_id)',
  // SM-2 每日取到期题：WHERE stage < 7 AND due_date <= ?
  'CREATE INDEX IF NOT EXISTS idx_mcqs_due ON mcqs (due_date)',
  // 按周-天投放：WHERE week = ? AND day = ?（日考核取当天题）
  'CREATE INDEX IF NOT EXISTS idx_mcqs_week_day ON mcqs(week, day)',
  // 错因历史：WHERE answered_at >= ?
  'CREATE INDEX IF NOT EXISTS idx_fail_events_at ON fail_events(answered_at)',
];

/// ====================================
/// 表 5: cards (736 张记忆卡)
/// stage 0..6 = D1 D2 D4 D7 D15 D30 毕业
/// ease 默认 2.5（SM-2 风格）
const String sqlCreateCards = '''
CREATE TABLE IF NOT EXISTS cards (
  id         TEXT NOT NULL PRIMARY KEY,
  week       INTEGER,
  module     TEXT,
  front      TEXT NOT NULL,
  back       TEXT NOT NULL,
  type       TEXT NOT NULL,
  stage      INTEGER NOT NULL DEFAULT 0,
  due_date   INTEGER,
  ease       REAL NOT NULL DEFAULT 2.5,
  source_ref TEXT NOT NULL DEFAULT ''
)''';

/// ====================================
/// 表 6: mcqs (目标 4140 道选择题 = 644 item × 6 + 92 周综合卷 × 3)
///
/// wrong_count / right_streak: 连对 2 次移出错题本
/// options 存 JSON 字符串数组，answer 是 0..3 的下标
///
/// v4 新增（按天投放 + SM-2）：
/// item_id       所属条目，按天投放靠它精确取某天的 6 道；周综合卷为空串
/// day           1..7 = 周一..周日；0 = 无天归属（老数据/综合卷）
/// question_type single / multi / judge / reverse
/// stage         SM-2 档位 0..7，7 = 毕业（与 cards 同构）
/// due_date      下次到期毫秒；null = 未排期
/// ease          SM-2 难度因子，默认 2.5，下限 1.3
const String sqlCreateMcqs = '''
CREATE TABLE IF NOT EXISTS mcqs (
  id            TEXT NOT NULL PRIMARY KEY,
  week          INTEGER,
  module        TEXT,
  question      TEXT NOT NULL,
  options       TEXT NOT NULL,
  answer        INTEGER NOT NULL,
  explain       TEXT,
  wrong_count   INTEGER NOT NULL DEFAULT 0,
  right_streak  INTEGER NOT NULL DEFAULT 0,
  source_ref    TEXT NOT NULL DEFAULT '',
  item_id       TEXT NOT NULL DEFAULT '',
  day           INTEGER NOT NULL DEFAULT 0,
  question_type TEXT NOT NULL DEFAULT 'single',
  stage         INTEGER NOT NULL DEFAULT 0,
  due_date      INTEGER,
  ease          REAL NOT NULL DEFAULT 2.5,
  self_score    INTEGER NOT NULL DEFAULT 0,
  fail_reason   INTEGER NOT NULL DEFAULT 0,
  self_verified INTEGER NOT NULL DEFAULT -1
)''';

/// ====================================
/// 表 7: concepts (129 个概念词条，白板抽背)
/// level 0 基础 / 1 中等 / 2 进阶 -> 影响难度
/// id 自增，因为 concepts.json 里没有 id 字段
const String sqlCreateConcepts = '''
CREATE TABLE IF NOT EXISTS concepts (
  id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  term        TEXT NOT NULL,
  definition  TEXT NOT NULL,
  week        INTEGER,
  level       INTEGER NOT NULL DEFAULT 0,
  due_date    INTEGER,
  ease        REAL NOT NULL DEFAULT 2.5,
  reps        INTEGER NOT NULL DEFAULT 0
)''';

/// ====================================
/// 表 8: stages (8 个里程碑阶段)
/// JSON 里的 key 是 'where'，为避开 SQL 关键字改名为 where_at
const String sqlCreateStages = '''
CREATE TABLE IF NOT EXISTS stages (
  id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  module   TEXT NOT NULL,
  week     INTEGER NOT NULL,
  title    TEXT NOT NULL,
  where_at TEXT NOT NULL,
  task     TEXT NOT NULL,
  pass     TEXT NOT NULL
)''';

/// ====================================
/// 表 9: streams (6 个主播清单)
const String sqlCreateStreams = '''
CREATE TABLE IF NOT EXISTS streams (
  id    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name  TEXT NOT NULL
)''';

/// ====================================
/// 表 10: app_settings（键值对存储）
const String sqlCreateAppSettings = '''
CREATE TABLE IF NOT EXISTS app_settings (
  key    TEXT NOT NULL PRIMARY KEY,
  value  TEXT NOT NULL
)''';

/// ====================================
/// 表 11: fail_events（错因事件流水，缺口③）
///
/// 与 mcqs.fail_reason 的区别：mcqs 里存的是「这一题最新一次标了什么」，
/// 本表存的是「每一次标错因都留一条」，能看出改善趋势。
///
/// 注意：本表最早写在 kMigrateV6ToV7 里只给老库补建，导致全新安装
/// （onCreate 只跑 kCreateTableSql）根本没有这张表，统计页查它会报
/// no such table。这里补成建表常量的唯一来源，迁移链引用同一个常量。
const String sqlCreateFailEvents = '''
CREATE TABLE IF NOT EXISTS fail_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mcq_id TEXT NOT NULL,
  reason INTEGER NOT NULL,
  week INTEGER,
  module TEXT,
  answered_at INTEGER NOT NULL
)''';

/// fail_events 按时间查的索引（错因历史默认查最近 30 天）。
const String sqlCreateFailEventsIndex =
    'CREATE INDEX IF NOT EXISTS idx_fail_events_at '
    'ON fail_events(answered_at)';

/// ====================================
/// 表 12: mock_exams（模考成绩留档，缺口④）
///
/// 同上：原先只在迁移链里建表，全新安装会缺表。
const String sqlCreateMockExams = '''
CREATE TABLE IF NOT EXISTS mock_exams (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  finished_at INTEGER NOT NULL,
  total INTEGER NOT NULL,
  right_count INTEGER NOT NULL,
  elapsed_seconds INTEGER NOT NULL,
  timed_out INTEGER NOT NULL DEFAULT 0
)''';

/// ====================================
/// 全部建表语句，按 kCreateTableOrder 一一对应
const List<String> kCreateTableSql = <String>[
  sqlCreateModules,
  sqlCreateWeeks,
  sqlCreateItems,
  sqlCreateCheckins,
  sqlCreateCards,
  sqlCreateMcqs,
  sqlCreateConcepts,
  sqlCreateStages,
  sqlCreateStreams,
  sqlCreateAppSettings,
  // v7/v8 引入的两张表，原先只在迁移链里建，全新安装会缺表
  sqlCreateFailEvents,
  sqlCreateMockExams,
];

/// ====================================
/// 删表顺序：按外键依赖从下游到上游（先删引用别人的）
const List<String> kDropTableOrder = <String>[
  T.checkins,
  T.cards,
  T.mcqs,
  T.concepts,
  T.stages,
  T.streams,
  T.items,
  T.weeks,
  T.modules,
  T.appSettings,
];

/// ====================================
/// 行数据类
///
/// 这些类原先由 drift 的代码生成器写到 app_database.g.dart。
/// 换成 sqflite 后没有生成器了，必须手写。
/// 类名与字段名保持与原生成代码一致，5 个 repo 里的引用零改动。
///
/// 列名映射：Dart 驼峰 -> SQL 蛇形（如 completedAt -> completed_at）
/// 时间映射：DateTime <-> INTEGER（毫秒时间戳）
/// ====================================

int? _dtToMs(DateTime? v) => v?.millisecondsSinceEpoch;

DateTime? _msToDt(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

/// --------------------------------------------------
/// modules
class Module {
  const Module({
    required this.id,
    required this.title,
    required this.sub,
    required this.color,
    required this.goal,
    required this.accept,
    required this.weeks,
  });

  final String id;
  final String title;
  final String sub;
  final String color;
  final String goal;
  final String accept;
  final int weeks;

  factory Module.fromMap(Map<String, Object?> m) => Module(
        id: m['id'] as String,
        title: m['title'] as String,
        sub: m['sub'] as String,
        color: m['color'] as String,
        goal: m['goal'] as String,
        accept: m['accept'] as String,
        weeks: m['weeks'] as int,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'sub': sub,
        'color': color,
        'goal': goal,
        'accept': accept,
        'weeks': weeks,
      };
}

/// --------------------------------------------------
/// weeks
class Week {
  const Week({
    required this.week,
    required this.title,
    required this.goal,
    this.review,
    this.completedAt,
  });

  final int week;
  final String title;
  final String goal;
  final String? review;
  final DateTime? completedAt;

  factory Week.fromMap(Map<String, Object?> m) => Week(
        week: m['week'] as int,
        title: m['title'] as String,
        goal: m['goal'] as String,
        review: m['review'] as String?,
        completedAt: _msToDt(m['completed_at']),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'week': week,
        'title': title,
        'goal': goal,
        'review': review,
        'completed_at': _dtToMs(completedAt),
      };
}

/// --------------------------------------------------
/// items
class Item {
  const Item({
    required this.id,
    required this.week,
    required this.day,
    required this.watch,
    required this.practice,
    required this.output,
    required this.minutes,
  });

  final String id;
  final int week;
  final int day;
  final String watch;
  final String practice;
  final String output;
  final int minutes;

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        week: m['week'] as int,
        day: m['day'] as int,
        watch: m['watch'] as String,
        practice: m['practice'] as String,
        output: m['output'] as String,
        minutes: m['minutes'] as int,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'week': week,
        'day': day,
        'watch': watch,
        'practice': practice,
        'output': output,
        'minutes': minutes,
      };
}

/// --------------------------------------------------
/// checkins（复合主键 item_id + date）
class Checkin {
  const Checkin({
    required this.itemId,
    required this.date,
    required this.done,
    this.completedAt,
  });

  final String itemId;
  final DateTime date;
  final bool done;
  final DateTime? completedAt;

  factory Checkin.fromMap(Map<String, Object?> m) => Checkin(
        itemId: m['item_id'] as String,
        date: _msToDt(m['date'])!,
        done: (m['done'] as int) != 0,
        completedAt: _msToDt(m['completed_at']),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'item_id': itemId,
        'date': date.millisecondsSinceEpoch,
        'done': done ? 1 : 0,
        'completed_at': _dtToMs(completedAt),
      };
}

/// --------------------------------------------------
/// cards
class Card {
  const Card({
    required this.id,
    this.week,
    this.module,
    required this.front,
    required this.back,
    required this.type,
    required this.stage,
    this.dueDate,
    required this.ease,
  });

  final String id;
  final int? week;
  final String? module;
  final String front;
  final String back;
  final String type;
  final int stage;
  final DateTime? dueDate;
  final double ease;

  factory Card.fromMap(Map<String, Object?> m) => Card(
        id: m['id'] as String,
        week: m['week'] as int?,
        module: m['module'] as String?,
        front: m['front'] as String,
        back: m['back'] as String,
        type: m['type'] as String,
        stage: m['stage'] as int,
        dueDate: _msToDt(m['due_date']),
        ease: (m['ease'] as num).toDouble(),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'week': week,
        'module': module,
        'front': front,
        'back': back,
        'type': type,
        'stage': stage,
        'due_date': _dtToMs(dueDate),
        'ease': ease,
      };
}

/// --------------------------------------------------
/// mcqs（options 在库里是 JSON 字符串，这里也保持字符串，
/// 由 question_repo 负责 jsonDecode/jsonEncode，与原逻辑一致）
class Mcq {
  const Mcq({
    required this.id,
    this.week,
    this.module,
    required this.question,
    required this.options,
    required this.answer,
    this.explain,
    required this.wrongCount,
    required this.rightStreak,
    this.sourceRef = '',
    this.itemId = '',
    this.day = 0,
    this.questionType = 'single',
    this.stage = 0,
    this.dueDate,
    this.ease = 2.5,
  });

  final String id;
  final int? week;
  final String? module;
  final String question;
  final String options;
  final int answer;
  final String? explain;

  /// 错题本：错过的次数
  final int wrongCount;
  /// 错题本：连续答对次数，达到 rightStreakToClear 后移出错题本
  final int rightStreak;

  /// 题目出处，形如 `builtin:questions` / `llm:W1D1` / `manual`
  final String sourceRef;

  /// 所属条目（如 M01W01D1），按天投放靠它精确定位；周综合卷为空串
  final String itemId;
  /// 1..7 = 周一..周日；0 = 无天归属（老数据 / 周综合卷）
  final int day;
  /// single / multi / judge / reverse
  final String questionType;

  /// SM-2 档位 0..7，7 = 毕业不再复习
  final int stage;
  /// 下次到期毫秒，null = 未排期
  final DateTime? dueDate;
  /// SM-2 难度因子，默认 2.5，答错 -0.2，下限 1.3
  final double ease;

  bool get isGraduated => stage >= 7;

  factory Mcq.fromMap(Map<String, Object?> m) => Mcq(
        id: m['id'] as String,
        week: m['week'] as int?,
        module: m['module'] as String?,
        question: m['question'] as String,
        options: m['options'] as String,
        answer: m['answer'] as int,
        explain: m['explain'] as String?,
        wrongCount: (m['wrong_count'] as int?) ?? 0,
        rightStreak: (m['right_streak'] as int?) ?? 0,
        sourceRef: (m['source_ref'] as String?) ?? '',
        itemId: (m['item_id'] as String?) ?? '',
        day: (m['day'] as int?) ?? 0,
        questionType: (m['question_type'] as String?) ?? 'single',
        stage: (m['stage'] as int?) ?? 0,
        dueDate: _msToDt(m['due_date'] as int?),
        ease: (m['ease'] as num?)?.toDouble() ?? 2.5,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'week': week,
        'module': module,
        'question': question,
        'options': options,
        'answer': answer,
        'explain': explain,
        'wrong_count': wrongCount,
        'right_streak': rightStreak,
        'source_ref': sourceRef,
        'item_id': itemId,
        'day': day,
        'question_type': questionType,
        'stage': stage,
        'due_date': _dtToMs(dueDate),
        'ease': ease,
      };

  Mcq copyWith({
    int? wrongCount,
    int? rightStreak,
    int? stage,
    DateTime? dueDate,
    double? ease,
    bool clearDueDate = false,
  }) =>
      Mcq(
        id: id,
        week: week,
        module: module,
        question: question,
        options: options,
        answer: answer,
        explain: explain,
        wrongCount: wrongCount ?? this.wrongCount,
        rightStreak: rightStreak ?? this.rightStreak,
        sourceRef: sourceRef,
        itemId: itemId,
        day: day,
        questionType: questionType,
        stage: stage ?? this.stage,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        ease: ease ?? this.ease,
      );
}

/// --------------------------------------------------
/// concepts
class Concept {
  const Concept({
    required this.id,
    required this.term,
    required this.definition,
    this.week,
    required this.level,
    this.dueDate,
    required this.ease,
    required this.reps,
  });

  final int id;
  final String term;
  final String definition;
  final int? week;
  final int level;
  final DateTime? dueDate;
  final double ease;
  final int reps;

  factory Concept.fromMap(Map<String, Object?> m) => Concept(
        id: m['id'] as int,
        term: m['term'] as String,
        definition: m['definition'] as String,
        week: m['week'] as int?,
        level: m['level'] as int,
        dueDate: _msToDt(m['due_date']),
        ease: (m['ease'] as num).toDouble(),
        reps: m['reps'] as int,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'term': term,
        'definition': definition,
        'week': week,
        'level': level,
        'due_date': _dtToMs(dueDate),
        'ease': ease,
        'reps': reps,
      };

  /// 插入时用（id 自增，不含 id）
  Map<String, Object?> toInsertMap() => <String, Object?>{
        'term': term,
        'definition': definition,
        'week': week,
        'level': level,
        'due_date': _dtToMs(dueDate),
        'ease': ease,
        'reps': reps,
      };
}

/// --------------------------------------------------
/// stages
class Stage {
  const Stage({
    required this.id,
    required this.module,
    required this.week,
    required this.title,
    required this.whereAt,
    required this.task,
    required this.pass,
  });

  final int id;
  final String module;
  final int week;
  final String title;
  final String whereAt;
  final String task;
  final String pass;

  factory Stage.fromMap(Map<String, Object?> m) => Stage(
        id: m['id'] as int,
        module: m['module'] as String,
        week: m['week'] as int,
        title: m['title'] as String,
        whereAt: m['where_at'] as String,
        task: m['task'] as String,
        pass: m['pass'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'module': module,
        'week': week,
        'title': title,
        'where_at': whereAt,
        'task': task,
        'pass': pass,
      };

  /// 插入时用（id 自增，不含 id）
  Map<String, Object?> toInsertMap() => <String, Object?>{
        'module': module,
        'week': week,
        'title': title,
        'where_at': whereAt,
        'task': task,
        'pass': pass,
      };
}

/// --------------------------------------------------
/// streams
class Stream {
  const Stream({required this.id, required this.name});

  final int id;
  final String name;

  factory Stream.fromMap(Map<String, Object?> m) => Stream(
        id: m['id'] as int,
        name: m['name'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{'id': id, 'name': name};

  /// 插入时用（id 自增，不含 id）
  Map<String, Object?> toInsertMap() => <String, Object?>{'name': name};
}

/// --------------------------------------------------
/// app_settings
/// 注意：drift 里这张表的行类叫 AppSettingRows（@DataClassName 指定），
/// 保持同名，repo/seeder 里的引用才不用改。
class AppSettingRows {
  const AppSettingRows({required this.key, required this.value});

  final String key;
  final String value;

  factory AppSettingRows.fromMap(Map<String, Object?> m) => AppSettingRows(
        key: m['key'] as String,
        value: m['value'] as String,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'key': key,
        'value': value,
      };
}

/// 迁移链一致性自检（第 10 项）。
///
/// 验证「建表语句里的列」= 「基础列 + 历次 ALTER 加进来的列」。
/// 不一致意味着：新装用户（走建表）和老用户（走迁移）的表结构不同，
/// 会导致只有在老库上才出现的 bug。
///
/// 这个函数在 debug 启动时跑一次，不一致直接抛断言。
/// 生产 release 不调它，零成本。
void verifyMcqsMigrationChain() {
  assert(() {
    final String create = sqlCreateMcqs;
    final List<String> alters = <String>[
      ...kMigrateV2ToV3,
      ...kMigrateV3ToV4,
      ...kMigrateV4ToV5,
      ...kMigrateV5ToV6,
      ...kMigrateV6ToV7,
      ...kMigrateV7ToV8,
    ];
    final List<String> alterCols = alters
        .where((String sql) => sql.contains('ALTER TABLE mcqs'))
        .map((String sql) {
          final RegExpMatch? m =
              RegExp(r'ADD COLUMN (\w+)').firstMatch(sql);
          return m?.group(1) ?? '';
        })
        .where((String c) => c.isNotEmpty)
        .toList();

    // 基础列（建表语句自带，不来自 ALTER）
    final List<String> baseCols = <String>[
      'id', 'week', 'module', 'question', 'options', 'answer', 'explain',
      'wrong_count', 'right_streak',
    ];

    for (final String col in alterCols) {
      if (!create.contains(col)) {
        throw StateError('mcqs 迁移链与建表语句不一致：ALTER 加了 "$col"，'
            '但 sqlCreateMcqs 里没有。新装用户会缺这一列。');
      }
    }
    // 反向检查：同一个列名在迁移链里被 ALTER 了两次。
    // SQLite 不支持 ADD COLUMN IF NOT EXISTS，重复 ALTER 会让老库升级直接报
    // duplicate column name，新装用户感觉不到、升级用户一升就崩。
    final Set<String> seen = <String>{};
    for (final String col in alterCols) {
      if (!seen.add(col)) {
        throw StateError('mcqs 迁移链重复添加列 "$col"：ALTER 链里出现了两次。'
            'SQLite 不支持 ADD COLUMN IF NOT EXISTS，老库升级会报 '
            'duplicate column name。请只在最早引入该列的版本里 ALTER 一次。');
      }
    }
    // 建表语句自身不允许出现重名列（例如手抖粘两行）。
    final Map<String, int> createCols = <String, int>{};
    for (final RegExpMatch m
        in RegExp(r'^\s{2}(\w+)\s+\w', multiLine: true).allMatches(create)) {
      final String name = m.group(1)!;
      createCols[name] = (createCols[name] ?? 0) + 1;
    }
    for (final MapEntry<String, int> e in createCols.entries) {
      if (e.value > 1) {
        throw StateError('sqlCreateMcqs 里列 "${e.key}" 重复定义了 ${e.value} 次，'
            '建表会直接失败：duplicate column name: ${e.key}。');
      }
    }
    for (final String col in baseCols) {
      if (!create.contains(col)) {
        throw StateError('mcqs 建表语句缺基础列 "$col"。');
      }
    }
    return true;
  }());
}
