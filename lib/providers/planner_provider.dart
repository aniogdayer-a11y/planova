import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/feedback_model.dart';
import '../models/task_model.dart';
import '../models/plan_model.dart';
import '../models/schedule_slot_model.dart';
import '../models/user_profile_model.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../services/scheduler_service.dart';
import '../services/planner_repository.dart';

class _CompletionChange {
  final String date;
  final int id;
  final bool isTask;
  final bool completed;
  final String timestamp = DateTime.now().toIso8601String();
  _CompletionChange(this.date, this.id, this.isTask, this.completed);
}

class PlannerProvider extends ChangeNotifier {
  final PlannerRepository _db;
  final GeminiService _gemini;
  late final Future<void> ready;
  PlannerProvider({
    DatabaseService? database,
    PlannerRepository? repository,
    GeminiService? gemini,
  }) : _db = repository ?? database ?? DatabaseService(),
       _gemini = gemini ?? GeminiService() {
    ready = init();
  }

  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;
  bool _isLoadingPlan = false;
  bool get isLoadingPlan => _isLoadingPlan;
  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;
  int _generationCompleted = 0;
  int _generationTotal = 0;
  String get generationLabel => _generationTotal > 25
      ? 'Planning $_generationCompleted of $_generationTotal...'
      : 'Generating...';
  String? get generationNotice => _gemini.notice;
  bool _isSaving = false;
  bool get isSaving => _isSaving;
  String? _error;
  String? get error => _error;
  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  DateTime get selectedDate => _selectedDate;
  DateTime? _draftDate;
  DateTime get draftDate => _draftDate ?? _selectedDate;
  UserProfileModel? _profile;
  UserProfileModel? get profile => _profile;
  PlanModel? _currentPlan;
  PlanModel? get currentPlan => _currentPlan;
  List<Map<String, dynamic>> _weeklyActivity = [];
  List<Map<String, dynamic>> get weeklyActivity =>
      List.unmodifiable(_weeklyActivity);
  bool _is24Hour = false;
  bool get is24Hour => _is24Hour;
  String _colorTheme = 'cream';
  String get colorTheme => _colorTheme;
  final Set<String> _likedSuggestions = {};
  bool likesSuggestion(String id) => _likedSuggestions.contains(id);
  bool preferenceSaving(String key) => _pendingWrites.contains(key);

  List<FeedbackModel> _feedbackList = [];
  List<FeedbackModel> get feedbackList => List.unmodifiable(_feedbackList);
  bool _loadingFeedback = false;
  bool get loadingFeedback => _loadingFeedback;
  String? _feedbackError;
  String? get feedbackError => _feedbackError;

  Future<void> loadFeedback() async {
    _loadingFeedback = true;
    _feedbackError = null;
    notifyListeners();
    try {
      _feedbackList = await _db.getFeedback();
    } catch (error) {
      _feedbackError = 'Could not load feedback: $error';
    } finally {
      _loadingFeedback = false;
      notifyListeners();
    }
  }

