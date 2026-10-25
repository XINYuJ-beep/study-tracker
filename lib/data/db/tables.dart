/// 十张本地表的建表 SQL 与表名常量（sqflite 版，已移除 drift）。
///
/// 说明：
/// - 表结构完全等价于原 drift 定义，schemaVersion 仍为 1。
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

/// 性能索引（SPEC 第 16 节：checkins(item_id)、checkins(date) 建索引）
const List<String> kCreateIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_checkins_item ON checkins (item_id)',
  'CREATE INDEX IF NOT EXISTS idx_checkins_date ON checkins (date)',
  'CREATE INDEX IF NOT EXISTS idx_cards_due ON cards (due_date)',
  'CREATE INDEX IF NOT EXISTS idx_items_week ON items (week)',
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
  ease       REAL NOT NULL DEFAULT 2.5
)''';

/// ====================================
/// 表 6: mcqs (276 道选择题)
/// wrong_count / right_streak: 连对 2 次移出错题本
/// options 存 JSON 字符串数组，answer 是 0..3 的下标
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
  right_streak  INTEGER NOT NULL DEFAULT 0
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
  });

  final String id;
  final int? week;
  final String? module;
  final String question;
  final String options;
  final int answer;
  final String? explain;
  final int wrongCount;
  final int rightStreak;

  factory Mcq.fromMap(Map<String, Object?> m) => Mcq(
        id: m['id'] as String,
        week: m['week'] as int?,
        module: m['module'] as String?,
        question: m['question'] as String,
        options: m['options'] as String,
        answer: m['answer'] as int,
        explain: m['explain'] as String?,
        wrongCount: m['wrong_count'] as int,
        rightStreak: m['right_streak'] as int,
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
      };
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
