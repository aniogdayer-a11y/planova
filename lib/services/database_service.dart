import 'package:intl/intl.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'database_connection_stub.dart'
    if (dart.library.io) 'database_connection_native.dart'
    if (dart.library.js_interop) 'database_connection_web.dart'
    as connection;
import '../models/feedback_model.dart';
import '../models/task_model.dart';
import '../models/plan_model.dart';
import '../models/schedule_slot_model.dart';
import '../models/user_profile_model.dart';
import 'scheduler_service.dart';
import 'planner_repository.dart';

class DatabaseService implements PlannerRepository {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();
  Database? _db;
  Future<Database>? _opening;

  static Future<DatabaseService> inMemory() => openForTesting();

  static Future<DatabaseService> openForTesting({
    String path = ':memory:',
  }) async {
    final service = DatabaseService._internal();
    service._db = await connection.openTestDatabase(path, _options);
    return service;
  }

  static OpenDatabaseOptions get _options => OpenDatabaseOptions(
    version: 2,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: _onCreate,
    onUpgrade: (db, oldVersion, newVersion) async {
      // Keep existing plans and settings. Activity is now derived from completions.
      await db.execute(
        'CREATE INDEX IF NOT EXISTS tasks_plan ON tasks(plan_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS slots_plan ON schedule_slots(plan_id)',
      );
      await db.execute('''CREATE TABLE IF NOT EXISTS feedback (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, author_name TEXT NOT NULL,
        content TEXT NOT NULL, visibility TEXT NOT NULL, created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS feedback_likes (
        feedback_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL,
        PRIMARY KEY (feedback_id, user_id))''');
    },
  );

