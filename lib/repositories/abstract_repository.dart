import 'package:dio/dio.dart';
import 'package:invoice_management/network/error_handling.dart';

import '../constants/env.dart' as env;
import '../network/interceptor.dart';

abstract class AbstractRepository {
  late Dio _dio;
  late String baseURL;

  AbstractRepository() {
    BaseOptions options = BaseOptions(
      receiveTimeout:  const Duration(seconds: 15),
      connectTimeout: const Duration(seconds: 20),
    );

    _dio = Dio(options);
    _dio.interceptors.add(LoggingInterceptor());
    baseURL = env.baseUrl;
  }

  Future<Response> get(
      {required String url,
      String? token,
      String? finalUrl,
      Map<String, dynamic>? queryParameters,
      }) async {
    final String _url = finalUrl ?? baseURL;
    try {
      return await _dio.get(
        _url + url,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) "Authorization": "Bearer $token",

          },
        ),
        queryParameters: queryParameters,
      );
    } on DioError catch (e) {
      throw ErrorHandling(e.response);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> post(
      {required String url,
      String? finalUrl,
      dynamic data,
      String? token,
     }) async {
    final String _url = finalUrl ?? baseURL;
    try {
      return await _dio.post(
        _url + url,
        data: data,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) "Authorization": "Bearer $token",

          },
        ),
      );
    } on DioError catch (e) {
      throw ErrorHandling(e.response);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> put(
      {required String url,
      String? finalUrl,
      dynamic data,
      String? token,
     }) async {
    final String _url = finalUrl ?? baseURL;
    try {
      return await _dio.put(
        _url + url,
        data: data,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) "Authorization": "Bearer $token",

          },
        ),
      );
    } on DioError catch (e) {
      throw ErrorHandling(e.response);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> deleteHttp(
      {required String url,
      String? finalUrl,
      String? token,
    }) async {
    final String _url = finalUrl ?? baseURL;
    try {
      return await _dio.delete(
        (_url + url),
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            if (token != null) "Authorization": "Bearer $token",
          },
        ),
      );
    } on DioError catch (e) {
      throw ErrorHandling(e.response);
    } catch (e) {
      rethrow;
    }
  }
  Future<Response> get2(
      {required String url,
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
            if (token != null) "token": "$token",

          },
        ),
        queryParameters: queryParameters,
      );
    } on DioError catch (e) {
      throw ErrorHandling(e.response);
    } catch (e) {
      rethrow;
    }
  }
}
