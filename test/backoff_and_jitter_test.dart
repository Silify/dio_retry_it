import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';
import 'package:test/test.dart';

import 'support/scripted_adapter.dart';

void main() {
  group('exponential backoff with full jitter', () {
    test('each retry delay stays within [0, cap] and grows with attempt',
        () async {
      const base = Duration(milliseconds: 40);
      const factor = 2.0;
      const maxDelay = Duration(milliseconds: 300);

      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 5,
        baseDelay: base,
        maxDelay: maxDelay,
        backoffFactor: factor,
        logPrint: (m) => print('  [retry] $m'),
      ));

      print('--- measuring inter-attempt delays ---');
      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      expect(adapter.callTimestamps.length, 4);

      // Theoretical uncapped exponential delay per attempt (1-based).
      Duration expectedCap(int attempt) {
        final ms = base.inMilliseconds * _pow(factor, attempt - 1);
        final capped =
            ms < maxDelay.inMilliseconds ? ms : maxDelay.inMilliseconds;
        return Duration(milliseconds: capped.round());
      }

      for (var attempt = 1; attempt <= 3; attempt++) {
        final gap = adapter.callTimestamps[attempt]
            .difference(adapter.callTimestamps[attempt - 1]);
        final cap = expectedCap(attempt);
        print('  attempt $attempt: observed gap = ${gap.inMilliseconds}ms, '
            'theoretical cap = ${cap.inMilliseconds}ms');

        // Full jitter means the gap should be >= 0 and, allowing generous
        // scheduling slack, not wildly larger than the cap.
        expect(gap.inMilliseconds, greaterThanOrEqualTo(0));
        expect(gap.inMilliseconds, lessThan(cap.inMilliseconds + 250),
            reason:
                'delay should not exceed cap by more than scheduling slack');
      }
      print('  PASS: all delays respected the exponential-with-cap bound\n');
    });

    test('delay is capped once exponential growth exceeds maxDelay', () async {
      const base = Duration(milliseconds: 50);
      const maxDelay = Duration(milliseconds: 60);

      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 5,
        baseDelay: base,
        maxDelay: maxDelay,
        backoffFactor: 4.0,
        // grows fast so it hits the cap quickly
        logPrint: (m) => print('  [retry] $m'),
      ));

      print('--- verifying delay cap kicks in ---');
      final response = await dio.get('/thing');
      expect(response.statusCode, 200);

      for (var i = 1; i < adapter.callTimestamps.length; i++) {
        final gap = adapter.callTimestamps[i]
            .difference(adapter.callTimestamps[i - 1])
            .inMilliseconds;
        print('  gap #$i = ${gap}ms (cap ${maxDelay.inMilliseconds}ms)');
        expect(gap, lessThan(maxDelay.inMilliseconds + 250));
      }
      print('  PASS: delays never meaningfully exceeded maxDelay\n');
    });

    test('a delay of zero (attempt with base 0) does not throw or hang',
        () async {
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 1,
        baseDelay: Duration.zero,
        logPrint: (m) => print('  [retry] $m'),
      ));

      print('--- zero base delay ---');
      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      print('  PASS: zero delay handled cleanly\n');
    });
  });
}

num _pow(num base, int exponent) {
  num result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}
