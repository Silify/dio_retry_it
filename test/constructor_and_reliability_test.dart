import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';
import 'package:test/test.dart';

import 'support/scripted_adapter.dart';

void main() {
  group('constructor validation', () {
    test('maxAttempts < 0 throws ArgumentError', () {
      print('--- maxAttempts negative ---');
      expect(
        () => RetryInterceptor(dio: Dio(), maxAttempts: -5),
        throwsArgumentError,
      );
      print('  PASS\n');
    });

    test('maxAttempts == 0 is allowed (means "never retry")', () {
      print('--- maxAttempts zero is valid ---');
      expect(
          () => RetryInterceptor(dio: Dio(), maxAttempts: 0), returnsNormally);
      print('  PASS\n');
    });

    test('backoffFactor < 1 throws ArgumentError', () {
      print('--- backoffFactor below 1 ---');
      expect(
        () => RetryInterceptor(dio: Dio(), backoffFactor: 0.5),
        throwsArgumentError,
      );
      print('  PASS\n');
    });

    test('backoffFactor == 1 is allowed (flat, non-exponential delay)', () {
      print('--- backoffFactor exactly 1 ---');
      expect(() => RetryInterceptor(dio: Dio(), backoffFactor: 1.0),
          returnsNormally);
      print('  PASS\n');
    });

    test('default construction uses documented defaults', () {
      print('--- defaults sanity check ---');
      final interceptor = RetryInterceptor(dio: Dio());
      expect(interceptor.maxAttempts, 3);
      expect(interceptor.baseDelay, const Duration(milliseconds: 500));
      expect(interceptor.maxDelay, const Duration(seconds: 10));
      expect(interceptor.backoffFactor, 2.0);
      print('  PASS: defaults match documentation\n');
    });
  });

  group('end-to-end reliability', () {
    test(
        'a flaky endpoint that fails twice then succeeds completes '
        'successfully with the expected number of calls', () async {
      print('--- flaky endpoint simulation ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.connectionError(),
        AdapterBehavior.badResponse(429),
        AdapterBehavior.success(body: {'result': 'ok'}),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 4,
        baseDelay: const Duration(milliseconds: 5),
        maxDelay: const Duration(milliseconds: 40),
        logPrint: (m) => print('  [retry] $m'),
      ));

      final response = await dio.get('/flaky');
      expect(response.statusCode, 200);
      expect(response.data['result'], 'ok');
      expect(adapter.callCount, 3);
      print('  PASS: recovered after a connection error + a 429\n');
    });

    test('a healthy endpoint (no failures) is called exactly once', () async {
      print('--- happy path, no retries needed ---');
      final adapter = ScriptedAdapter([AdapterBehavior.success()]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(dio: dio));

      final response = await dio.get('/healthy');
      expect(response.statusCode, 200);
      expect(adapter.callCount, 1);
      print('  PASS: no unnecessary retries on a healthy call\n');
    });

    test(
        'multiple concurrent requests each track their own attempt count '
        'independently', () async {
      print('--- concurrent requests do not interfere ---');
      final adapterA = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final adapterB = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dioA = Dio(BaseOptions(baseUrl: 'https://a.test'))
        ..httpClientAdapter = adapterA;
      final dioB = Dio(BaseOptions(baseUrl: 'https://b.test'))
        ..httpClientAdapter = adapterB;
      dioA.interceptors.add(RetryInterceptor(
          dio: dioA,
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 5)));
      dioB.interceptors.add(RetryInterceptor(
          dio: dioB,
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 5)));

      final results = await Future.wait([dioA.get('/x'), dioB.get('/y')]);

      expect(results[0].statusCode, 200);
      expect(results[1].statusCode, 200);
      expect(adapterA.callCount, 2);
      expect(adapterB.callCount, 3);
      print('  PASS: adapterA=${adapterA.callCount} calls, '
          'adapterB=${adapterB.callCount} calls, independent as expected\n');
    });
  });
}
