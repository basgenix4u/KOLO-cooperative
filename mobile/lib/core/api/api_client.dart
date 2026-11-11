import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exception.dart';
import 'token_store.dart';

/// The single door to the KOLO backend.
///
/// Responsibilities, in order of importance:
///  1. never let a stale access token turn into a confusing failure — refresh
///     once, replay the request, and only then give up;
///  2. never replay a money request that might have succeeded;
///  3. turn transport problems into failures the UI can describe honestly.
class ApiClient {
  ApiClient({required TokenStore tokens, String? baseUrl, Dio? dio})
      : _tokens = tokens,
        _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: baseUrl ?? defaultBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      // 4xx are failures, not responses. `onError` — and therefore the
      // refresh-and-retry path — only runs for statuses Dio rejects. Allowing
      // 4xx through here made session recovery dead code: an expired access
      // token surfaced as a raw "token not valid" error and the member was
      // never refreshed, never retried, never signed out cleanly.
      validateStatus: (status) => status != null && status < 400,
    );
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _attachToken, onError: _onError),
    );
  }

  /// Sandbox default. Overridden at build time with
  /// `--dart-define=KOLO_API_BASE=https://…`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'KOLO_API_BASE',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  final Dio _dio;
  final TokenStore _tokens;

  /// Called when the session is unrecoverable, so the app can send the member
  /// back to sign-in instead of showing an error they cannot act on.
  VoidCallback? onSessionExpired;

  Future<void> _attachToken(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokens.accessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final response = error.response;
    if (response != null && response.statusCode == 401 && !_isAuthEndpoint(error.requestOptions.path)) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        try {
          final replay = await _replay(error.requestOptions);
          return handler.resolve(replay);
        } on DioException catch (retryError) {
          return handler.next(retryError);
        }
      }
      await _tokens.clear();
      onSessionExpired?.call();
    }
    handler.next(error);
  }

  /// A money-moving request is only replayed when it carries an idempotency key.
  /// Without one, a replay after a refresh could charge a member twice.
  ///
  /// Header lookup is case-insensitive: Dio normalises header names, so an
  /// exact `containsKey('Idempotency-Key')` silently missed the key and refused
  /// to replay safe writes.
  bool _hasIdempotencyKey(RequestOptions options) =>
      options.headers.keys.any((key) => key.toLowerCase() == 'idempotency-key');

  Future<Response<dynamic>> _replay(RequestOptions options) {
    final isWrite = options.method != 'GET';
    final hasKey = _hasIdempotencyKey(options);
    if (isWrite && !hasKey) {
      throw DioException(
        requestOptions: options,
        error: 'Refusing to replay a non-idempotent write after a token refresh',
      );
    }
    return _dio.fetch(options);
  }

  bool _isAuthEndpoint(String path) =>
      path.contains('/auth/login') || path.contains('/auth/refresh') || path.contains('/auth/register');

  Future<bool> _tryRefresh() async {
    final refresh = await _tokens.refreshToken();
    if (refresh == null) return false;

    try {
      final response = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl)).post(
        '/auth/refresh/',
        data: {'refresh': refresh},
      );
      final data = response.data is Map ? response.data['data'] as Map? : null;
      final access = data?['access'] as String?;
      final newRefresh = data?['refresh'] as String?;
      if (access == null) return false;
      if (newRefresh != null) {
        await _tokens.save(access: access, refresh: newRefresh);
      } else {
        await _tokens.updateAccess(access);
      }
      return true;
    } on DioException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Verbs
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final data = await _send(() => _dio.get(path, queryParameters: query));
    return _unwrap(data);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    final data = await _send(
      () => _dio.post(
        path,
        data: body,
        options: Options(headers: idempotencyKey == null ? null : {'Idempotency-Key': idempotencyKey}),
      ),
    );
    return _unwrap(data);
  }

  Future<Map<String, dynamic>> patch(String path, {Object? body}) async {
    final data = await _send(() => _dio.patch(path, data: body));
    return _unwrap(data);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final data = await _send(() => _dio.delete(path));
    return _unwrap(data);
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      // A 3xx or 4xx that reaches here came from the replay path; the normal
      // path already rejected anything under 400 via `validateStatus`.
      final status = response.statusCode ?? 0;
      if (status >= 300) {
        throw ApiException.fromResponse(response);
      }
      return response.data;
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapTransportError(error);
    }
  }

  /// Server responses are wrapped as `{"data": …}`; unwrap once here so no
  /// feature has to remember the envelope.
  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map<String, dynamic>) {
      final inner = data['data'];
      if (inner is Map<String, dynamic>) {
        // Keep meta alongside for pagination and counts.
        if (data['meta'] is Map) {
          return {...inner, '_meta': data['meta']};
        }
        return inner;
      }
      return data;
    }
    return const {};
  }

  /// Lists arrive as `{"data": [ … ]}`, which `_unwrap` flattens away. List
  /// endpoints therefore go through this instead.
  Future<List<Map<String, dynamic>>> getList(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      final status = response.statusCode ?? 0;
      if (status >= 300) throw ApiException.fromResponse(response);

      final body = response.data;
      final list = body is Map ? body['data'] : body;
      if (list is List) {
        return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
      return const [];
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapTransportError(error);
    }
  }

  ApiException _mapTransportError(DioException error) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout) {
      return ApiException(code: 'network_error', message: 'The connection timed out.');
    }
    if (type == DioExceptionType.connectionError) {
      return ApiException(
        code: 'offline',
        message: 'KOLO could not reach the server. Check your connection.',
      );
    }
    final response = error.response;
    if (response != null) return ApiException.fromResponse(response);
    return ApiException(code: 'network_error', message: 'Something went wrong on the way.');
  }
}
