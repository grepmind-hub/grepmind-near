import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';

/// Dio-based API client with automatic bearer-token injection.
class ApiClient {
  ApiClient._internal();
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Dio get dio => _dio;

  /// Resolves storage URLs returned by the API against the configured API host.
  /// This keeps emulator, local MinIO proxy and production cloud URLs configurable.
  String resolveMediaUrl(String path) {
    final value = path.trim();
    if (value.isEmpty) return value;
    final uri = Uri.parse(value);
    if (uri.hasScheme) return value;
    return Uri.parse(_dio.options.baseUrl).resolve(value).toString();
  }

  void init({String? baseUrl}) {
    final dio = Dio(
      BaseOptions(
        baseUrl:
            baseUrl ?? '${AppConstants.apiBaseUrl}${AppConstants.apiVersion}',
        connectTimeout: AppConstants.requestTimeout,
        receiveTimeout: AppConstants.requestTimeout,
        sendTimeout: AppConstants.requestTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    dio.interceptors.add(AuthInterceptor(_storage, dio));
    _dio = dio;
  }

  /// Convenience GET.
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Convenience POST.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Convenience PATCH.
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Convenience PUT.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Convenience DELETE.
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Direct Photo Upload to MinIO (Option 4).
  Future<Map<String, dynamic>> uploadMedia({
    required List<int> bytes,
    required String filename,
    String purpose = 'general',
  }) async {
    final formData = FormData.fromMap({
      'purpose': purpose,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post(
      '/media/upload',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.data['data'] as Map<String, dynamic>;
  }
}

/// Injects the access token from secure storage on every request.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage, this._dio);
  final FlutterSecureStorage _storage;
  final Dio _dio;
  Completer<String?>? _refreshInFlight;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuthHeader'] != true) {
      final token = await _storage.read(key: AppConstants.accessTokenKey);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        request.extra['skipAuthRefresh'] == true ||
        request.extra['retriedAfterRefresh'] == true ||
        request.path.endsWith('/auth/refresh') ||
        request.path.endsWith('/auth/otp/request') ||
        request.path.endsWith('/auth/otp/verify')) {
      return handler.next(err);
    }

    final token = await _refreshAccessToken();
    if (token == null) return handler.next(err);

    request.extra['retriedAfterRefresh'] = true;
    request.headers['Authorization'] = 'Bearer $token';
    try {
      return handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken() async {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh.future;

    final completer = Completer<String?>();
    _refreshInFlight = completer;
    try {
      final refreshToken = await _storage.read(
        key: AppConstants.refreshTokenKey,
      );
      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(null);
        return null;
      }
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(
          extra: const {'skipAuthHeader': true, 'skipAuthRefresh': true},
        ),
      );
      final data = response.data?['data'] as Map<String, dynamic>?;
      final accessToken = data?['access_token'] as String?;
      final rotatedRefreshToken = data?['refresh_token'] as String?;
      if (accessToken == null || rotatedRefreshToken == null) {
        completer.complete(null);
        return null;
      }
      await _storage.write(
        key: AppConstants.accessTokenKey,
        value: accessToken,
      );
      await _storage.write(
        key: AppConstants.refreshTokenKey,
        value: rotatedRefreshToken,
      );
      completer.complete(accessToken);
      return accessToken;
    } on DioException {
      await _storage.delete(key: AppConstants.accessTokenKey);
      await _storage.delete(key: AppConstants.refreshTokenKey);
      completer.complete(null);
      return null;
    } catch (_) {
      completer.complete(null);
      return null;
    } finally {
      _refreshInFlight = null;
    }
  }
}

final ApiClient apiClient = ApiClient();
