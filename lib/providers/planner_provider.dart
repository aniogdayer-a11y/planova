import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../models/plan_model.dart';
import '../models/user_profile_model.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../services/scheduler_service.dart';
import '../services/planner_repository.dart';

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
  int _loadVersion = 0;
  final Set<String> _pendingWrites = {};
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
      _is24Hour =
          await _db.getSetting('time_format', defaultValue: '12-hour') ==
          '24-hour';
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
    await loadPlanForSelectedDate();
    await _refreshStats();
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
    final version = ++_loadVersion;
    final date = DateFormat('yyyy-MM-dd').format(_selectedDate);
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
    final clean = title.trim();
    if (clean.isEmpty ||
        clean.length > 200 ||
        _draftTasks.length >= 30 ||
        _draftTasks.any((t) => t.title.toLowerCase() == clean.toLowerCase())) {
      return false;
    }
    _draftTasks.add(
      TaskModel(
        title: clean,
        durationMinutes: duration,
        orderIndex: _draftTasks.length,
      ),
    );
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

  Future<void> _writeCompletion(
    String key,
    Future<void> Function() write,
  ) async {
    if (!_pendingWrites.add(key)) return;
    try {
      await write();
      await loadPlanForSelectedDate();
      await _refreshStats();
    } finally {
      _pendingWrites.remove(key);
      notifyListeners();
    }
  }

  Future<void> toggleTaskCompletion(int id) async {
    final task = _currentPlan?.tasks.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      await _writeCompletion(
        'task:$id',
        () => _db.toggleTaskCompletion(id, !task.isCompleted),
      );
    }
  }

  Future<void> toggleSlotCompletion(int id) async {
    final slot = _currentPlan?.scheduleSlots
        .where((s) => s.id == id)
        .firstOrNull;
    if (slot != null) {
      await _writeCompletion(
        'slot:$id',
        () => _db.toggleSlotCompletion(id, !slot.isCompleted),
      );
    }
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
