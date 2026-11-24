import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:auto_task_scheduler/providers/planner_provider.dart';
import 'package:auto_task_scheduler/screens/suggestions_screen.dart';
import 'package:auto_task_scheduler/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseService db;

  setUp(() async {
    db = await DatabaseService.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('Feedback CRUD and likes persistence in database service', () async {
    final initial = await db.getFeedback();
    expect(initial.length, 3);
    expect(initial.first.likesCount, 0);
    expect(initial.first.isLikedByMe, isFalse);

    // Add feedback
    final created = await db.addFeedback('Drink water between tasks', visibility: 'public');
    expect(created.content, 'Drink water between tasks');
    expect(created.isMine, isTrue);

    // Like feedback
    final likeResult = await db.toggleFeedbackLike(created.id);
    expect(likeResult['is_liked_by_me'], isTrue);
    expect(likeResult['likes_count'], 1);

    // Unlike feedback
    final unlikeResult = await db.toggleFeedbackLike(created.id);
    expect(unlikeResult['is_liked_by_me'], isFalse);
    expect(unlikeResult['likes_count'], 0);

    // Like again
    await db.toggleFeedbackLike(created.id);

    // Update feedback
    final updated = await db.updateFeedback(created.id, 'Stay hydrated all day');
    expect(updated.content, 'Stay hydrated all day');
    expect(updated.likesCount, 1);

    // Delete feedback
    await db.deleteFeedback(created.id);
    final remaining = await db.getFeedback();
    expect(remaining.any((f) => f.id == created.id), isFalse);
  });

  testWidgets('Suggestions screen renders comment feed, submits, and likes', (tester) async {
    late PlannerProvider planner;
    await tester.runAsync(() async {
      planner = PlannerProvider(database: db);
      await planner.ready;
      await planner.loadFeedback();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: planner,
        child: const MaterialApp(
          home: Scaffold(body: SuggestionsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial suggestions rendered like comments
    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.text('Start with the tasks you can realistically finish today.'), findsOneWidget);

    // Verify like button
    final firstId = planner.feedbackList.first.id;
    final likeBtn = find.byKey(ValueKey('like-$firstId'));
    expect(likeBtn, findsOneWidget);

    // Tap like button
    await tester.runAsync(() async {
      await tester.tap(likeBtn);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(planner.feedbackList.first.isLikedByMe, isTrue);
    expect(planner.feedbackList.first.likesCount, 1);

    // Post new suggestion via comment input
    final input = find.byType(TextField);
    await tester.enterText(input, 'Take 5 deep breaths');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('submit-suggestion-button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Take 5 deep breaths'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    planner.dispose();
  });
}
