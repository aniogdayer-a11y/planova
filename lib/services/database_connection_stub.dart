import 'package:sqflite_common/sqlite_api.dart';

Future<Database> openPlannerDatabase(OpenDatabaseOptions options) =>
    throw UnsupportedError('Unsupported database platform.');

Future<Database> openTestDatabase(String path, OpenDatabaseOptions options) =>
    throw UnsupportedError('Unsupported database platform.');
