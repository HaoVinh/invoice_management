import 'dart:convert';

import 'package:dio/dio.dart';
import '../model/invoice_detail_temp_dto.dart';
import '/repositories/abstract_interface.dart';
import '/screens/invoice_screen/model/invoice_temp_dto.dart';

import '../../../repositories/abstract_repository.dart';
import '../../../utils/secure_storage.dart';

class InvoiceDetailTempRepository extends AbstractRepository {
  final String _finalUrl = '/data/invoicedetailtemp';
  final String _saveUrl = '/data/saveinvoicedetailtemp';

  Future<List<InvoiceDetailTempDto>> searchInvoiceDetail({
    required String cm,
    required int idInvoice,
  }) async {
    try {
      var dt = '$cm,$idInvoice';
      var url = "$_finalUrl?cm=$cm&dt=$dt";
      print('Calling API: $url');
      // final auth = await secureStorage.readAuth();

      // Token tạm thời
      var accessToken =
          "Bearer eyJhbGciOiJSUzI1NiJ9.eyJ1c2VyTmFtZSI6ImFkbWluYXBpIiwic3ViIjoiTElYQ08iLCJqdGkiOiJjNmIyMGVkZS03YTVlLTQwNzMtYjA2Zi0wOTAxZTQ0NzdiZTYiLCJpYXQiOjE3NDcxODMyNTIsImV4cCI6MTc0OTc3NTI1Mn0.IS_UKLFHqVsgSmuE8fPp-bGiPJf-8Fo2UV9C6n9wUFDaxY1t0BpQZWKPjrX7zfnTZOF0wUQnl4qhDLrtbmBFgs9UYhMRLvplrFvrh66k_BFdAgWY484QNpRKVRaYKlyhMgDcwy-i72s9StL_gRnj2j6zybqs5lTpSj4sN4PbSLTrcsu3u0HcabiroHrliIjoClQZdK_XXtiEyaJEnTqo_aZueungU550k4CJgQnhbffQcBL6bA6fCTdbqav2_M9adE-uaOzNzpD-cdS9DqH6rnNib2X4PXvUHhMBS8FG_fs3Kvb3gkF-xLU8OmomKPbuf6GlZiXURsATrmpIdhsOow";
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
@override
  Future<List<InvoiceDetailTempDto>> create(
      List<InvoiceDetailTempDto> invoiceDetailTempDtos) async {
    try {
      var accessToken =
          "eyJhbGciOiJSUzI1NiJ9.eyJ1c2VyTmFtZSI6ImFkbWluYXBpIiwic3ViIjoiTElYQ08iLCJqdGkiOiJjNmIyMGVkZS03YTVlLTQwNzMtYjA2Zi0wOTAxZTQ0NzdiZTYiLCJpYXQiOjE3NDcxODMyNTIsImV4cCI6MTc0OTc3NTI1Mn0.IS_UKLFHqVsgSmuE8fPp-bGiPJf-8Fo2UV9C6n9wUFDaxY1t0BpQZWKPjrX7zfnTZOF0wUQnl4qhDLrtbmBFgs9UYhMRLvplrFvrh66k_BFdAgWY484QNpRKVRaYKlyhMgDcwy-i72s9StL_gRnj2j6zybqs5lTpSj4sN4PbSLTrcsu3u0HcabiroHrliIjoClQZdK_XXtiEyaJEnTqo_aZueungU550k4CJgQnhbffQcBL6bA6fCTdbqav2_M9adE-uaOzNzpD-cdS9DqH6rnNib2X4PXvUHhMBS8FG_fs3Kvb3gkF-xLU8OmomKPbuf6GlZiXURsATrmpIdhsOow";

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


