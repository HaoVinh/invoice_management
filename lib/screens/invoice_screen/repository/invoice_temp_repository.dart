import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../repositories/abstract_interface.dart';
import '../../../repositories/abstract_repository.dart';
import '../../auth_screen/repository/auth_repostory.dart';
import '../model/car_dto.dart';
import '/screens/invoice_screen/model/invoice_temp_dto.dart';

class InvoiceTempRepository extends AbstractRepository
    implements AbstractInterface<double, InvoiceTempDto> {
  final String _finalUrl = '/data/invoicetemp';
  final String _saveUrl = '/data/saveinvoicetemp';

  Future<String> _getAccessToken() async {
    final token = await AuthRepository().getToken();
    if (token == null || token.isEmpty) {
      throw Exception("Chưa có accessToken, vui lòng đăng nhập lại.");
    }
    return token;
  }

  Future<List<InvoiceTempDto>> search(query,
      {required String cm,
      String? sDate,
      String? eDate,
      String? codeNV,
      String? maNX,
      String? statusNX}) async {
    try {
      final url = "$_finalUrl?cm=$cm"
          "${sDate != null ? '&sDate=$sDate' : ''}"
          "${eDate != null ? '&eDate=$eDate' : ''}"
          "${codeNV != null ? '&codeNV=$codeNV' : ''}"
          "${maNX != null ? '&maNX=$maNX' : ''}"
          "${statusNX != null ? '&statusNX=$statusNX' : ''}";
      print('Search URL: $url');

      final accessToken = await _getAccessToken();
      final response = await get(url: url, token: accessToken);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['err'] != 0) {
          return Future.error(data['msg'] ?? 'Lỗi không xác định');
        }

        if (data['dt'] == null || data['dt']['list_invoice_temps'] == null) {
          return [];
        }

        final List<dynamic> list = data['dt']['list_invoice_temps'];
        return list.map((item) => InvoiceTempDto.fromJson(item)).toList();
      } else {
        return Future.error(
            response.data['msg'] ?? 'Lỗi server: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioError) {
        return Future.error(
            e.response?.data['msg'] ?? 'Lỗi kết nối: ${e.message}');
      }
      return Future.error('Lỗi không xác định: $e');
    }
  }

  Future<List<CarDTO>> searchCar(String data) async {
    try {
      final url = "/data/license_plate?dt=$data";
      print('Search URL: $url');

      final accessToken = await _getAccessToken();
      final response = await get(url: url, token: accessToken);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['err'] != 0) {
          return Future.error(data['msg'] ?? 'Lỗi không xác định');
        }

        if (data['dt'] == null) {
          return [];
        }

        final List<dynamic> list = data['dt']['cars'];
        return list.map((item) => CarDTO.fromJson(item)).toList();
      } else {
        return Future.error(
            response.data['msg'] ?? 'Lỗi server: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioError) {
        return Future.error(
            e.response?.data['msg'] ?? 'Lỗi kết nối: ${e.message}');
      }
      return Future.error('Lỗi không xác định: $e');
    }
  }

  @override
  Future<InvoiceTempDto> create(InvoiceTempDto invoiceTempDto) async {
    throw UnimplementedError();
  }

  Future<bool> updateInvoiceTemp(InvoiceTempDto invoiceTempDto) async {
    try {
      final accessToken = await _getAccessToken();
      final data = {
        'data': jsonEncode({
          'invoiceTempDTO': invoiceTempDto.toJson(),
        }),
      };

      print('Sending data to API: $data');

      final response = await post(
        url: _saveUrl,
        data: data,
        token: accessToken,
      );

      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>?;

        if (responseData == null || responseData['err'] == null) {
          return false;
        }

        final err = responseData['err'] as int? ?? -1;
        final msg = responseData['msg'] as String? ?? 'Không có thông tin lỗi';

        if (err == 0) {
          print('Lưu tạm thành công: $msg');
          return true;
        } else {
          throw Exception(msg.isNotEmpty ? msg : 'Lỗi từ server (err: $err)');
        }
      } else {
        throw Exception(
            'Lỗi server: ${response.statusCode} - ${response.data['msg'] ?? 'Không có thông tin'}');
      }
    } catch (e) {
      if (e is DioError) {
        final msg = e.response?.data['msg'] ?? e.message ?? 'Lỗi kết nối';
        print('DioError khi lưu tạm: $msg');
        throw Exception(msg);
      }
      print('Lỗi khi lưu tạm: $e');
      rethrow;
    }
  }

  Future<List<String>> findProductCodeByBarcodeThung(String barcode) async {
    if (barcode.trim().isEmpty) {
      return [];
    }

    try {
      final barcodeLookupBaseUrl = dotenv.env['BARCODE_LOOKUP_URL'] ??
          'http://192.168.0.2:8380/norm/api/data/huongDanDongGoi';
      final url = "$barcodeLookupBaseUrl?cm=barcode&dt=${barcode.trim()}";
      final accessToken = dotenv.env['BARCODE_LOOKUP_TOKEN'] ?? '';

      final response = await get2(
        url: url,
        token: accessToken,
      ).timeout(const Duration(seconds: 3), onTimeout: () {
        throw Exception('API quá chậm, thử lại sau');
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = response.data;

        if (json['err'] != null && json['err'] != 0) {
          throw Exception(json['msg'] ?? 'Lỗi từ server');
        }

        final dynamic dataField = json['dt']?['data'];

        if (dataField is List) {
          return dataField
              .map((code) => code?.toString().trim())
              .where((code) => code != null && code.isNotEmpty)
              .cast<String>()
              .toList();
        } else if (dataField is String && dataField.trim().isNotEmpty) {
          return [dataField.trim()];
        }

        return [];
      } else {
        throw Exception('Lỗi server: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      print('Timeout khi gọi API barcode $barcode: $e');
      return [];
    } on DioError catch (e) {
      final msg = e.response?.data['msg'] ?? e.message;
      print('DioError khi tìm barcode $barcode: $msg');
      return [];
    } catch (e) {
      print('Lỗi khi tìm product code cho barcode $barcode: $e');
      return [];
    }
  }

  @override
  Future<void> delete(InvoiceTempDto invoiceTempDto) {
    throw UnimplementedError();
  }

  @override
  Future<List<InvoiceTempDto>> getAll() {
    throw UnimplementedError();
  }

  @override
  Future<InvoiceTempDto> getOne(double id) {
    throw UnimplementedError();
  }

  @override
  Future<InvoiceTempDto> update(InvoiceTempDto invoiceTempDto) {
    throw UnimplementedError();
  }
}
