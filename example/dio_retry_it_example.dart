import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';

Future<void> main() async {
  // Create Dio instance
  final dio = Dio();

  // Add the retry interceptor with exponential backoff and full jitter
  dio.interceptors.add(
    RetryInterceptor(
      dio: dio,
      maxAttempts: 4,
      // Retry up to 4 times (total 5 attempts including original)
      baseDelay: const Duration(milliseconds: 500),
      // Start with 500ms delay
      maxDelay: const Duration(seconds: 10),
      // Cap at 10 seconds
      backoffFactor: 2.0,
      // Double the delay each attempt
      logPrint: print, // Optional: log retry attempts
    ),
  );

  try {
    // This request will be automatically retried with exponential backoff
    // Attempt 1: 0-500ms delay
    // Attempt 2: 0-1,000ms delay
    // Attempt 3: 0-2,000ms delay
    // Attempt 4: 0-4,000ms delay
    print('Sending request to https://mock.codes/500...');
    await dio.get('https://mock.codes/500');
  } catch (e) {
    print('Request failed after all retry attempts: $e');
  }
}
