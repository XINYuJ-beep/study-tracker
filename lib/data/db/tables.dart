import 'package:drift/drift.dart';

/// Ten tables total.
/// review_queue is NOT a table: it is a VIEW over (cards UNION concepts).
/// ====================================
/// Table 1: Modules
/// id: A1..A8 / title / sub / color / goal / accept / weeks
@DataClassName('Modules')
class Modules extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get sub => text()();
  TextColumn get color => text()();
  TextColumn get goal => text()();
  TextColumn get accept => text()();
  IntColumn get weeks => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

/// ====================================
/// Table 2: Weeks (week 1..92)
/// review may be null; completedAt null = not finished
@DataClassName('Weeks')
class Weeks extends Table {
  IntColumn get week => integer()();
  TextColumn get title => text()();
  TextColumn get goal => text()();
  TextColumn get review => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {week};
}

/// ====================================
/// Table 3: Items (644 items = 92 weeks x 7)
/// NOTE: NO done flag here. Done is derived from checkins table.
@DataClassName('Items')
class Items extends Table {
  TextColumn get id => text()();
  IntColumn get week => integer()();
  IntColumn get day => integer()();
  TextColumn get watch => text()();
  TextColumn get practice => text()();
  TextColumn get output => text()();
  IntColumn get minutes => integer().notNull().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

/// ====================================
/// Table 4: Checkins (the done records)
/// Composite PK {itemId, date}.
/// done defaults true so an un-undoed row means checked.
/// completedAt is required by the 5-second undo window.
/// date is stored at 00:00 local; day boundary = 04:00 rule is
/// applied in the repo layer, not here.
@DataClassName('Checkins')
class Checkins extends Table {
  TextColumn get itemId => text()();
  DateTimeColumn get date => dateTime()();
  BoolColumn get done => boolean().notNull().withDefault(const Constant(true))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {itemId, date};
}

/// ====================================
/// Table 5: Cards (736 recall cards)
/// stage 0..6 = D1 D2 D4 D7 D15 D30 graduated
/// ease default 2.5 (SM-2 style)
@DataClassName('Cards')
class Cards extends Table {
  TextColumn get id => text()();
  IntColumn get week => integer().nullable()();
  TextColumn get module => text().nullable()();
  TextColumn get front => text()();
  TextColumn get back => text()();
  TextColumn get type => text()();
  IntColumn get stage => integer().notNull().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get ease => real().notNull().withDefault(const Constant(2.5))();
  @override
  Set<Column> get primaryKey => {id};
}

/// ====================================
/// Table 6: Mcqs (276 choice questions)
/// wrongCount / rightStreak: 2 consecutive right => leave wrong book
/// options stored as JSON string array, answer is int index 0..3
@DataClassName('Mcqs')
class Mcqs extends Table {
  TextColumn get id => text()();
  IntColumn get week => integer().nullable()();
  TextColumn get module => text().nullable()();
  TextColumn get question => text()();
  TextColumn get options => text()();
  IntColumn get answer => integer()();
  TextColumn get explain => text().nullable()();
  IntColumn get wrongCount => integer().notNull().withDefault(const Constant(0))();
  IntColumn get rightStreak => integer().notNull().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

/// ====================================
/// Table 7: Concepts (129 concepts, whiteboard recitation)
/// level 0 basic / 1 medium / 2 advanced -> affects difficulty
/// auto-increment id because concepts.json has no id field
@DataClassName('Concepts')
class Concepts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get term => text()();
  TextColumn get definition => text()();
  IntColumn get week => integer().nullable()();
  IntColumn get level => integer().notNull().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get ease => real().notNull().withDefault(const Constant(2.5))();
  IntColumn get reps => integer().notNull().withDefault(const Constant(0))();
}

/// ====================================
/// Table 8: Stages (8 milestone stages)
/// JSON key is 'where'; renamed to whereAt to avoid SQL keyword
@DataClassName('Stages')
class Stages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get module => text()();
  IntColumn get week => integer()();
  TextColumn get title => text()();
  TextColumn get whereAt => text().named('where_at')();
  TextColumn get task => text()();
  TextColumn get pass => text()();
}

/// ====================================
/// Table 9: Streams (6 stream names)
@DataClassName('Streams')
class Streams extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

/// ====================================
/// Table 10: AppSettings (key-value store)
/// DataClassName avoids clash with drift 'settings' keyword
@DataClassName('AppSettingRows')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// ------------------------------------
/// review_queue is NOT a table: it is a VIEW over (cards UNION concepts).
/// Stage 0..6 maps to D1 / D2 / D4 / D7 / D15 / D30 / graduated.
/// ------------------------------------
