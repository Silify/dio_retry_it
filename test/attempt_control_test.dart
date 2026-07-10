import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';
import 'package:test/test.dart';

import 'support/scripted_adapter.dart';

Dio _newDio(ScriptedAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;

void main() {
  group('maxAttempts', () {
    test('maxAttempts = 0 means no retries at all', () async {
      print('--- maxAttempts = 0 ---');
      final adapter = ScriptedAdapter([AdapterBehavior.badResponse(503)]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 0,
        logPrint: (m) => print('  [retry] $m'),
      ));

      await expectLater(dio.get('/thing'), throwsA(isA<DioException>()));
      expect(adapter.callCount, 1);
      print('  PASS: exactly one call, no retries\n');
    });

    test('negative maxAttempts throws ArgumentError at construction', () {
      print('--- negative maxAttempts ---');
      final dio = Dio();
      expect(
        () => RetryInterceptor(dio: dio, maxAttempts: -1),
        throwsArgumentError,
      );
      print('  PASS: ArgumentError raised\n');
    });
  });

  group('disableRetry', () {
    test('per-request Options(extra: {disableRetry: true}) skips retry',
        () async {
      print('--- disableRetry via Options.extra ---');
      final adapter = ScriptedAdapter([AdapterBehavior.badResponse(503)]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        logPrint: (m) => print('  [retry] $m'),
      ));

      await expectLater(
        dio.get('/thing', options: Options(extra: {'disableRetry': true})),
        throwsA(isA<DioException>()),
      );

      expect(adapter.callCount, 1, reason: 'retry should have been skipped');
      print('  PASS: request with disableRetry was not retried\n');
    });

    test('OptionsX.disableRetry setter round-trips correctly', () {
      print('--- OptionsX.disableRetry setter/getter ---');
      final options = Options();
      expect(options.disableRetry, isFalse);
      options.disableRetry = true;
      expect(options.disableRetry, isTrue);
      print('  PASS: disableRetry flag stored and read back\n');
    });

    test('requests without disableRetry still retry normally', () async {
      print('--- default (retry enabled) request ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        logPrint: (m) => print('  [retry] $m'),
      ));

      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
      print('  PASS: retried as expected\n');
    });
  });

  group('cancellation', () {
    test('cancelling the request during the retry delay stops the retry',
        () async {
      print('--- cancel during retry delay ---');
      final adapter = ScriptedAdapter([AdapterBehavior.badResponse(503)]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 200),
        logPrint: (m) => print('  [retry] $m'),
      ));

      final cancelToken = CancelToken();
      final future = dio.get('/thing', cancelToken: cancelToken);

      // Cancel while the interceptor is still sleeping before the retry.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancelToken.cancel('user navigated away');

      await expectLater(future, throwsA(isA<DioException>()));
      // Only the original call should have gone out; the retry should
      // have been aborted once cancellation was detected post-delay.
      expect(adapter.callCount, 1);
      print('  PASS: retry aborted after cancellation\n');
    });
  });

  group('custom retryEvaluator', () {
    test('custom evaluator can restrict retries to specific status codes',
        () async {
      print('--- custom evaluator: only retry 503 ---');
      final adapter = ScriptedAdapter([AdapterBehavior.badResponse(500)]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        retryEvaluator: (error, attempt) {
          final code = error.response?.statusCode;
          print('  evaluator called: status=$code attempt=$attempt');
          return code == 503;
        },
      ));

      await expectLater(dio.get('/thing'), throwsA(isA<DioException>()));
      expect(adapter.callCount, 1, reason: '500 should not match custom rule');
      print('  PASS: custom evaluator correctly rejected 500\n');
    });

    test('custom evaluator receives correct 1-based attempt numbers', () async {
      print('--- custom evaluator attempt numbering ---');
      final seenAttempts = <int>[];
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 5,
        baseDelay: const Duration(milliseconds: 5),
        retryEvaluator: (error, attempt) {
          seenAttempts.add(attempt);
          return true;
        },
      ));

      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      expect(seenAttempts, [1, 2]);
      print('  PASS: attempts observed in order: $seenAttempts\n');
    });

    test('an evaluator that throws aborts the retry instead of crashing',
        () async {
      print('--- evaluator throws ---');
      final adapter = ScriptedAdapter([AdapterBehavior.badResponse(503)]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        retryEvaluator: (error, attempt) {
          throw StateError('boom - evaluator misconfigured');
        },
        logPrint: (m) => print('  [retry] $m'),
      ));

      await expectLater(dio.get('/thing'), throwsA(isA<DioException>()));
      expect(adapter.callCount, 1);
      print('  PASS: evaluator exception surfaced original error, no crash\n');
    });

    test('an async (Future<bool>) evaluator is awaited correctly', () async {
      print('--- async evaluator ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        retryEvaluator: (error, attempt) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return true;
        },
      ));

      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
      print('  PASS: async evaluator awaited before retrying\n');
    });
  });
}
