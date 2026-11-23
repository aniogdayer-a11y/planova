import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_task_scheduler/models/task_model.dart';
import 'package:auto_task_scheduler/services/gemini_service.dart';

GeminiHttpResponse responseFor(Object tasks, {String finish = 'STOP'}) =>
    GeminiHttpResponse(
      200,
      jsonEncode({
        'candidates': [
          {
            'finishReason': finish,
            'content': {
              'parts': [
                {
                  'text': jsonEncode({'tasks': tasks}),
                },
              ],
            },
          },
        ],
      }),
    );

Future<List<TaskModel>> generate(
  GeminiService service, {
  String key = 'test-key',
}) => service.generate(
  apiKey: key,
  model: GeminiService.defaultModel,
  tasks: [
    TaskModel(id: 7, title: 'Review notes', durationMinutes: 0),
    TaskModel(id: 8, title: 'Email', durationMinutes: 15),
  ],
  date: DateTime(2026, 11, 23),
  startTime: '9:00 AM',
  breakCount: 1,
  breakMinutes: 5,
);

void main() {
  test(
    'request authenticates in a header, requests JSON and preserves task identity',
    () async {
      final service = GeminiService(
        transport: (uri, headers, body) async {
          expect(uri.host, 'generativelanguage.googleapis.com');
          expect(
            uri.path,
            '/v1beta/models/${GeminiService.defaultModel}:generateContent',
          );
          expect(uri.query, isEmpty);
          expect(headers['x-goog-api-key'], 'test-key');
          final payload = jsonDecode(body);
          expect(
            payload['generationConfig']['responseMimeType'],
            'application/json',
          );
          expect(payload['generationConfig']['responseJsonSchema'], isA<Map>());
          return responseFor([
            {'input_index': 1, 'duration_minutes': 15},
            {'input_index': 0, 'duration_minutes': 40},
          ]);
        },
      );
      final tasks = await generate(service);
      expect(tasks.map((t) => t.title), ['Email', 'Review notes']);
      expect(tasks.map((t) => t.id), [8, 7]);
      expect(tasks.map((t) => t.durationMinutes), [15, 40]);
    },
  );

  test('project server is used automatically without a client key', () async {
    final endpoint = Uri.parse('https://planner.example/api/gemini');
    final service = GeminiService(
      proxyEndpoint: endpoint,
      transport: (uri, headers, body) async {
        expect(uri, endpoint);
        expect(headers.containsKey('x-goog-api-key'), isFalse);
        return responseFor([
          {'input_index': 0, 'duration_minutes': 25},
          {'input_index': 1, 'duration_minutes': 15},
        ]);
      },
    );
    final tasks = await generate(service, key: '');
    expect(tasks.length, 2);
  });

  for (final status in [400, 401, 403, 404, 429, 500]) {
    test(
      'HTTP $status returns a friendly error without raw API data',
      () async {
        final service = GeminiService(
          transport: (_, __, ___) async =>
              GeminiHttpResponse(status, 'private-error-content'),
        );
        await expectLater(
          generate(service),
          throwsA(
            isA<GeminiException>().having(
              (e) => e.message,
              'message',
              isNot(contains('private-error-content')),
            ),
          ),
        );
      },
    );
  }

  test('timeout is recoverable', () async {
    final service = GeminiService(
      transport: (_, __, ___) async => throw TimeoutException('test'),
    );
    await expectLater(
      generate(service),
      throwsA(
        isA<GeminiException>().having(
          (e) => e.message,
          'message',
          contains('too long'),
        ),
      ),
    );
  });

  for (final invalid in [
    [
      {'input_index': 0, 'duration_minutes': 20},
    ],
    [
      {'input_index': 0, 'duration_minutes': 20},
      {'input_index': 0, 'duration_minutes': 20},
    ],
    [
      {'input_index': 0, 'duration_minutes': 0},
      {'input_index': 1, 'duration_minutes': 15},
    ],
    [
      {'input_index': 0, 'duration_minutes': 20},
      {'input_index': 1, 'duration_minutes': 40},
    ],
    [
      {'input_index': 0, 'duration_minutes': 20},
      {'input_index': 99, 'duration_minutes': 15},
    ],
  ]) {
    test('invalid model tasks are rejected: $invalid', () async {
      final service = GeminiService(
        transport: (_, __, ___) async => responseFor(invalid),
      );
      await expectLater(generate(service), throwsA(isA<GeminiException>()));
    });
  }

  test('blocked and truncated responses cannot become plans', () async {
    for (final response in [
      const GeminiHttpResponse(
        200,
        '{"promptFeedback":{"blockReason":"SAFETY"}}',
      ),
      responseFor([], finish: 'MAX_TOKENS'),
      const GeminiHttpResponse(200, 'not-json'),
    ]) {
      final service = GeminiService(transport: (_, __, ___) async => response);
      await expectLater(generate(service), throwsA(isA<GeminiException>()));
    }
  });
}
