import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';

/// A function that evaluates whether a retry should be attempted.
///
/// Returns `true` if the request should be retried, `false` otherwise.
/// [attempt] is 1-based (first retry is attempt 1).
///
/// Example:
/// ```dart
/// final customEvaluator = (DioException error, int attempt) {
///   // Only retry network errors and 5xx status codes
///   if (error.type == DioExceptionType.connectionError) return true;
///   if (error.type == DioExceptionType.badResponse) {
///     final status = error.response?.statusCode ?? 0;
///     return status >= 500 && status < 600;
///   }
///   return false;
/// };
/// ```
typedef RetryEvaluator = FutureOr<bool> Function(
    DioException error, int attempt);

/// An interceptor that automatically retries failed requests using
/// exponential backoff with full jitter.
///
/// This interceptor provides a robust retry mechanism that:
/// - Retries failed requests automatically based on configurable rules
/// - Uses exponential backoff with full jitter to prevent thundering herd problems
/// - Supports custom retry evaluation logic
/// - Handles FormData cloning automatically
/// - Respects request cancellation
/// - Tracks retry attempts per request
///
/// ## Retry Strategy
///
/// The delay between retries follows a full jitter pattern:
/// 1. Calculate exponential delay: `baseDelay * backoffFactor^(attempt-1)`
/// 2. Cap at `maxDelay`
/// 3. Apply full jitter: `random(0, cappedDelay)`
///
/// ### Example:
/// With `baseDelay: 500ms`, `backoffFactor: 2.0`, `maxDelay: 10s`:
/// - Attempt 1: delay = `random(0, 500ms)`
/// - Attempt 2: delay = `random(0, 1000ms)`
/// - Attempt 3: delay = `random(0, 2000ms)`
/// - Attempt 4: delay = `random(0, 4000ms)`
/// - Attempt 5: delay = `random(0, 8000ms)`
/// - Attempt 6+: delay = `random(0, 10000ms)`
///
/// ## Default Retry Rules
///
/// By default, the interceptor retries:
/// - Connection errors (timeouts, network issues)
/// - Bad responses with status codes: 408, 429, 500, 502, 503, 504
/// - Does NOT retry: cancelled requests, format exceptions, client errors
///
/// ## Usage Examples
///
/// ### Basic Setup
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(RetryInterceptor(
///   dio: dio,
///   maxAttempts: 3,
/// ));
/// ```
///
/// ### Custom Retry Logic
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(RetryInterceptor(
///   dio: dio,
///   maxAttempts: 5,
///   baseDelay: Duration(seconds: 1),
///   maxDelay: Duration(seconds: 30),
///   retryEvaluator: (error, attempt) {
///     // Only retry specific error types
///     if (error.type == DioExceptionType.connectionTimeout) return true;
///     if (error.type == DioExceptionType.receiveTimeout) return true;
///     return error.response?.statusCode == 503;
///   },
/// ));
/// ```
///
/// ### Disable Retry for Specific Requests
/// ```dart
/// final response = await dio.get(
///   'https://api.example.com/data',
///   options: Options(extra: {'disableRetry': true}),
/// );
/// ```
///
/// ### Logging
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(RetryInterceptor(
///   dio: dio,
///   logPrint: (message) => print('Retry: $message'),
/// ));
/// ```
class RetryInterceptor extends Interceptor {
  /// Creates a new RetryInterceptor with the specified configuration.
  ///
  /// Parameters:
  /// - [dio]: The Dio instance used to re-fetch retried requests (required)
  /// - [logPrint]: Optional logging hook, called once per retry attempt
  /// - [maxAttempts]: Maximum number of retry attempts (default: 3)
  /// - [baseDelay]: Delay before the first retry (default: 500ms)
  /// - [maxDelay]: Upper bound on the computed delay (default: 10s)
  /// - [backoffFactor]: Multiplier applied to the delay after each attempt (default: 2.0)
  /// - [retryEvaluator]: Custom function to determine if retry should happen
  ///
  /// Throws [ArgumentError] if [maxAttempts] is negative or [backoffFactor] < 1
  RetryInterceptor({
    required this.dio,
    this.logPrint,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 10),
    this.backoffFactor = 2.0,
    RetryEvaluator? retryEvaluator,
  }) : _shouldRetry = retryEvaluator ?? _defaultEvaluator {
    if (maxAttempts < 0) {
      throw ArgumentError('[maxAttempts] cannot be negative', 'maxAttempts');
    }
    if (backoffFactor < 1) {
      throw ArgumentError('[backoffFactor] must be >= 1', 'backoffFactor');
    }
  }

  /// The Dio instance used to re-fetch retried requests.
  ///
  /// This should typically be the same Dio instance that the interceptor
  /// is attached to, but can be a different instance if needed.
  final Dio dio;

  /// Optional logging hook, called once per retry attempt.
  ///
  /// The callback receives a descriptive message about each retry attempt,
  /// including the attempt number, delay, and error details.
  final void Function(String message)? logPrint;

  /// Maximum number of retry attempts (not counting the original request).
  ///
  /// For example, if `maxAttempts = 3`, the interceptor will try the request
  /// up to 4 times total (1 original + 3 retries).
  final int maxAttempts;

  /// Delay before the first retry, before backoff is applied.
  ///
  /// This serves as the base for the exponential backoff calculation.
  /// The actual delay for the first retry will be a random value between 0
  /// and [baseDelay] (full jitter).
  final Duration baseDelay;

  /// Upper bound on the computed delay, before jitter is applied.
  ///
  /// Prevents the delay from growing indefinitely. Once the computed
  /// exponential delay exceeds this value, it's capped at [maxDelay].
  final Duration maxDelay;

  /// Multiplier applied to the delay after each attempt.
  ///
  /// Must be >= 1.0. Common values:
  /// - `2.0` (default): Classic exponential backoff
  /// - `1.5`: Slower growth, more retries in shorter time
  /// - `3.0`: Faster growth, fewer retries
  final double backoffFactor;

  /// Decides whether a given error on a given attempt should be retried.
  ///
  /// This is the core logic that determines if a retry should be attempted.
  /// The default implementation retries timeout errors, connection errors,
  /// and specific status codes (408, 429, 500, 502, 503, 504).
  final RetryEvaluator _shouldRetry;

  /// Random number generator used for jitter calculation.
  static final _random = Random();

  /// Default retry evaluator implementation.
  ///
  /// Retries:
  /// - All errors except: cancelled requests and format exceptions
  /// - For [DioExceptionType.badResponse], only retries status codes:
  ///   - 408: Request Timeout
  ///   - 429: Too Many Requests
  ///   - 500: Internal Server Error
  ///   - 502: Bad Gateway
  ///   - 503: Service Unavailable
  ///   - 504: Gateway Timeout
  static bool _defaultEvaluator(DioException error, int attempt) {
    if (error.type == DioExceptionType.cancel) return false;
    if (error.error is FormatException) return false;
    if (error.type == DioExceptionType.badResponse) {
      final statusCode = error.response?.statusCode;
      return statusCode != null &&
          defaultRetryableStatuses.contains(statusCode);
    }
    return true; // timeouts, connection errors, etc.
  }

  @override
  Future<dynamic> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    // Skip retry if explicitly disabled
    if (options.disableRetry) return super.onError(err, handler);

    final attempt = options._attempt + 1;
    final canRetry = attempt <= maxAttempts;

    // Check if we should retry this error
    bool willRetry;
    try {
      willRetry = canRetry && await _shouldRetry(err, attempt);
    } catch (e) {
      logPrint?.call('Retry evaluator threw, aborting retry: $e');
      return super.onError(err, handler);
    }

    if (!willRetry) return super.onError(err, handler);

    // Update attempt counter and calculate delay
    options._attempt = attempt;
    final delay = _jitteredDelay(attempt);

    // Log the retry attempt
    logPrint?.call(
      '[${options.path}] retrying (attempt $attempt/$maxAttempts, '
      'delay ${delay.inMilliseconds}ms, error: ${err.error ?? err})',
    );

    // FormData can only be consumed once, so it must be cloned before reuse.
    final retryOptions = options.data is FormData
        ? options.copyWith(data: (options.data as FormData).clone())
        : options;

    // Wait for the computed delay
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    // Re-check after the delay: cancellation may have happened while waiting.
    if (options.cancelToken?.isCancelled ?? false) {
      logPrint?.call('[${options.path}] cancelled during retry delay');
      return super.onError(err, handler);
    }

    // Execute the retry
    try {
      final response = await dio.fetch<void>(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      super.onError(e, handler);
    }
  }

  /// Computes the exponential backoff delay for [attempt], then applies
  /// full jitter: a random duration in `[0, delay]`.
  ///
  /// Full jitter prevents many clients from retrying in lockstep against
  /// a recovering server, which matters far more for real-world reliability
  /// than a fixed delay schedule.
  ///
  /// The algorithm:
  /// 1. Calculate: `baseDelay * backoffFactor^(attempt-1)`
  /// 2. Cap at `maxDelay`
  /// 3. Return random value between 0 and the capped delay
  Duration _jitteredDelay(int attempt) {
    final exponential = baseDelay * pow(backoffFactor, attempt - 1);
    final capped = exponential < maxDelay ? exponential : maxDelay;
    final jitteredMs = (_random.nextDouble() * capped.inMilliseconds).round();
    return Duration(milliseconds: jitteredMs);
  }
}

// Internal keys for storing retry metadata in request options
const _kDisableRetryKey = 'ro_disable_retry';
const _kAttemptKey = 'ro_attempt';

/// Retry-related properties on [RequestOptions].
///
/// These extensions provide convenient access to retry configuration
/// at the individual request level.
extension RequestOptionsX on RequestOptions {
  /// Current retry attempt number (0 = original request, not yet retried).
  ///
  /// This value is automatically managed by the [RetryInterceptor].
  /// It increments with each retry attempt.
  int get attempt => _attempt;

  /// Whether retry is disabled for this request.
  ///
  /// When set to `true`, the [RetryInterceptor] will skip retry logic
  /// for this request, even if the interceptor is active.
  ///
  /// Example:
  /// ```dart
  /// final options = RequestOptions(path: '/api/data');
  /// options.disableRetry = true;
  /// final response = await dio.fetch(options);
  /// ```
  bool get disableRetry => (extra[_kDisableRetryKey] as bool?) ?? false;
  set disableRetry(bool value) => extra[_kDisableRetryKey] = value;

  /// Internal attempt counter stored in [extra].
  ///
  /// This is managed automatically by the interceptor and should not
  /// be modified directly.
  int get _attempt => (extra[_kAttemptKey] as int?) ?? 0;
  set _attempt(int value) => extra[_kAttemptKey] = value;
}

/// Retry-related properties on [Options].
///
/// These extensions provide convenient access to retry configuration
/// at the request level when using [Dio]'s [Options] class.
extension OptionsX on Options {
  /// Whether retry is disabled for this request.
  ///
  /// When set to `true`, the [RetryInterceptor] will skip retry logic
  /// for this request, even if the interceptor is active.
  ///
  /// Example:
  /// ```dart
  /// final response = await dio.get(
  ///   'https://api.example.com/data',
  ///   options: Options(extra: {'disableRetry': true}),
  /// );
  /// ```
  bool get disableRetry => (extra?[_kDisableRetryKey] as bool?) ?? false;
  set disableRetry(bool value) {
    extra = Map.of(extra ?? <String, dynamic>{});
    extra![_kDisableRetryKey] = value;
  }
}
