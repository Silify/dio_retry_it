# Dio Retry It 🚀

**An Smarter retry interceptor for Dio with exponential backoff and full jitter based on dio_smart_retry**

[![Pub Version](https://img.shields.io/pub/v/dio_retry_it?logo=dart&logoColor=white)](https://pub.dev/packages/dio_retry_it/)
[![Dart SDK Version](https://badgen.net/pub/sdk-version/dio_retry_it)](https://pub.dev/packages/dio_retry_it/)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License](https://img.shields.io/github/license/rodion-m/dio_retry_it)](https://github.com/Silify/dio_retry_it/blob/master/LICENSE)


## ✨ Why Dio Retry It?

When building production apps, network failures are inevitable. **Dio Retry It** automatically handles these failures with an intelligent retry strategy that protects your servers from traffic spikes and improves user experience.

### 🎯 Key Features

- **⚡ Smart Retry Logic** - Automatically retries failed requests based on configurable rules
- **📈 Exponential Backoff with Full Jitter** - Prevents thundering herd problems when servers recover
- **🎲 Random Delays** - Avoids synchronized retry storms from thousands of clients
- **🔄 FormData Support** - Automatically clones FormData before retrying
- **🚫 Per-Request Control** - Disable retries for specific requests when needed
- **📝 Built-in Logging** - Track retry attempts with custom log functions
- **🔒 Null Safety** - Fully migrated to sound null safety
- **⚙️ Highly Configurable** - Customize every aspect of the retry behavior


## 📑 Table of Contents

- [✨ Why Dio Retry It?](#-why-dio-retry-it)
    - [🎯 Key Features](#-key-features)
- [🚀 Getting Started](#-getting-started)
    - [Installation](#installation)
    - [Basic Usage](#basic-usage)
- [🎯 How It Works](#-how-it-works)
    - [The Retry Strategy](#the-retry-strategy)
    - [Why Full Jitter Matters](#-why-full-jitter-matters)
- [📖 Advanced Usage](#-advanced-usage)
    - [Custom Retry Logic](#custom-retry-logic)
    - [Custom Retry Delays](#custom-retry-delays)
    - [Disable Retry for Specific Requests](#disable-retry-for-specific-requests)
    - [Working with FormData](#working-with-formdata)
- [⚙️ Configuration Reference](#️-configuration-reference)
    - [Constructor Parameters](#constructor-parameters)
    - [Default Retry Status Codes](#default-retry-status-codes)
    - [Extending Status Codes](#extending-status-codes)
- [🔄 Migration Guide](#-migration-guide)
    - [From dio_smart_retry to dio_retry_it](#from-dio_smart_retry-to-dio_retry_it)
- [📊 Performance & Best Practices](#-performance--best-practices)
    - [When to Use Retries](#-when-to-use-retries)
    - [Production Recommendations](#-production-recommendations)


## 🚀 Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  dio_retry_it: ^7.0.0
```

Then import it:

```dart
import 'package:dio_retry_it/dio_retry_it.dart';
```

### Basic Usage

```dart
final dio = Dio();

// Add the retry interceptor
dio.interceptors.add(
  RetryInterceptor(
    dio: dio,
    maxAttempts: 3,              // Retry up to 3 times
    baseDelay: Duration(milliseconds: 500),  // Start with 500ms
    maxDelay: Duration(seconds: 10),         // Cap at 10 seconds
    backoffFactor: 2.0,          // Double the delay each attempt
    logPrint: print,             // Optional: log retry attempts
  ),
);

// Now every failed request will be automatically retried
try {
  await dio.get('https://api.example.com/data');
} catch (e) {
  // After all retries fail, the error will be thrown
  print('Request failed after retries: $e');
}
```



## 🎯 How It Works

### The Retry Strategy

Unlike simple fixed-delay retries, **Dio Retry It** uses **exponential backoff with full jitter** - the gold standard for distributed systems.

**The Algorithm:**
1. Calculate exponential delay: `baseDelay × backoffFactor^(attempt-1)`
2. Cap at `maxDelay`
3. Apply full jitter: pick a random delay between `0` and the capped value

**Example with defaults** (`baseDelay: 500ms`, `backoffFactor: 2.0`, `maxDelay: 10s`):

| Attempt | Calculation | Delay Range |
|---------|-------------|-------------|
| 1 | 500ms × 2⁰ | 0-500ms |
| 2 | 500ms × 2¹ | 0-1,000ms |
| 3 | 500ms × 2² | 0-2,000ms |
| 4 | 500ms × 2³ | 0-4,000ms |
| 5 | 500ms × 2⁴ | 0-8,000ms |
| 6+ | Capped at 10s | 0-10,000ms |

### 🛡️ Why Full Jitter Matters

Imagine thousands of clients all hitting a server that's temporarily down. When the server recovers, without jitter, all clients would retry **at the exact same moment**, causing a massive traffic spike - effectively a DDoS attack on your own servers!

**Full jitter solves this** by randomizing retry times, spreading the load evenly across the recovery window.

> **Key Insight:** Random jitter matters far more for real-world reliability than a fixed delay schedule. This is why major cloud providers like AWS and Google Cloud recommend jitter-based retries.


## 📖 Advanced Usage

### Custom Retry Logic

Sometimes you need finer control over what gets retried:

```dart
final dio = Dio();

dio.interceptors.add(
  RetryInterceptor(
    dio: dio,
    maxAttempts: 5,
    retryEvaluator: (error, attempt) async {
      // Only retry specific errors
      if (error.type == DioExceptionType.connectionTimeout) return true;
      if (error.type == DioExceptionType.receiveTimeout) return true;
      
      // Retry server errors but not client errors
      if (error.type == DioExceptionType.badResponse) {
        final status = error.response?.statusCode ?? 0;
        return status >= 500 && status < 600;
      }
      
      return false;
    },
  ),
);
```

### Custom Retry Delays

Configure retry behavior for your specific needs:

```dart
dio.interceptors.add(
  RetryInterceptor(
    dio: dio,
    maxAttempts: 5,
    baseDelay: Duration(seconds: 1),     // Start with 1 second
    maxDelay: Duration(minutes: 1),      // Cap at 1 minute
    backoffFactor: 1.5,                  // Slower growth
    logPrint: (msg) => debugPrint(msg),
  ),
);
```

### Disable Retry for Specific Requests

Some requests shouldn't be retried (e.g., idempotent operations):

```dart
// Using RequestOptions
final request = RequestOptions(path: '/user/delete/123')
  ..disableRetry = true;
await dio.fetch(request);

// Using Options
final response = await dio.get(
  'https://api.example.com/status',
  options: Options(extra: {'disableRetry': true}),
);
```

### Working with FormData

**Dio Retry It** automatically clones FormData before retrying - no extra work needed!

```dart
final formData = FormData.fromMap({
  'file': await MultipartFile.fromFile('image.jpg'),
  'name': 'My Image',
});

// This will retry automatically if it fails
final response = await dio.post(
  'https://api.example.com/upload',
  data: formData,
);
```


## ⚙️ Configuration Reference

### Constructor Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dio` | `Dio` | **Required** | The Dio instance used for retries |
| `maxAttempts` | `int` | `3` | Maximum retry attempts (excludes original) |
| `baseDelay` | `Duration` | `500ms` | Starting delay before backoff |
| `maxDelay` | `Duration` | `10s` | Maximum delay cap |
| `backoffFactor` | `double` | `2.0` | Multiplier per attempt (must be ≥1) |
| `retryEvaluator` | `RetryEvaluator?` | Default evaluator | Custom retry decision logic |
| `logPrint` | `Function(String)?` | `null` | Logging callback |

### Default Retry Status Codes

By default, responses with these status codes are retried:

- **408** - Request Timeout
- **429** - Too Many Requests
- **500** - Internal Server Error
- **502** - Bad Gateway
- **503** - Service Unavailable
- **504** - Gateway Timeout
- **440** - Login Timeout (IIS)
- **460** - Client Closed Request (AWS ELB)
- **499** - Client Closed Request (nginx)
- **520** - Web Server Unknown Error
- **521** - Web Server Is Down
- **522** - Connection Timed Out
- **523** - Origin Unreachable
- **524** - Timeout Occurred
- **525** - SSL Handshake Failed
- **527** - Railgun Error
- **598** - Network Read Timeout
- **599** - Network Connect Timeout

### Extending Status Codes

```dart
// Add your own status codes
final evaluator = DefaultRetryEvaluator(
  {...defaultRetryableStatuses, 401, 403},
);

dio.interceptors.add(
  RetryInterceptor(
    dio: dio,
    retryEvaluator: evaluator.evaluate,
  ),
);
```

## 🔄 Migration Guide

### From dio_smart_retry to dio_retry_it


### Key Changes

| dio_smart_retry          | dio_retry_it                               |
|--------------------------|--------------------------------------------|
| `retries: 3`             | `maxAttempts: 3`                           |
| `retryDelays: [...]`     | `baseDelay` + `backoffFactor` + `maxDelay` |
| `retryableExtraStatuses` | Custom `retryEvaluator`                    |
| Fixed delays             | Exponential backoff with full jitter ✅     |
| Manual FormData handling | Automatic cloning ✅                        |


### Migration Examples

#### Basic Retry

**Before:**
```dart
RetryInterceptor(
  dio: dio,
  retries: 3,
  retryDelays: const [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ],
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


#### Custom Status Codes

**Before:**
```dart
RetryInterceptor(
  dio: dio,
  retries: 3,
  retryableExtraStatuses: {401, 403},
)
```

**After:**
```dart
RetryInterceptor(
  dio: dio,
  maxAttempts: 3,
  retryEvaluator: (error, attempt) {
    if (error.type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      return status == 401 || status == 403;
    }
    return false;
  },
)
```

#### FormData

**Before:**
```dart
// Manual handling was needed
final formData = FormData.fromMap({'file': file});
// Interceptor called _recreateOptions internally
```

**After:**
```dart
// Automatic cloning - works out of the box!
final formData = FormData.fromMap({'file': file});
// No extra code needed
```


### Removed Parameters

| Parameter | Replacement |
|-----------|-------------|
| `retryableExtraStatuses` | Custom `retryEvaluator` |
| `ignoreRetryEvaluatorExceptions` | Built-in error handling |
| `retryDelays` | `baseDelay` + `backoffFactor` |


### ✅ Migration Checklist

- [ ] Replace `retries` → `maxAttempts`
- [ ] Replace `retryDelays` → `baseDelay` + `backoffFactor`
- [ ] Add `maxDelay` parameter
- [ ] Update custom status codes to use `retryEvaluator`
- [ ] Remove `ignoreRetryEvaluatorExceptions` if used
- [ ] Test your app


**Benefit:** New package prevents thundering herd problems with **exponential backoff + full jitter** - critical for production apps with many concurrent users! 🚀


## 📊 Performance & Best Practices

### 🎯 When to Use Retries

**✅ Good Candidates:**
- GET requests (idempotent)
- Network timeouts
- Temporary server errors (5xx)
- Rate limiting (429)
- Connection issues

**❌ Avoid Retries For:**
- POST/PUT/DELETE mutations (unless idempotent)
- Client errors (4xx except 429)
- Cancelled requests
- Format/serialization errors

### 📈 Production Recommendations

```dart
// Recommended production configuration
dio.interceptors.add(
  RetryInterceptor(
    dio: dio,
    maxAttempts: 3,
    baseDelay: Duration(milliseconds: 1000),
    maxDelay: Duration(seconds: 30),
    backoffFactor: 2.0,
    logPrint: (msg) {
      // Only log in development
      if (kDebugMode) print(msg);
    },
  ),
);
```


## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.


## 🙏 Acknowledgments

This package is a next-generation fork of the abandoned `dio_smart_retry` package, rebuilt with:

- ✅ Modern Dart practices
- ✅ Full null safety
- ✅ Exponential backoff with full jitter
- ✅ Better FormData handling
- ✅ Improved error handling
- ✅ Better test coverage


## 📞 Support

- 📚 [GitHub Repository](https://github.com/Silify/dio_retry_it)
- 🐛 [Issue Tracker](https://github.com/Silify/dio_retry_it/issues)
- 📦 [Pub.dev Package](https://pub.dev/packages/dio_retry_it)

---

**Made with ❤️ for the Dart community**

---

© 2026 Silify

