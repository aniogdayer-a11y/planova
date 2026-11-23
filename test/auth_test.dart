import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auto_task_scheduler/main.dart';
import 'package:auto_task_scheduler/providers/auth_provider.dart';
import 'package:auto_task_scheduler/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'create account verifies an email OTP before opening the planner',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? persistedToken;
      var verified = false;
      final api = ApiClient(
        base: Uri.parse('https://test.invalid/api/'),
        client: MockClient((request) async {
          Map<String, dynamic> body = {};
          var status = 200;
          switch (request.url.path) {
            case '/api/auth/me':
              status = 401;
              body = {'error': 'Please sign in.'};
            case '/api/auth/request-code':
              expect(jsonDecode(request.body)['purpose'], 'register');
              body = {'challengeId': 'challenge', 'retryAfter': 60};
            case '/api/auth/verify':
              if (jsonDecode(request.body)['code'] != '123456') {
                status = 400;
                body = {'error': 'This code is incorrect or expired.'};
              } else {
                verified = true;
                body = {
                  'user': {
                    'id': 'account-1',
                    'email': 'person@example.test',
                    'name': 'Test User',
                  },
                  'token': 'opaque-session',
                };
              }
            case '/api/profile':
              body = {
                'profile': {
                  'id': 1,
                  'name': 'Test User',
                  'workspace': 'Personal',
                  'tagline': '',
                  'avatar_url': '',
                  'streak_count': 0,
                  'last_active_date': '',
                },
              };
            case '/api/settings':
              body = {'settings': {}};
            case '/api/activity':
              body = {'weekly': [], 'streak': 0};
            default:
              body = {'plan': null, 'revision': 0};
          }
          return http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final auth = AuthProvider(
        client: api,
        readToken: () async => null,
        writeToken: (token) async {
          persistedToken = token;
        },
        clearToken: () async {
          persistedToken = null;
        },
      );
      await auth.ready;
      await tester.pumpWidget(AutoTaskSchedulerApp(authProvider: auth));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-name')),
        'Test User',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'person@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'Example passphrase 123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'Example passphrase 123',
      );
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Check your email'), findsOneWidget);
      expect(verified, isFalse);
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '000000');
      await tester.tap(find.text('Verify and sign in'));
      await tester.pumpAndSettle();
      expect(find.text('This code is incorrect or expired.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.text('Verify and sign in'));
      await tester.pumpAndSettle();
      expect(verified, isTrue);
      expect(persistedToken, 'opaque-session');
      expect(find.text('Hi, Test User.'), findsOneWidget);
      await tester.ensureVisible(find.text('Plan this day'));
      await tester.tap(find.text('Plan this day'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Plan your day'), findsOneWidget);
      expect(find.text('Generate plan'), findsOneWidget);
      expect(find.text('Use Gemini'), findsNothing);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Plan your day'), findsNothing);
      expect(persistedToken, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('expired sessions clear persisted tokens', () async {
    var cleared = false;
    final api = ApiClient(
      base: Uri.parse('https://test.invalid/api/'),
      client: MockClient(
        (_) async => http.Response(
          '{"error":"Please sign in."}',
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final auth = AuthProvider(
      client: api,
      readToken: () async => 'expired',
      writeToken: (_) async {},
      clearToken: () async {
        cleared = true;
      },
    );
    await auth.ready;
    expect(auth.user, isNull);
    expect(api.token, isNull);
    expect(cleared, isTrue);
    auth.dispose();
  });
}
