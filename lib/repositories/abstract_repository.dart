import 'package:dio/dio.dart';
import 'package:invoice_management/network/error_handling.dart';
import '../constants/env.dart' as env;
import '../network/interceptor.dart';

abstract class AbstractRepository {
  late Dio _dio;

  AbstractRepository() {
    final options = BaseOptions(
      receiveTimeout: const Duration(seconds: 15),
      connectTimeout: const Duration(seconds: 20),
    );

    _dio = Dio(options);
    _dio.interceptors.add(LoggingInterceptor());
  }

  String _getFullUrl(String url, String? finalUrl) {
    final base = finalUrl ?? env.Environment.baseUrl;
    return base.endsWith('/') ? '$base$url' : '$base$url';
  }

  Future<Response> get({
    required String url,
    String? token,
    String? finalUrl,
    Map<String, dynamic>? queryParameters,
  }) async {
    final fullUrl = _getFullUrl(url, finalUrl);

    try {
      return await _dio.get(
        fullUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
        queryParameters: queryParameters,
      );
    } on DioException catch (e) {
      throw ErrorHandling.showMessage(e);
    } catch (e) {
      throw ErrorHandling.getErrorMessage(e);
    }
  }

  Future<Response> post({
    required String url,
    String? finalUrl,
    dynamic data,
    String? token,
  }) async {
    final fullUrl = _getFullUrl(url, finalUrl);

    try {
      return await _dio.post(
        fullUrl,
        data: data,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw ErrorHandling.showMessage(e);
    } catch (e) {
      throw ErrorHandling.getErrorMessage(e);
    }
  }

  Future<Response> put({
    required String url,
    String? finalUrl,
    dynamic data,
    String? token,
  }) async {
    final fullUrl = _getFullUrl(url, finalUrl);

    try {
      return await _dio.put(
        fullUrl,
        data: data,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw ErrorHandling.showMessage(e);
    } catch (e) {
      throw ErrorHandling.getErrorMessage(e);
    }
  }

  Future<Response> deleteHttp({
    required String url,
    String? finalUrl,
    String? token,
  }) async {
    final fullUrl = _getFullUrl(url, finalUrl);

    try {
      return await _dio.delete(
        fullUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw ErrorHandling.showMessage(e);
    } catch (e) {
      throw ErrorHandling.getErrorMessage(e);
    }
  }

  Future<Response> get2({
    required String url,
    String? token,
    String? finalUrl,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) 'token': token,
          },
        ),
        queryParameters: queryParameters,
      );
    } on DioException catch (e) {
      throw ErrorHandling.showMessage(e);
    } catch (e) {
      throw ErrorHandling.getErrorMessage(e);
    }
  }
}
