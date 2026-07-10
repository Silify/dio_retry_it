import 'dart:convert';

import 'package:dio/dio.dart';

/// What a single simulated network call should do.
enum _Kind { success, connectionError, badResponse, cancel, formatError }

class AdapterBehavior {
  final _Kind kind;
  final int? statusCode;
  final Map<String, dynamic>? body;

  const AdapterBehavior.success({this.statusCode = 200, this.body})
      : kind = _Kind.success;

  const AdapterBehavior.connectionError()
      : kind = _Kind.connectionError,
        statusCode = null,
        body = null;

  const AdapterBehavior.badResponse(int code)
      : kind = _Kind.badResponse,
        statusCode = code,
        body = null;

  const AdapterBehavior.cancel()
      : kind = _Kind.cancel,
        statusCode = null,
        body = null;

  const AdapterBehavior.formatError()
      : kind = _Kind.formatError,
        statusCode = null,
        body = null;
}

/// A minimal fake [HttpClientAdapter] that plays back a scripted list of
/// [AdapterBehavior]s, one per call. If more calls happen than behaviors
/// were provided, the last behavior repeats. Every call (and its
/// timestamp) is recorded so tests can assert on retry counts and timing.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.behaviors);

  final List<AdapterBehavior> behaviors;
  int callCount = 0;
  final List<DateTime> callTimestamps = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callTimestamps.add(DateTime.now());
    final index =
        callCount < behaviors.length ? callCount : behaviors.length - 1;
    final behavior = behaviors[index];
    callCount++;
    print('  [ScriptedAdapter] call #$callCount -> ${behavior.kind}'
        '${behavior.statusCode != null ? ' (${behavior.statusCode})' : ''}');

    switch (behavior.kind) {
      case _Kind.connectionError:
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Simulated connection error',
        );
      case _Kind.cancel:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case _Kind.formatError:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const FormatException('Simulated bad payload'),
        );
      case _Kind.badResponse:
      case _Kind.success:
        final code = behavior.statusCode ?? 200;
        final bytes = utf8.encode(jsonEncode(behavior.body ?? {'ok': true}));
        return ResponseBody.fromBytes(
          bytes,
          code,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    }
  }

  @override
  void close({bool force = false}) {}
}
