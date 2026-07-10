import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';
import 'package:test/test.dart';

import 'support/scripted_adapter.dart';

Dio _dioWith(ScriptedAdapter adapter, {int maxAttempts = 3}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter;
  dio.interceptors.add(RetryInterceptor(
    dio: dio,
    maxAttempts: maxAttempts,
    baseDelay: const Duration(milliseconds: 5),
    maxDelay: const Duration(milliseconds: 20),
    logPrint: (m) => print('  [retry] $m'),
  ));
  return dio;
}

void main() {
  group('default evaluator - retryable status codes', () {
    for (final code in [408, 429, 500, 502, 503, 504]) {
      test('retries on HTTP $code then succeeds', () async {
        print('--- retryable status $code ---');
        final adapter = ScriptedAdapter([
          AdapterBehavior.badResponse(code),
          AdapterBehavior.success(),
        ]);
        final dio = _dioWith(adapter);

        final response = await dio.get('/thing');

        expect(response.statusCode, 200);
        expect(adapter.callCount, 2, reason: 'original + 1 retry');
        print('  PASS: $code triggered exactly one retry\n');
      });
    }
  });

  group('default evaluator - non-retryable status codes', () {
    for (final code in [400, 401, 403, 404, 422]) {
      test('does NOT retry on HTTP $code', () async {
        print('--- non-retryable status $code ---');
        final adapter = ScriptedAdapter([AdapterBehavior.badResponse(code)]);
        final dio = _dioWith(adapter);

        await expectLater(
          dio.get('/thing'),
          throwsA(isA<DioException>()),
        );

        expect(adapter.callCount, 1, reason: 'no retry should have happened');
        print('  PASS: $code was not retried\n');
      });
    }
  });

  group('default evaluator - error types', () {
    test('retries connection errors (timeouts / network issues)', () async {
      print('--- connection error ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.connectionError(),
        AdapterBehavior.success(),
      ]);
      final dio = _dioWith(adapter);

      final response = await dio.get('/thing');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
      print('  PASS: connection error was retried\n');
    });

    test('does NOT retry cancelled requests', () async {
      print('--- cancelled request ---');
      final adapter = ScriptedAdapter([AdapterBehavior.cancel()]);
      final dio = _dioWith(adapter);

      await expectLater(dio.get('/thing'), throwsA(isA<DioException>()));

      expect(adapter.callCount, 1);
      print('  PASS: cancellation was not retried\n');
    });

    test('does NOT retry FormatException errors', () async {
      print('--- format exception ---');
      final adapter = ScriptedAdapter([AdapterBehavior.formatError()]);
      final dio = _dioWith(adapter);

      await expectLater(dio.get('/thing'), throwsA(isA<DioException>()));

      expect(adapter.callCount, 1);
      print('  PASS: FormatException was not retried\n');
    });
  });

  group('default evaluator - exhausting retries', () {
    test('gives up after maxAttempts and surfaces the last error', () async {
      print('--- exhausting retries ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503), // still failing after max retries
      ]);
      final dio = _dioWith(adapter, maxAttempts: 3);

      await expectLater(
        dio.get('/thing'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      // 1 original attempt + 3 retries = 4 calls total.
      expect(adapter.callCount, 4);
      print('  PASS: stopped after original + 3 retries (4 calls total)\n');
    });
  });
}