  Future<void> addFeedback(
    String content, {
    String category = 'General Feedback',
    String recommendation = 'yes',
    String visibility = 'public',
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    final item = await _db.addFeedback(
      clean,
      category: category,
      recommendation: recommendation,
      visibility: visibility,
    );
    _feedbackList = [item, ..._feedbackList];
    notifyListeners();
  }

  Future<void> updateFeedback(
    String id,
    String content, {
    String category = 'General Feedback',
    String recommendation = 'yes',
    String visibility = 'public',
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    final updated = await _db.updateFeedback(
      id,
      clean,
      category: category,
      recommendation: recommendation,
      visibility: visibility,
    );
    _feedbackList = _feedbackList.map((f) => f.id == id ? updated : f).toList();
    notifyListeners();
  }

  Future<void> deleteFeedback(String id) async {
    await _db.deleteFeedback(id);
    _feedbackList = _feedbackList.where((f) => f.id != id).toList();
    notifyListeners();
  }

  Future<void> toggleFeedbackLike(String id) async {
    final key = 'feedback_like_$id';
    if (_pendingWrites.contains(key)) return;
    _pendingWrites.add(key);
    notifyListeners();
    try {
      final res = await _db.toggleFeedbackLike(id);
      final isLiked = res['is_liked_by_me'] as bool? ?? false;
      final count = (res['likes_count'] as num?)?.toInt() ?? 0;
      _feedbackList = _feedbackList.map((f) {
        if (f.id == id) {
          return f.copyWith(isLikedByMe: isLiked, likesCount: count);
        }
        return f;
      }).toList();
    } finally {
      _pendingWrites.remove(key);
      notifyListeners();
    }
  }

  Future<void> setColorTheme(String value) async {
    if (!['cream', 'sage', 'lavender', 'rose', 'sky'].contains(value) ||
        preferenceSaving('color_theme')) {
      return;
    }
    _pendingWrites.add('color_theme');
    notifyListeners();
    try {
      await _db.setSetting('color_theme', value);
      _colorTheme = value;
    } finally {
      _pendingWrites.remove('color_theme');
      notifyListeners();
    }
  }

  Future<void> toggleSuggestion(String id) async {
    final key = 'suggestion_like_$id';
    if (preferenceSaving(key)) return;
    final liked = !_likedSuggestions.contains(id);
    _pendingWrites.add(key);
    notifyListeners();
    try {
      await _db.setSetting(key, liked ? 'true' : 'false');
      liked ? _likedSuggestions.add(id) : _likedSuggestions.remove(id);
    } finally {
      _pendingWrites.remove(key);
      notifyListeners();
    }
  }

  int _loadVersion = 0;
  final Set<String> _pendingWrites = {};
  final Map<String, PlanModel> _completionBases = {};
  final List<_CompletionChange> _completionChanges = [];
  Future<void> _completionQueue = Future<void>.value();
  bool get isSyncingCompletions => _completionChanges.isNotEmpty;
  List<TaskModel> _draftTasks = [];
  List<TaskModel> get draftTasks => List.unmodifiable(_draftTasks);
  String _draftStartTime = '9:00 AM';
  String get draftStartTime => _draftStartTime;
  bool _draftHasBreaks = true;
  bool get draftHasBreaks => _draftHasBreaks;
  int _draftBreakCount = 1;
  int get draftBreakCount => _draftBreakCount;
  int _draftBreakDuration = 5;
  int get draftBreakDuration => _draftBreakDuration;

  Future<void> init() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _profile = await _db.getUserProfile();
      _colorTheme = await _db.getSetting('color_theme', defaultValue: 'cream');
      _likedSuggestions.clear();
      for (final id in ['short_list', 'enough_time', 'break']) {
        if (await _db.getSetting('suggestion_like_$id') == 'true') {
          _likedSuggestions.add(id);
        }
      }
      _is24Hour =
          await _db.getSetting('time_format', defaultValue: '12-hour') ==
          '24-hour';
      await loadFeedback();
      await _refreshStats();
      await loadPlanForSelectedDate();
    } catch (_) {
      _error = 'Could not open your planner. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (isSyncingCompletions) return;
    await loadPlanForSelectedDate();
    await _refreshStats();
    await loadFeedback();
    notifyListeners();
  }

  void setTabIndex(int index) {
    if (index < 0 || index > 4) return;
    _currentTabIndex = index;
    notifyListeners();
  }

  Future<void> selectDate(DateTime date) async {
    _selectedDate = DateUtils.dateOnly(date);
    _currentPlan = null;
    await loadPlanForSelectedDate();
  }

  Future<void> loadPlanForSelectedDate() async {
    final date = DateFormat('yyyy-MM-dd').format(_selectedDate);
    if (_completionBases.containsKey(date)) {
      _renderCompletions(date);
      notifyListeners();
      return;
    }
    final version = ++_loadVersion;
    _isLoadingPlan = _currentPlan == null;
    notifyListeners();
    try {
      final plan = await _db.getPlanForDate(date);
      if (version == _loadVersion) _currentPlan = plan;
    } finally {
      if (version == _loadVersion) {
        _isLoadingPlan = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshStats() async {
    _weeklyActivity = await _db.getWeeklyActivity();
    _profile = await _db.getUserProfile();
  }

  void preparePlanDraft({PlanModel? existingPlan}) {
    final plan = existingPlan ?? _currentPlan;
    _draftDate = _selectedDate;
    if (_db is DraftAwareRepository) {
      (_db as DraftAwareRepository).beginDraft(
        DateFormat('yyyy-MM-dd').format(_selectedDate),
      );
    }
    _draftTasks = List.of(plan?.tasks ?? []);
    _draftStartTime = plan?.startTime ?? '9:00 AM';
    _draftHasBreaks = plan?.hasBreaks ?? true;
    _draftBreakCount = (plan?.breakCount ?? 1).clamp(1, 3);
    _draftBreakDuration = plan?.breakDurationMinutes ?? 5;
    notifyListeners();
  }

  bool addDraftTask(String title, {int duration = 0}) {
    return addDraftTasks([title], duration: duration);
  }

  bool addDraftTasks(List<String> titles, {int duration = 0}) {
    final clean = titles.map((title) => title.trim()).toList();
    final names = _draftTasks.map((task) => task.title.toLowerCase()).toSet();
    if (clean.isEmpty ||
        _draftTasks.length + clean.length > SchedulerService.maxTasks ||
        clean.any(
          (title) =>
              title.isEmpty ||
              title.length > 200 ||
              !names.add(title.toLowerCase()),
        )) {
      return false;
    }
    for (final title in clean) {
      _draftTasks.add(
        TaskModel(
          title: title,
          durationMinutes: duration,
          orderIndex: _draftTasks.length,
        ),
      );
    }
    notifyListeners();
    return true;
  }

  void removeDraftTask(int index) {
    _draftTasks.removeAt(index);
    notifyListeners();
  }

  void setDraftDuration(int index, int duration) {
    final task = _draftTasks[index];
    _draftTasks[index] = TaskModel(
      id: task.id,
      planId: task.planId,
      title: task.title,
      durationMinutes: duration,
      orderIndex: task.orderIndex,
    );
    notifyListeners();
  }

  void setDraftStartTime(String value) {
    _draftStartTime = value;
    notifyListeners();
  }

  void setDraftHasBreaks(bool value) {
    _draftHasBreaks = value;
    notifyListeners();
  }

  void setDraftBreakCount(int value) {
    _draftBreakCount = value;
    notifyListeners();
  }

  void setDraftBreakDuration(int value) {
    _draftBreakDuration = value;
    notifyListeners();
  }

  ScheduleResult preview({List<TaskModel>? tasks}) =>
      SchedulerService.generateSchedule(
        tasks: tasks ?? _draftTasks,
        startTimeStr: _draftStartTime,
        hasBreaks: _draftHasBreaks,
        breakCount: _draftBreakCount,
        breakDurationMinutes: _draftBreakDuration,
      );

  Future<void> generateDraft({bool useGemini = true}) async {
    if (_isGenerating) return;
    _isGenerating = true;
    notifyListeners();
    try {
      final tasks = useGemini
          ? await _gemini.generate(
              tasks: List.of(_draftTasks),
              date: draftDate,
              startTime: _draftStartTime,
              breakCount: _draftHasBreaks ? _draftBreakCount : 0,
              breakMinutes: _draftHasBreaks ? _draftBreakDuration : 0,
              onProgress: (completed, total) {
                _generationCompleted = completed;
                _generationTotal = total;
                notifyListeners();
              },
            )
          : _draftTasks
                .map(
                  (t) => t.durationMinutes == 0
                      ? t.copyWith(durationMinutes: 30)
                      : t,
                )
                .toList();
      preview(tasks: tasks);
      _draftTasks = tasks;
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  bool _submittingPlan = false;

  Future<void> deleteTask(int id) async {
    if (_isSaving || _isGenerating || _currentPlan == null) return;
    final date = _currentPlan!.planDate;
    _isSaving = true;
    ++_loadVersion;
    notifyListeners();
    try {
      await _completionQueue;
      final plan = _currentPlan;
      if (plan == null || plan.planDate != date) return;
      final remaining = plan.tasks.where((task) => task.id != id).toList();
      if (remaining.length == plan.tasks.length) return;
      if (remaining.isEmpty) {
        await _db.deletePlanForDate(date);
        if (_currentPlan?.planDate == date) _currentPlan = null;
      } else {
        if (_db is DraftAwareRepository) {
          (_db as DraftAwareRepository).beginDraft(date);
        }
        final focus = remaining.fold(
          0,
          (sum, task) => sum + task.durationMinutes,
        );
        final breaks = plan.hasBreaks ? plan.breakCount.clamp(0, focus - 1) : 0;
        final saved = await _db.saveOrUpdatePlan(
          plan.copyWith(hasBreaks: breaks > 0, breakCount: breaks),
          remaining,
        );
        if (_currentPlan?.planDate == date) _currentPlan = saved;
      }
      notifyListeners();
      unawaited(_syncCompletionStats());
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> generateAndSaveDraft({bool useGemini = true}) async {
    if (_submittingPlan || _isGenerating || _isSaving) return;
    _submittingPlan = true;
    try {
      await generateDraft(useGemini: useGemini);
      await saveDraft();
    } finally {
      _submittingPlan = false;
    }
  }

  Future<void> saveDraft() async {
    if (_isSaving) return;
    _isSaving = true;
    notifyListeners();
    try {
      final result = preview();
      final plan = PlanModel(
        planDate: DateFormat('yyyy-MM-dd').format(draftDate),
        startTime: _draftStartTime,
        hasBreaks: _draftHasBreaks,
        breakCount: _draftHasBreaks ? _draftBreakCount : 0,
        breakDurationMinutes: _draftHasBreaks ? _draftBreakDuration : 0,
        totalFocusMinutes: result.totalFocusMinutes,
        endTime: result.endTime,
        createdAt: DateTime.now().toIso8601String(),
      );
      await _db.saveOrUpdatePlan(plan, List.of(_draftTasks));
      _selectedDate = draftDate;
      await loadPlanForSelectedDate();
      await _refreshStats();
      _currentTabIndex = 1;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _renderCompletions(String date) {
    var plan = _completionBases[date]!;
    for (final change in _completionChanges.where((c) => c.date == date)) {
      final slots = plan.scheduleSlots.map((slot) {
        final affected = change.isTask
            ? slot.taskId == change.id && slot.slotType == SlotType.focus
            : slot.id == change.id;
        return affected ? slot.copyWith(isCompleted: change.completed) : slot;
      }).toList();
      final changedSlot = change.isTask
          ? null
          : plan.scheduleSlots.where((s) => s.id == change.id).firstOrNull;
      final taskId = change.isTask ? change.id : changedSlot?.taskId;
      final tasks = plan.tasks.map((task) {
        if (task.id != taskId) return task;
        final completed = change.isTask
            ? change.completed
            : slots
                  .where(
                    (s) => s.taskId == taskId && s.slotType == SlotType.focus,
                  )
                  .every((s) => s.isCompleted);
        return task.copyWith(
          isCompleted: completed,
          completedAt: task.completedAt ?? change.timestamp,
        );
      }).toList();
      plan = plan.copyWith(tasks: tasks, scheduleSlots: slots);
    }
    if (date == DateFormat('yyyy-MM-dd').format(_selectedDate)) {
      _currentPlan = plan;
      _isLoadingPlan = false;
    }
  }

  Future<void> _writeCompletion(
    int id,
    bool completed, {
    required bool isTask,
  }) {
    if (_isSaving) return Future<void>.value();
    final plan = _currentPlan;
    if (plan == null) return Future<void>.value();
    final exists = isTask
        ? plan.tasks.any((t) => t.id == id)
        : plan.scheduleSlots.any((s) => s.id == id);
    if (!exists) return Future<void>.value();
    final date = plan.planDate;
    final change = _CompletionChange(date, id, isTask, completed);
    _completionBases.putIfAbsent(date, () => plan);
    _completionChanges.add(change);
    ++_loadVersion; // An older refresh must not replace the immediate change.
    _renderCompletions(date);
    notifyListeners();

    final pending = _completionQueue.then((_) async {
      try {
        PlanModel? saved;
        if (_db is CompletionRepository) {
          final repository = _db as CompletionRepository;
          saved = isTask
              ? await repository.completeTask(id, completed)
              : await repository.completeSlot(id, completed);
        } else {
          if (isTask) {
            await _db.toggleTaskCompletion(id, completed);
          } else {
            await _db.toggleSlotCompletion(id, completed);
          }
          saved = await _db.getPlanForDate(date);
        }
        if (saved != null) _completionBases[date] = saved;
      } finally {
        // Reapply later clicks over the confirmed state; a failed click rolls
        // back without erasing another task's successful or pending changes.
        _completionChanges.remove(change);
        _renderCompletions(date);
        if (!_completionChanges.any((c) => c.date == date)) {
          _completionBases.remove(date);
        }
        notifyListeners();
        if (!isSyncingCompletions) unawaited(_syncCompletionStats());
      }
    });
    _completionQueue = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<void> _syncCompletionStats() async {
    try {
      await _refreshStats();
      notifyListeners();
    } catch (_) {
      // A stats refresh failure must not undo a successfully saved checkbox.
      // The regular background sync retries these totals.
    }
  }

  Future<void> toggleTaskCompletion(int id) async {
    final task = _currentPlan?.tasks.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      await setTaskCompletion(id, !task.isCompleted);
    }
  }

  Future<void> setTaskCompletion(int id, bool completed) async {
    await _writeCompletion(id, completed, isTask: true);
  }

  Future<void> toggleSlotCompletion(int id) async {
    final slot = _currentPlan?.scheduleSlots
        .where((s) => s.id == id)
        .firstOrNull;
    if (slot != null) {
      await setSlotCompletion(id, !slot.isCompleted);
    }
  }

  Future<void> setSlotCompletion(int id, bool completed) async {
    await _writeCompletion(id, completed, isTask: false);
  }

  Future<void> toggleTimeFormat(bool value) async {
    await _db.setSetting('time_format', value ? '24-hour' : '12-hour');
    _is24Hour = value;
    notifyListeners();
  }

  Future<void> updateName(String name) async {
    if (_profile == null || name.trim().isEmpty) return;
    final profile = _profile!.copyWith(name: name.trim());
    await _db.updateUserProfile(profile);
    _profile = profile;
    notifyListeners();
  }

  bool get canUpdateAvatar => _db is AvatarRepository;
  Future<void> updateAvatar(List<int>? bytes) async {
    if (_db is! AvatarRepository) return;
    await (_db as AvatarRepository).updateAvatar(bytes);
    _profile = await _db.getUserProfile();
    notifyListeners();
  }

  String displayTime(String value) => SchedulerService.formatTime(
    SchedulerService.parseTimeString(value),
    is24Hour: _is24Hour,
  );
  int get tasksDoneCount =>
      _currentPlan?.tasks.where((t) => t.isCompleted).length ?? 0;
  int get pendingTasksCount =>
      _currentPlan?.tasks.where((t) => !t.isCompleted).length ?? 0;
  int get streakCount => _profile?.streakCount ?? 0;
}
