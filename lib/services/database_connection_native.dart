import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openPlannerDatabase(OpenDatabaseOptions options) async {
  final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final testing = Platform.environment.containsKey('FLUTTER_TEST');
  final path = testing
      ? inMemoryDatabasePath
      : join(
          (await getApplicationDocumentsDirectory()).path,
          'auto_task_scheduler_v1.db',
        );
  if (desktop || testing) return openTestDatabase(path, options);
  return mobile.openDatabase(
    path,
    version: options.version,
    onConfigure: options.onConfigure,
    onCreate: options.onCreate,
    onUpgrade: options.onUpgrade,
  );
}

Future<Database> openTestDatabase(String path, OpenDatabaseOptions options) {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(path, options: options);
}
