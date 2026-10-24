import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Drift database: 10 tables, schemaVersion 1.
/// Schema snapshots are exported to app/schemas/.
/// fallbackToDestructiveMigration is DEV ONLY; remove before release.
@DriftDatabase(
  tables: [
    Modules,
    Weeks,
    Items,
    Checkins,
    Cards,
    Mcqs,
    Concepts,
    Stages,
    Streams,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      for (final step in kMigrations) {
        if (step.from >= from && step.to <= to) {
          await step.run(m);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// A single schema migration step.
class MigrationStep {
  const MigrationStep({
    required this.from,
    required this.to,
    required this.run,
  });

  final int from;
  final int to;
  final Future<void> Function(Migrator m) run;
}

/// Empty on purpose: schemaVersion is still 1.
/// Add real steps here BEFORE removing fallbackToDestructiveMigration.
const List<MigrationStep> kMigrations = <MigrationStep>[];

/// Opens the on-disk sqlite file in a background isolate.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dir.path, 'study_tracker.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
