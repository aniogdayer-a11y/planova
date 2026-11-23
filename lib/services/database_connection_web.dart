import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> openPlannerDatabase(OpenDatabaseOptions options) =>
    databaseFactoryFfiWeb.openDatabase(
      'auto_task_scheduler_v1.db',
      options: options,
    );

Future<Database> openTestDatabase(String path, OpenDatabaseOptions options) =>
    throw UnsupportedError('Use native database tests.');
