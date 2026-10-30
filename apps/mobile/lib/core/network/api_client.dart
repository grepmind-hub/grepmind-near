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

  void init({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '${AppConstants.apiBaseUrl}${AppConstants.apiVersion}',
        connectTimeout: AppConstants.requestTimeout,
        receiveTimeout: AppConstants.requestTimeout,
        sendTimeout: AppConstants.requestTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    )
      ..interceptors.add(AuthInterceptor(_storage))
      ..interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  /// Convenience GET.
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
  }

  /// Convenience POST.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
  }

  /// Convenience PATCH.
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.patch<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
  }

  /// Convenience PUT.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
  }

  /// Convenience DELETE.
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options, cancelToken: cancelToken);
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
  AuthInterceptor(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: AppConstants.accessTokenKey);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    return handler.next(err);
  }
}

final ApiClient apiClient = ApiClient();
