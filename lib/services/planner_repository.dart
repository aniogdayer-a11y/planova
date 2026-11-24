import '../models/feedback_model.dart';
import '../models/plan_model.dart';
import '../models/task_model.dart';
import '../models/user_profile_model.dart';

abstract class PlannerRepository {
  Future<UserProfileModel> getUserProfile({DateTime? today});
  Future<void> updateUserProfile(UserProfileModel profile);
  Future<PlanModel?> getPlanForDate(String date);
  Future<PlanModel> saveOrUpdatePlan(PlanModel plan, List<TaskModel> tasks);
  Future<void> deletePlanForDate(String date);
  Future<void> toggleTaskCompletion(int id, bool completed);
  Future<void> toggleSlotCompletion(int id, bool completed);
  Future<List<Map<String, dynamic>>> getWeeklyActivity({DateTime? today});
  Future<String> getSetting(String key, {String defaultValue = ''});
  Future<void> setSetting(String key, String value);
  Future<List<FeedbackModel>> getFeedback();
  Future<FeedbackModel> addFeedback(
    String content, {
    String category = 'General Feedback',
    String recommendation = 'yes',
    String visibility = 'public',
  });
  Future<FeedbackModel> updateFeedback(
    String id,
    String content, {
    String category = 'General Feedback',
    String recommendation = 'yes',
    String visibility = 'public',
  });
  Future<void> deleteFeedback(String id);
  Future<Map<String, dynamic>> toggleFeedbackLike(String id);
}

abstract class DraftAwareRepository {
  void beginDraft(String date);
}

abstract class CompletionRepository {
  Future<PlanModel> completeTask(int id, bool completed);
  Future<PlanModel> completeSlot(int id, bool completed);
}

abstract class AvatarRepository {
  Future<void> updateAvatar(List<int>? bytes);
}
