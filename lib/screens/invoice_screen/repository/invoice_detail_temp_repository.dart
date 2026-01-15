import 'dart:convert';

import 'package:dio/dio.dart';
import '../../auth_screen/repository/auth_repostory.dart';
import '../model/invoice_detail_temp_dto.dart';
import '/repositories/abstract_interface.dart';
import '/screens/invoice_screen/model/invoice_temp_dto.dart';

import '../../../repositories/abstract_repository.dart';
import '../../../utils/secure_storage.dart';

class InvoiceDetailTempRepository extends AbstractRepository {
  final String _finalUrl = '/data/invoicedetailtemp';
  final String _saveUrl = '/data/saveinvoicedetailtemp';
  Future<String> _getAccessToken() async {
    final token = await AuthRepository().getToken();
    if (token == null || token.isEmpty) {
      throw Exception("Chưa có accessToken, vui lòng đăng nhập lại.");
    }
    return token;
  }

  Future<List<InvoiceDetailTempDto>> searchInvoiceDetail({
    required String cm,
    required int idInvoice,
  }) async {
    try {
      var dt = '$cm,$idInvoice';
      var url = "$_finalUrl?cm=$cm&dt=$dt";
      final accessToken = await _getAccessToken();
      var response = await get(url: url, token: accessToken);

      if (response.statusCode == 200) {
        var data = response.data;
        var res = InvoiceDetailTempResponse.fromJson(data);
        if (res.err != 0) {
          return Future.error(res.msg ?? 'Lỗi không xác định');
        }
        return res.listInvoiceDetailTemps ?? [];
      } else {
        return Future.error('Lỗi khi gọi API: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in searchInvoiceDetail: $e');
      rethrow;
    }
  }
Future<List<InvoiceDetailTempDto>> create(
      List<InvoiceDetailTempDto> invoiceDetailTempDtos) async {
    try {
      final accessToken = await _getAccessToken();
      final data = {
        'data': jsonEncode({
          'invoiceDetailTemps': invoiceDetailTempDtos.map((dto) => dto.toJson()).toList(),
        }),
      };

      print('Sending data to API: $data');

      final response = await post(
        url: _saveUrl,
        data: data,
        token: accessToken,
      );

      if (response.statusCode == 200) {
        final responseData = response.data as Map<String, dynamic>;
        if (responseData['err'] != null && responseData['err'] != 0) {
          throw Exception(responseData['msg'] ?? 'Lỗi không xác định');
        }
        if (responseData['data'] == null || responseData['data'].isEmpty) {
          return invoiceDetailTempDtos;
        }

        final dataList = responseData['data'] as List;
        final result = dataList
            .map((item) => InvoiceDetailTempDto.fromJson(item as Map<String, dynamic>))
            .toList();

        return result;
      } else {
        return Future.error(response.data['message'] ?? 'Lỗi server');
      }
    } catch (e) {
      if (e is DioError) {
        return Future.error(
            e.response?.data['message'] ?? 'Lỗi kết nối: ${e.message}');
      }
      return Future.error('Lỗi không xác định: $e');
    }
  }
}

  @override
  Future<void> delete(InvoiceDetailTempDto invoiceDetailTempDto) {
    throw UnimplementedError();
  }

  @override
  Future<List<InvoiceDetailTempDto>> getAll() {
    throw UnimplementedError();
  }

  @override
  Future<InvoiceDetailTempDto> getOne(double id) {
    throw UnimplementedError();
  }

  @override
  Future<InvoiceDetailTempDto> update(
      InvoiceDetailTempDto invoiceDetailTempDto) {
    throw UnimplementedError();
  }


