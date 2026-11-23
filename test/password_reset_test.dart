import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:auto_task_scheduler/providers/auth_provider.dart';
import 'package:auto_task_scheduler/services/api_client.dart';
import 'package:auto_task_scheduler/screens/auth_screen.dart';
import 'package:auto_task_scheduler/theme/app_theme.dart';

void main() {
  testWidgets(
    'wrong password stays on sign-in and password reset validates, verifies and returns to login',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clears = 0, resets = 0;
      final api = ApiClient(
        base: Uri.parse('https://test.invalid/api/'),
        client: MockClient((request) async {
          var status = 200;
          Map<String, dynamic> result = {};
          if (request.url.path.endsWith('/auth/me')) {
            status = 401;
            result = {'error': 'Please sign in.'};
          } else if (request.url.path.endsWith('/auth/request-code')) {
            final body = jsonDecode(request.body);
            if (body['purpose'] == 'login') {
              status = 401;
              result = {'error': 'Email or password is incorrect.'};
            } else {
              expect(body['purpose'], 'reset');
              expect(body.containsKey('password'), isFalse);
              result = {'challengeId': 'reset-challenge', 'retryAfter': 60};
            }
          } else if (request.url.path.endsWith('/auth/reset-password')) {
            resets++;
            final body = jsonDecode(request.body);
            expect(body['password'], 'My new passphrase 456');
            if (body['code'] != '123456') {
              status = 400;
              result = {'error': 'This code is incorrect or expired.'};
            } else {
              result = {
                'ok': true,
                'message': 'Password updated. Sign in with your new password.',
              };
            }
          }
          return http.Response(
            jsonEncode(result),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final auth = AuthProvider(
        client: api,
        readToken: () async => null,
        writeToken: (_) async {},
        clearToken: () async {
          clears++;
        },
      );
      await auth.ready;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'owner@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'Wrong password',
      );
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Sign in'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(clears, 1);
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send reset code'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '000000');
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'My new passphrase 456',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'Different passphrase',
      );
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Reset password'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset password'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(resets, 0);
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'My new passphrase 456',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset password'));
      await tester.pumpAndSettle();
      expect(find.text('This code is incorrect or expired.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('auth-code')), '123456');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset password'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(auth.user, isNull);
      expect(auth.challengeId, isNull);
      expect(resets, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );
}
