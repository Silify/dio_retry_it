## 8.0.1

- Improve code quality and fix dart analyze issues

## 8.0.0

- **[BREAKING CHANGE]** Complete redesign of retry strategy from **fixed delays** to **exponential backoff with full jitter**
- **[BREAKING CHANGE]** Removed `retryDelays` parameter - replaced with `baseDelay`, `maxDelay`, and `backoffFactor`
- **[BREAKING CHANGE]** Renamed `retries` parameter to `maxAttempts` for clarity
- **[BREAKING CHANGE]** Removed `retryableExtraStatuses` parameter - use custom `retryEvaluator` instead
- **[BREAKING CHANGE]** Removed `ignoreRetryEvaluatorExceptions` parameter - built-in error handling
- **[BREAKING CHANGE]** Removed `MultipartFileRecreatable` - use regular `MultipartFile` with automatic cloning
- **[NEW]** Exponential backoff with full jitter prevents thundering herd problems
- **[NEW]** Automatic FormData cloning - no manual recreation needed
- **[NEW]** Better logging with attempt count and delay information
- **[IMPROVED]** Better error handling in retry evaluator
- **[IMPROVED]** Enhanced documentation with examples
- **[IMPROVED]** Full null safety with modern Dart practices

### Migration Guide

Replace fixed delays with exponential backoff:

**Before:**
```dart
RetryInterceptor(
  dio: dio,
  retries: 3,
  retryDelays: [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 3)],
)
```

**After:**
```dart
RetryInterceptor(
  dio: dio,
  maxAttempts: 3,
  baseDelay: Duration(seconds: 1),
  maxDelay: Duration(seconds: 10),
  backoffFactor: 2.0,
)
```

## 7.0.0
- [BREAKING CHANGE] `MultipartFileRecreatable` removed. Use a regular `MultipartFile` instead of `MultipartFileRecreatable`.

## 6.0.0
- Updated internal libraries.
- Bumped minimum Dart SDK to 3.0.
- Added `MultipartFileRecreatable` documentation.
- Refactors static constructors to factories.
- Adds a new `MultipartFileRecreatable.fromBytes` factory compatible with web.
- Added a new `headers` parameter.
- You can now read the file's content with `MultipartFileRecreatable.data`.
- **Breaking:** `MultipartFileRecreatable.filename` is now a named parameter to match `dio`.
- **Breaking:** Removed `MultipartFileRecreatable.filePath` since it was not being used internally.

## 5.0.0
- Add supporting of the new dio 5.+

## 2.0.1-diox
- Add supporting of [DioX](https://pub.dev/packages/diox)

## 1.4.0
- Add supporting of retrying for requests with `multipart/form-data`, use `MultipartFileRecreatable` class for that ([details](https://github.com/Silify/dio_retry_it#retry-requests-with-multipartform-data)).
- `DefaultRetryEvaluator` and status codes constants from the file `http_status_codes.dart` was made a part of the public API.

## 1.3.2
- Add a feature allowing to specify extra retryable status codes (parameter `retryableExtraStatuses`) (#11)
- Add a request's `CancelToken` checking
- Update dependencies

## 1.2.0

- Add properly an incorrect url scheme error handling in the default  retry evaluator (#2)

## 1.1.0

- A request catching is fixed (#1)
- Dependencies were updated

## 1.0.3

- Example updated

## 1.0.2

- Initial version.
