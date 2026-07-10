import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_retry_it/dio_retry_it.dart';

/// A function that evaluates whether a retry should be attempted.
///
/// Returns `true` if the request should be retried, `false` otherwise.
/// [attempt] is 1-based (first retry is attempt 1).
typedef RetryEvaluator = FutureOr<bool> Function(
    DioException error, int attempt);

/// An interceptor that automatically retries failed requests using
/// exponential backoff with full jitter.
///
/// Delay formula: `min(baseDelay * backoffFactor^(attempt - 1), maxDelay)`,
/// then a random value in `[0, delay]` is used as the actual wait. Jitter
/// prevents many clients from retrying in lockstep against a recovering
/// server, which matters far more for real-world reliability than a fixed
/// delay schedule.
class RetryInterceptor extends Interceptor {
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
  final Dio dio;

  /// Optional logging hook, called once per retry attempt.
  final void Function(String message)? logPrint;

  /// Maximum number of retry attempts (not counting the original request).
  final int maxAttempts;

  /// Delay before the first retry, before backoff is applied.
  final Duration baseDelay;

  /// Upper bound on the computed delay, before jitter is applied.
  final Duration maxDelay;

  /// Multiplier applied to the delay after each attempt.
  final double backoffFactor;

  /// Decides whether a given error on a given attempt should be retried.
  final RetryEvaluator _shouldRetry;

  static final _random = Random();

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

    if (options.disableRetry) return super.onError(err, handler);

    final attempt = options._attempt + 1;
    final canRetry = attempt <= maxAttempts;

    bool willRetry;
    try {
      willRetry = canRetry && await _shouldRetry(err, attempt);
    } catch (e) {
      logPrint?.call('Retry evaluator threw, aborting retry: $e');
      return super.onError(err, handler);
    }

    if (!willRetry) return super.onError(err, handler);

    options._attempt = attempt;
    final delay = _jitteredDelay(attempt);

    logPrint?.call(
      '[${options.path}] retrying (attempt $attempt/$maxAttempts, '
      'delay ${delay.inMilliseconds}ms, error: ${err.error ?? err})',
    );

    // FormData can only be consumed once, so it must be cloned before reuse.
    final retryOptions = options.data is FormData
        ? options.copyWith(data: (options.data as FormData).clone())
        : options;

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    // Re-check after the delay: cancellation may have happened while waiting.
    if (options.cancelToken?.isCancelled ?? false) {
      logPrint?.call('[${options.path}] cancelled during retry delay');
      return super.onError(err, handler);
    }

    try {
      final response = await dio.fetch<void>(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      super.onError(e, handler);
    }
  }

  /// Computes the exponential backoff delay for [attempt], then applies
  /// full jitter: a random duration in `[0, delay]`.
  Duration _jitteredDelay(int attempt) {
    final exponential = baseDelay * pow(backoffFactor, attempt - 1);
    final capped = exponential < maxDelay ? exponential : maxDelay;
    final jitteredMs = (_random.nextDouble() * capped.inMilliseconds).round();
    return Duration(milliseconds: jitteredMs);
  }
}

const _kDisableRetryKey = 'ro_disable_retry';
const _kAttemptKey = 'ro_attempt';

/// Retry-related properties on [RequestOptions].
extension RequestOptionsX on RequestOptions {
  /// Current retry attempt number (0 = original request, not yet retried).
  int get attempt => _attempt;

  /// Whether retry is disabled for this request.
  bool get disableRetry => (extra[_kDisableRetryKey] as bool?) ?? false;
  set disableRetry(bool value) => extra[_kDisableRetryKey] = value;

  int get _attempt => (extra[_kAttemptKey] as int?) ?? 0;
  set _attempt(int value) => extra[_kAttemptKey] = value;
}

/// Retry-related properties on [Options].
extension OptionsX on Options {
  /// Whether retry is disabled for this request.
  bool get disableRetry => (extra?[_kDisableRetryKey] as bool?) ?? false;
  set disableRetry(bool value) {
    extra = Map.of(extra ?? <String, dynamic>{});
    extra![_kDisableRetryKey] = value;
  }
}
