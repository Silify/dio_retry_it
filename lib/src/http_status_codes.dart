import 'package:dio_smart_retry/dio_smart_retry.dart';

// 1xx Informational status codes
const status100Continue = 100;
const status101SwitchingProtocols = 101;
const status102Processing = 102;

// 2xx Success status codes
const status200OK = 200;
const status201Created = 201;
const status202Accepted = 202;
const status203NonAuthoritative = 203;
const status204NoContent = 204;
const status205ResetContent = 205;
const status206PartialContent = 206;
const status207Multistatus = 207;
const status208AlreadyReported = 208;
const status226IMUsed = 226;

// 3xx Redirection status codes
const status300MultipleChoices = 300;
const status301MovedPermanently = 301;
const status302Found = 302;
const status303SeeOther = 303;
const status304NotModified = 304;
const status305UseProxy = 305;
const status306SwitchProxy = 306;
const status307TemporaryRedirect = 307;
const status308PermanentRedirect = 308;

// 4xx Client Errors status codes
const status400BadRequest = 400;
const status401Unauthorized = 401;
const status402PaymentRequired = 402;
const status403Forbidden = 403;
const status404NotFound = 404;
const status405MethodNotAllowed = 405;
const status406NotAcceptable = 406;
const status407ProxyAuthenticationRequired = 407;
const status408RequestTimeout = 408;
const status409Conflict = 409;
const status410Gone = 410;
const status411LengthRequired = 411;
const status412PreconditionFailed = 412;
const status413RequestEntityTooLarge = 413;
const status413PayloadTooLarge = 413;
const status414RequestUriTooLong = 414;
const status414UriTooLong = 414;
const status415UnsupportedMediaType = 415;
const status416RequestedRangeNotSatisfiable = 416;
const status416RangeNotSatisfiable = 416;
const status417ExpectationFailed = 417;
const status418ImATeapot = 418;
const status419AuthenticationTimeout = 419;
const status421MisdirectedRequest = 421;
const status422UnprocessableEntity = 422;
const status423Locked = 423;
const status424FailedDependency = 424;
const status426UpgradeRequired = 426;
const status428PreconditionRequired = 428;
const status429TooManyRequests = 429;
const status431RequestHeaderFieldsTooLarge = 431;
const status451UnavailableForLegalReasons = 451;

// 5xx Server Errors
const status500InternalServerError = 500;
const status501NotImplemented = 501;
const status502BadGateway = 502;
const status503ServiceUnavailable = 503;
const status504GatewayTimeout = 504;
const status505HttpVersionNotSupported = 505;
const status506VariantAlsoNegotiates = 506;
const status507InsufficientStorage = 507;
const status508LoopDetected = 508;
const status510NotExtended = 510;
const status511NetworkAuthenticationRequired = 511;

// Cloudflare Statuses
const status520WebServerReturnedUnknownError = 520;
const status521WebServerIsDown = 521;
const status522ConnectionTimedOut = 522;
const status523OriginIsUnreachable = 523;
const status524TimeoutOccurred = 524;
const status525SSLHandshakeFailed = 525;
const status526InvalidSSLCertificate = 526;
const status527RailgunError = 527;

// Vendor Specific
const status440LoginTimeout = 440; // IIS
const status499ClientClosedRequest = 499; // Nginx
const status460ClientClosedRequest = 460; // AWS ELB

// Network Timeouts (Non-standard)
const status598NetworkReadTimeoutError = 598;
const status599NetworkConnectTimeoutError = 599;

// Retryable Statuses
const defaultRetryableStatuses = <int>{
  status408RequestTimeout,
  status429TooManyRequests,
  status500InternalServerError,
  status502BadGateway,
  status503ServiceUnavailable,
  status504GatewayTimeout,
  status440LoginTimeout,
  status460ClientClosedRequest,
  status598NetworkReadTimeoutError,
  status599NetworkConnectTimeoutError,
  status520WebServerReturnedUnknownError,
  status522ConnectionTimedOut,
  status523OriginIsUnreachable,
  status524TimeoutOccurred,
  status527RailgunError,
};

/// All 1xx status codes
const Set<int> informationalStatuses = {
  status100Continue,
  status101SwitchingProtocols,
  status102Processing,
};

/// All 2xx status codes
const Set<int> successStatuses = {
  status200OK,
  status201Created,
  status202Accepted,
  status203NonAuthoritative,
  status204NoContent,
  status205ResetContent,
  status206PartialContent,
  status207Multistatus,
  status208AlreadyReported,
  status226IMUsed,
};

/// All 3xx status codes
const Set<int> redirectionStatuses = {
  status300MultipleChoices,
  status301MovedPermanently,
  status302Found,
  status303SeeOther,
  status304NotModified,
  status305UseProxy,
  status306SwitchProxy,
  status307TemporaryRedirect,
  status308PermanentRedirect,
};

/// All 4xx status codes
const Set<int> clientErrorStatuses = {
  status400BadRequest,
  status401Unauthorized,
  status402PaymentRequired,
  status403Forbidden,
  status404NotFound,
  status405MethodNotAllowed,
  status406NotAcceptable,
  status407ProxyAuthenticationRequired,
  status408RequestTimeout,
  status409Conflict,
  status410Gone,
  status411LengthRequired,
  status412PreconditionFailed,
  status413RequestEntityTooLarge,
  status414RequestUriTooLong,
  status415UnsupportedMediaType,
  status416RequestedRangeNotSatisfiable,
  status417ExpectationFailed,
  status418ImATeapot,
  status419AuthenticationTimeout,
  status421MisdirectedRequest,
  status422UnprocessableEntity,
  status423Locked,
  status424FailedDependency,
  status426UpgradeRequired,
  status428PreconditionRequired,
  status429TooManyRequests,
  status431RequestHeaderFieldsTooLarge,
  status451UnavailableForLegalReasons,
};

/// All 5xx status codes
const Set<int> serverErrorStatuses = {
  status500InternalServerError,
  status501NotImplemented,
  status502BadGateway,
  status503ServiceUnavailable,
  status504GatewayTimeout,
  status505HttpVersionNotSupported,
  status506VariantAlsoNegotiates,
  status507InsufficientStorage,
  status508LoopDetected,
  status510NotExtended,
  status511NetworkAuthenticationRequired,
};

/// All Cloudflare-specific status codes
const Set<int> cloudflareStatuses = {
  status520WebServerReturnedUnknownError,
  status521WebServerIsDown,
  status522ConnectionTimedOut,
  status523OriginIsUnreachable,
  status524TimeoutOccurred,
  status525SSLHandshakeFailed,
  status526InvalidSSLCertificate,
  status527RailgunError,
};

// For backward compatibility purpose
@Deprecated('Use [defaultRetryableStatuses]')
const retryableStatuses = defaultRetryableStatuses;

// For backward compatibility purpose
/// Be careful: this method do not
///   take into account [RetryInterceptor.retryableExtraStatuses]
bool isRetryable(int statusCode) =>
    defaultRetryableStatuses.contains(statusCode);