  Future<Database> get database async {
    if (_db != null) return _db!;
    try {
      return _db = await (_opening ??= connection.openPlannerDatabase(
        _options,
      ));
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE user_profile (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, workspace TEXT NOT NULL,
      tagline TEXT NOT NULL, avatar_url TEXT, streak_count INTEGER NOT NULL,
      last_active_date TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT, plan_date TEXT NOT NULL,
      start_time TEXT NOT NULL, has_breaks INTEGER NOT NULL, break_count INTEGER NOT NULL,
      break_duration_minutes INTEGER NOT NULL, total_focus_minutes INTEGER NOT NULL,
      end_time TEXT NOT NULL, created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL,
      title TEXT NOT NULL, duration_minutes INTEGER NOT NULL, order_index INTEGER NOT NULL,
      is_completed INTEGER NOT NULL, completed_at TEXT,
      FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE schedule_slots (
      id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL, task_id INTEGER,
      slot_type TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT, start_time TEXT NOT NULL,
      end_time TEXT NOT NULL, duration_minutes INTEGER NOT NULL, order_index INTEGER NOT NULL,
      is_completed INTEGER NOT NULL,
      FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE CASCADE,
      FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE)''');
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS feedback (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, author_name TEXT NOT NULL,
      content TEXT NOT NULL, visibility TEXT NOT NULL, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS feedback_likes (
      feedback_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TEXT NOT NULL,
      PRIMARY KEY (feedback_id, user_id))''');
    await db.execute('CREATE INDEX tasks_plan ON tasks(plan_id)');
    await db.execute('CREATE INDEX slots_plan ON schedule_slots(plan_id)');
    await db.insert('user_profile', {
      'id': 1,
      'name': 'Dayer',
      'workspace': 'Personal',
      'tagline': '',
      'avatar_url': '',
      'streak_count': 0,
      'last_active_date': '',
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }

  @override
  Future<UserProfileModel> getUserProfile({DateTime? today}) async {
    final db = await database;
    final rows = await db.query('user_profile', where: 'id = 1');
    return UserProfileModel.fromMap(
      rows.first,
    ).copyWith(streakCount: await getStreak(today: today));
  }

  @override
  Future<void> updateUserProfile(UserProfileModel profile) async {
    final db = await database;
    await db.update(
      'user_profile',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  @override
  Future<PlanModel?> getPlanForDate(String date) async =>
      _readPlan(await database, date);

  static Future<PlanModel?> _readPlan(DatabaseExecutor db, String date) async {
    final rows = await db.query(
      'plans',
      where: 'plan_date = ?',
      whereArgs: [date],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = rows.first['id'];
    final tasks = await db.query(
      'tasks',
      where: 'plan_id = ?',
      whereArgs: [id],
      orderBy: 'order_index',
    );
    final slots = await db.query(
      'schedule_slots',
      where: 'plan_id = ?',
      whereArgs: [id],
      orderBy: 'order_index',
    );
    return PlanModel.fromMap(
      rows.first,
      tasks: tasks.map(TaskModel.fromMap).toList(),
      scheduleSlots: slots.map(ScheduleSlotModel.fromMap).toList(),
    );
  }

  @override
  Future<PlanModel> saveOrUpdatePlan(
    PlanModel plan,
    List<TaskModel> tasks,
  ) async {
    // Validate before opening a transaction or replacing any existing data.
    SchedulerService.generateSchedule(
      tasks: tasks,
      startTimeStr: plan.startTime,
      hasBreaks: plan.hasBreaks,
      breakCount: plan.breakCount,
      breakDurationMinutes: plan.breakDurationMinutes,
    );
    final db = await database;
    return db.transaction((txn) async {
      final existing = await _readPlan(txn, plan.planDate);
      final values = plan.toMap()..remove('id');
      if (existing != null) values['created_at'] = existing.createdAt;
      final int id;
      if (existing != null) {
        id = existing.id!;
        await txn.update('plans', values, where: 'id = ?', whereArgs: [id]);
        await txn.delete(
          'schedule_slots',
          where: 'plan_id = ?',
          whereArgs: [id],
        );
        await txn.delete('tasks', where: 'plan_id = ?', whereArgs: [id]);
      } else {
        id = await txn.insert('plans', values);
      }
      final saved = <TaskModel>[];
      for (var i = 0; i < tasks.length; i++) {
        final task = tasks[i];
        final data = task.toMap()..remove('id');
        data['plan_id'] = id;
        data['order_index'] = i;
        final taskId = await txn.insert('tasks', data);
        saved.add(
          TaskModel(
            id: taskId,
            planId: id,
            title: task.title,
            durationMinutes: task.durationMinutes,
            orderIndex: i,
            isCompleted: task.isCompleted,
            completedAt: task.isCompleted ? task.completedAt : null,
          ),
        );
      }
      final result = SchedulerService.generateSchedule(
        tasks: saved,
        startTimeStr: plan.startTime,
        hasBreaks: plan.hasBreaks,
        breakCount: plan.breakCount,
        breakDurationMinutes: plan.breakDurationMinutes,
      );
      final savedSlots = <ScheduleSlotModel>[];
      for (final slot in result.slots) {
        var completed = slot.isCompleted;
        // Keep partial progress when an edit leaves a task's session durations unchanged.
        if (existing != null && slot.taskId != null && !completed) {
          final index = saved.indexWhere((task) => task.id == slot.taskId);
          final oldId = tasks[index].id;
          final oldSlots = existing.scheduleSlots
              .where((s) => s.taskId == oldId)
              .toList();
          final newSlots = result.slots
              .where((s) => s.taskId == slot.taskId)
              .toList();
          if (oldSlots.length == newSlots.length &&
              List.generate(
                oldSlots.length,
                (i) =>
                    oldSlots[i].durationMinutes == newSlots[i].durationMinutes,
              ).every((v) => v)) {
            completed = oldSlots[newSlots.indexOf(slot)].isCompleted;
          }
        }
        final data = slot.toMap()..remove('id');
        data['plan_id'] = id;
        data['is_completed'] = completed ? 1 : 0;
        final slotId = await txn.insert('schedule_slots', data);
        savedSlots.add(
          slot.copyWith(id: slotId, planId: id, isCompleted: completed),
        );
      }
      await txn.update(
        'plans',
        {
          'end_time': result.endTime,
          'total_focus_minutes': result.totalFocusMinutes,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return plan.copyWith(
        id: id,
        tasks: saved,
        scheduleSlots: savedSlots,
        endTime: result.endTime,
        totalFocusMinutes: result.totalFocusMinutes,
      );
    });
  }

  @override
  Future<void> toggleTaskCompletion(int id, bool completed) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'tasks',
        {
          'is_completed': completed ? 1 : 0,
          'completed_at': completed ? DateTime.now().toIso8601String() : null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'schedule_slots',
        {'is_completed': completed ? 1 : 0},
        where: "task_id = ? AND slot_type = 'focus'",
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> toggleSlotCompletion(int id, bool completed) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'schedule_slots',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      await txn.update(
        'schedule_slots',
        {'is_completed': completed ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      final taskId = rows.first['task_id'];
      if (taskId == null || rows.first['slot_type'] != 'focus') return;
      final slots = await txn.query(
        'schedule_slots',
        where: "task_id = ? AND slot_type = 'focus'",
        whereArgs: [taskId],
      );
      final allDone = slots.every((row) => row['is_completed'] == 1);
      final task = (await txn.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [taskId],
      )).first;
      await txn.update(
        'tasks',
        {
          'is_completed': allDone ? 1 : 0,
          'completed_at': allDone
              ? (task['completed_at'] ?? DateTime.now().toIso8601String())
              : null,
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getWeeklyActivity({
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = DateTime(end.year, end.month, end.day - 6);
    final fmt = DateFormat('yyyy-MM-dd');
    final db = await database;
    final rows = await db.rawQuery(
      '''SELECT substr(completed_at, 1, 10) AS date, COUNT(*) AS tasks_completed
      FROM tasks WHERE is_completed = 1 AND substr(completed_at, 1, 10) BETWEEN ? AND ?
      GROUP BY substr(completed_at, 1, 10)''',
      [fmt.format(start), fmt.format(end)],
    );
    final counts = {
      for (final row in rows) row['date']: row['tasks_completed'] as int,
    };
    return List.generate(7, (i) {
      final date = fmt.format(DateTime(start.year, start.month, start.day + i));
      final count = counts[date] ?? 0;
      return {
        'date': date,
        'tasks_completed': count,
        'is_active': count > 0 ? 1 : 0,
      };
    });
  }

  Future<int> getStreak({DateTime? today}) async {
    final now = today ?? DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    final db = await database;
    final rows = await db.rawQuery(
      '''SELECT DISTINCT substr(completed_at, 1, 10) AS date
      FROM tasks WHERE is_completed = 1 AND completed_at IS NOT NULL''',
    );
    final dates = rows.map((row) => row['date']).toSet();
    final fmt = DateFormat('yyyy-MM-dd');
    if (!dates.contains(fmt.format(cursor))) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    var count = 0;
    while (dates.contains(fmt.format(cursor))) {
      count++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return count;
  }

  @override
  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    final rows = await (await database).query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? defaultValue : rows.first['value'] as String;
  }

  @override
  Future<void> setSetting(String key, String value) async =>
      (await database).insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<List<FeedbackModel>> getFeedback() async {
    final db = await database;
    var rows = await db.query('feedback', orderBy: 'created_at DESC');
    if (rows.isEmpty) {
      final now = DateTime.now().toIso8601String();
      final defaults = [
        {'id': 'fb-1', 'content': 'Start with the tasks you can realistically finish today.'},
        {'id': 'fb-2', 'content': 'Leave a little room between tasks so you do not have to rush.'},
        {'id': 'fb-3', 'content': 'Add a short break between focus sessions.'},
      ];
      for (final d in defaults) {
        await db.insert('feedback', {
          'id': d['id']!,
          'user_id': '1',
          'author_name': 'Planova',
          'content': d['content']!,
          'visibility': 'public',
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      rows = await db.query('feedback', orderBy: 'created_at DESC');
    }
    final likes = await db.query('feedback_likes');
    final counts = <String, int>{};
    final myLikes = <String>{};
    for (final l in likes) {
      final fbId = l['feedback_id'] as String;
      counts[fbId] = (counts[fbId] ?? 0) + 1;
      if (l['user_id'] == '1') myLikes.add(fbId);
    }
    return rows.map((r) {
      final id = r['id'] as String;
      return FeedbackModel.fromMap({
        ...r,
        'likes_count': counts[id] ?? 0,
        'is_liked_by_me': myLikes.contains(id),
        'is_mine': r['user_id'] == '1',
      });
    }).toList();
  }

  @override
  Future<FeedbackModel> addFeedback(
    String content, {
    String visibility = 'public',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final id = 'fb_${DateTime.now().microsecondsSinceEpoch}';
    final profile = await getUserProfile();
    final item = {
      'id': id,
      'user_id': '1',
      'author_name': profile.name.isNotEmpty ? profile.name : 'Planova User',
      'content': content.trim(),
      'visibility': visibility,
      'created_at': now,
      'updated_at': now,
    };
    await db.insert('feedback', item);
    return FeedbackModel.fromMap({
      ...item,
      'likes_count': 0,
      'is_liked_by_me': false,
      'is_mine': true,
    });
  }

  @override
  Future<FeedbackModel> updateFeedback(
    String id,
    String content, {
    String visibility = 'public',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query('feedback', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw Exception('Feedback not found');
    final existing = rows.first;
    final updated = {
      ...existing,
      'content': content.trim(),
      'visibility': visibility,
      'updated_at': now,
    };
    await db.update('feedback', updated, where: 'id = ?', whereArgs: [id]);
    final likes = await db.query(
      'feedback_likes',
      where: 'feedback_id = ?',
      whereArgs: [id],
    );
    final isLiked = likes.any((l) => l['user_id'] == '1');
    return FeedbackModel.fromMap({
      ...updated,
      'likes_count': likes.length,
      'is_liked_by_me': isLiked,
      'is_mine': true,
    });
  }

  @override
  Future<void> deleteFeedback(String id) async {
    final db = await database;
    await db.delete('feedback', where: 'id = ?', whereArgs: [id]);
    await db.delete('feedback_likes', where: 'feedback_id = ?', whereArgs: [id]);
  }

  @override
  Future<Map<String, dynamic>> toggleFeedbackLike(String id) async {
    final db = await database;
    final existing = await db.query(
      'feedback_likes',
      where: 'feedback_id = ? AND user_id = ?',
      whereArgs: [id, '1'],
    );
    if (existing.isNotEmpty) {
      await db.delete(
        'feedback_likes',
        where: 'feedback_id = ? AND user_id = ?',
        whereArgs: [id, '1'],
      );
    } else {
      await db.insert('feedback_likes', {
        'feedback_id': id,
        'user_id': '1',
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final allLikes = await db.query(
      'feedback_likes',
      where: 'feedback_id = ?',
      whereArgs: [id],
    );
    return {
      'is_liked_by_me': existing.isEmpty,
      'likes_count': allLikes.length,
    };
  }
}
