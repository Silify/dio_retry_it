import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';
import 'package:test/test.dart';

import 'support/scripted_adapter.dart';

Dio _newDio(ScriptedAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;

void main() {
  group('FormData cloning', () {
    test(
        'a FormData request survives a retry without a "stream already '
        'consumed" style failure', () async {
      print('--- FormData retry ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
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

      final formData = FormData.fromMap({
        'name': 'Mohammad',
        'file': MultipartFile.fromString('hello world', filename: 'a.txt'),
      });

      final response = await dio.post('/upload', data: formData);

      expect(response.statusCode, 200);
      expect(adapter.callCount, 3, reason: 'original + 2 retries');
      print('  PASS: FormData request completed after 2 retries\n');
    });

    test('non-FormData bodies are reused as-is (no cloning needed)', () async {
      print('--- plain JSON body retry ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
      ));

      final response = await dio.post('/upload', data: {'name': 'Mohammad'});
      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
      print('  PASS: JSON body retried without issue\n');
    });
  });

  group('RequestOptionsX attempt tracking', () {
    test('attempt starts at 0 and increments once per retry', () async {
      print('--- attempt counter ---');
      final observedAttempts = <int>[];
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);

      // A second interceptor placed after RetryInterceptor lets us peek at
      // RequestOptions.attempt on each outgoing call.
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 5,
        baseDelay: const Duration(milliseconds: 5),
      ));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          observedAttempts.add(options.attempt);
          print('  outgoing request, options.attempt = ${options.attempt}');
          handler.next(options);
        },
      ));

      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      expect(observedAttempts, [0, 1, 2]);
      print('  PASS: attempt sequence was $observedAttempts\n');
    });

    test('a fresh RequestOptions defaults attempt to 0', () {
      print('--- default attempt value ---');
      final options = RequestOptions(path: '/x');
      expect(options.attempt, 0);
      print('  PASS: default attempt is 0\n');
    });
  });

  group('logPrint hook', () {
    test('logPrint fires once per retry with attempt/delay/error info',
        () async {
      print('--- logPrint hook ---');
      final logs = <String>[];
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        logPrint: (m) {
          logs.add(m);
          print('  captured log: $m');
        },
      ));

      await dio.get('/thing');

      expect(logs.length, 2, reason: 'two retries happened');
      for (final line in logs) {
        expect(line, contains('attempt'));
      }
      print('  PASS: logPrint called exactly once per retry\n');
    });

    test('no logPrint provided does not crash the interceptor', () async {
      print('--- no logPrint configured ---');
      final adapter = ScriptedAdapter([
        AdapterBehavior.badResponse(503),
        AdapterBehavior.success(),
      ]);
      final dio = _newDio(adapter);
      dio.interceptors.add(RetryInterceptor(
        dio: dio,
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 5),
        // logPrint intentionally omitted
      ));

      final response = await dio.get('/thing');
      expect(response.statusCode, 200);
      print('  PASS: worked fine without a logger\n');
    });
  });
}
