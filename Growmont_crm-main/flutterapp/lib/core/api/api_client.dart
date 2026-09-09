import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'endpoints.dart';

typedef LogoutCallback = Future<void> Function();

class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required LogoutCallback onUnauthorized,
  }) : _tokenStorage = tokenStorage,
       _onUnauthorized = onUnauthorized {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final requireAuth = options.extra['requireAuth'] != false;
          if (requireAuth) {
            final token = await _tokenStorage.getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              error.requestOptions.extra['requireAuth'] != false) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final opts = error.requestOptions;
              final token = await _tokenStorage.getAccessToken();
              opts.headers['Authorization'] = 'Bearer $token';
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            }
            await _onUnauthorized();
          }
          handler.next(error);
        },
      ),
    );
  }

  final TokenStorage _tokenStorage;
  final LogoutCallback _onUnauthorized;
  late final Dio _dio;

  Dio get dio => _dio;

  Future<bool> _tryRefresh() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await Dio(
        BaseOptions(baseUrl: AppConfig.baseUrl),
      ).post(Endpoints.refresh, data: {'refresh': refreshToken});
      final access = response.data['access'] as String;
      final user = await _tokenStorage.getUser();
      if (user == null) return false;
      await _tokenStorage.saveSession(
        accessToken: access,
        refreshToken: refreshToken,
        user: user,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requireAuth = true,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: Options(extra: {'requireAuth': requireAuth}),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    bool requireAuth = true,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      options: Options(extra: {'requireAuth': requireAuth}),
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    bool requireAuth = true,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      options: Options(extra: {'requireAuth': requireAuth}),
    );
  }

  Future<Response<T>> delete<T>(String path, {bool requireAuth = true}) {
    return _dio.delete<T>(
      path,
      options: Options(extra: {'requireAuth': requireAuth}),
    );
  }

  Future<Response> upload(
    String path,
    FormData formData, {
    bool requireAuth = true,
    String method = 'POST',
  }) {
    return _dio.request(
      path,
      data: formData,
      options: Options(
        method: method,
        extra: {'requireAuth': requireAuth},
        contentType: 'multipart/form-data',
      ),
    );
  }

  Future<Response> downloadFile(
    String path,
    String savePath, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.download(path, savePath, queryParameters: queryParameters);
  }
}
