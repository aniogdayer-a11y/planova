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
    expect(initial, isEmpty);

    // Add feedback
    final created = await db.addFeedback(
      'Drink water between tasks',
      category: 'Feature Suggestion',
      recommendation: 'maybe',
      visibility: 'public',
    );
    expect(created.content, 'Drink water between tasks');
    expect(created.isMine, isTrue);
    expect(created.category, 'Feature Suggestion');
    expect(created.recommendation, 'maybe');

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
    final updated = await db.updateFeedback(
      created.id,
      'Stay hydrated all day',
      category: 'Bug Report',
      recommendation: 'no',
    );
    expect(updated.content, 'Stay hydrated all day');
    expect(updated.category, 'Bug Report');
    expect(updated.recommendation, 'no');
    expect(updated.likesCount, 1);

    // Delete feedback
    await db.deleteFeedback(created.id);
    final remaining = await db.getFeedback();
    expect(remaining.any((f) => f.id == created.id), isFalse);

    final private = await db.addFeedback(
      'Only I should see this.',
      visibility: 'private',
    );
    expect(private.visibility, 'private');
    expect((await db.getFeedback()).single.id, private.id);
    await db.deleteFeedback(private.id);
  });

  testWidgets('Feedback screen submits public feedback and supports likes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late PlannerProvider planner;
    await tester.runAsync(() async {
      planner = PlannerProvider(database: db);
      await planner.ready;
      await planner.loadFeedback();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: planner,
        child: const MaterialApp(home: Scaffold(body: SuggestionsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Feedback'), findsOneWidget);
    expect(
      find.text('No community feedback yet. Be the first to share.'),
      findsOneWidget,
    );

    final input = find.byType(TextField).first;
    await tester.enterText(input, 'Take 5 deep breaths');
    await tester.tap(find.byType(Checkbox).first);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('submit-suggestion-button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Take 5 deep breaths'), findsOneWidget);
    expect(planner.feedbackList.first.visibility, 'public');

    final firstId = planner.feedbackList.first.id;
    final likeBtn = find.byKey(ValueKey('like-$firstId'));
    expect(likeBtn, findsOneWidget);
    await tester.ensureVisible(likeBtn);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(likeBtn).onPressed, isNotNull);
    await tester.tap(likeBtn);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(planner.feedbackList.first.isLikedByMe, isTrue);
    expect(planner.feedbackList.first.likesCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    planner.dispose();
  });
}
