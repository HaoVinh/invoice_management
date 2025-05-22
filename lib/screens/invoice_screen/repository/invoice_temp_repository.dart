import 'dart:convert';

import 'package:dio/dio.dart';
import '/repositories/abstract_interface.dart';
import '/screens/invoice_screen/model/invoice_temp_dto.dart';

import '../../../repositories/abstract_repository.dart';
import '../../../utils/secure_storage.dart';

class InvoiceTempRepository extends AbstractRepository
    implements AbstractInterface<double, InvoiceTempDto> {
  final String _finalUrl = '/data/invoicetemp';
  final String _saveUrl = '/data/saveinvoicetemp';


  Future<List<InvoiceTempDto>> search(query, {required cm, sDate, eDate}) async {
    try {
      var url = "$_finalUrl?cm=$cm&sDate=$sDate&eDate=$eDate";
      print('url: $url');
      // final auth = await secureStorage.readAuth();

      var accessToken = "Bearer eyJhbGciOiJSUzI1NiJ9.eyJ1c2VyTmFtZSI6ImFkbWluYXBpIiwic3ViIjoiTElYQ08iLCJqdGkiOiJjNmIyMGVkZS03YTVlLTQwNzMtYjA2Zi0wOTAxZTQ0NzdiZTYiLCJpYXQiOjE3NDcxODMyNTIsImV4cCI6MTc0OTc3NTI1Mn0.IS_UKLFHqVsgSmuE8fPp-bGiPJf-8Fo2UV9C6n9wUFDaxY1t0BpQZWKPjrX7zfnTZOF0wUQnl4qhDLrtbmBFgs9UYhMRLvplrFvrh66k_BFdAgWY484QNpRKVRaYKlyhMgDcwy-i72s9StL_gRnj2j6zybqs5lTpSj4sN4PbSLTrcsu3u0HcabiroHrliIjoClQZdK_XXtiEyaJEnTqo_aZueungU550k4CJgQnhbffQcBL6bA6fCTdbqav2_M9adE-uaOzNzpD-cdS9DqH6rnNib2X4PXvUHhMBS8FG_fs3Kvb3gkF-xLU8OmomKPbuf6GlZiXURsATrmpIdhsOow";
      var response = await get(url: url, token: accessToken);
      if (response.statusCode == 200) {
        var data = response.data;
        var res = InvoiceTempResponse.fromJson(data);
        if (res.err != 0) {
          return Future.error(res.msg ?? 'Lỗi không xác định');
        }
        return res.listInvoiceTemps ?? [];
      } else {
        return Future.error(response.data['message']);
      }
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<InvoiceTempDto> create(InvoiceTempDto invoiceTempDto) async {
    try {
      // final auth = await secureStorage.readAuth();
      var accessToken =
          "Bearer eyJhbGciOiJSUzI1NiJ9.eyJ1c2VyTmFtZSI6ImFkbWluYXBpIiwic3ViIjoiTElYQ08iLCJqdGkiOiJjNmIyMGVkZS03YTVlLTQwNzMtYjA2Zi0wOTAxZTQ0NzdiZTYiLCJpYXQiOjE3NDcxODMyNTIsImV4cCI6MTc0OTc3NTI1Mn0.IS_UKLFHqVsgSmuE8fPp-bGiPJf-8Fo2UV9C6n9wUFDaxY1t0BpQZWKPjrX7zfnTZOF0wUQnl4qhDLrtbmBFgs9UYhMRLvplrFvrh66k_BFdAgWY484QNpRKVRaYKlyhMgDcwy-i72s9StL_gRnj2j6zybqs5lTpSj4sN4PbSLTrcsu3u0HcabiroHrliIjoClQZdK_XXtiEyaJEnTqo_aZueungU550k4CJgQnhbffQcBL6bA6fCTdbqav2_M9adE-uaOzNzpD-cdS9DqH6rnNib2X4PXvUHhMBS8FG_fs3Kvb3gkF-xLU8OmomKPbuf6GlZiXURsATrmpIdhsOow";

      final data = {
        'data': jsonEncode({
          'invoiceTempDTO': invoiceTempDto.toJson(),
        }),
      };

      // print('Sending data to API: $data');

      final response = await post(
        url: _saveUrl,
        data: data,
        token: accessToken,
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        // if (responseData['err'] != 0) {
        //   return Future.error(responseData['msg'] ?? 'Lỗi không xác định');
        // }
        if(responseData['data'] == null || responseData['data'].isEmpty){
          return InvoiceTempDto(idInvoice: invoiceTempDto.idInvoice,customerCode: invoiceTempDto.customerCode,customerName: invoiceTempDto.customerName,orderCode: invoiceTempDto.orderCode,orderVoucher: invoiceTempDto.orderVoucher,invoiceDate: invoiceTempDto.invoiceDate,taxValue: invoiceTempDto.taxValue,warehouseCode: invoiceTempDto.warehouseCode, ieCategories: invoiceTempDto.ieCategories,content: invoiceTempDto.content,note:invoiceTempDto.note,tongTien: invoiceTempDto.tongTien,thue:invoiceTempDto.thue,poNo: invoiceTempDto.poNo,lookupCode: invoiceTempDto.lookupCode,delivery_date: invoiceTempDto.delivery_date,voucher_code: invoiceTempDto.voucher_code,invoiceDetailTemps: invoiceTempDto.invoiceDetailTemps,exported: invoiceTempDto.exported,isSaved: invoiceTempDto.isSaved);
        }
        try{
          final parsedData = jsonDecode(responseData['data']);
          return InvoiceTempDto.fromJson(parsedData);
        }catch(e){
          print("Error parsing response data:$e");

          return Future.error("Không parse dc : $e");
        }
      } else {
        return Future.error(response.data['message'] ?? 'Lỗi server');
      }
    } catch (e) {
      if (e is DioError) {
        return Future.error(e.response?.data['message'] ?? 'Lỗi kết nối: ${e.message}');
      }
      return Future.error('Lỗi không xác định: $e');
    }
  }

  @override
  Future<void> delete(InvoiceTempDto invoiceTempDto) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<List<InvoiceTempDto>> getAll() {
    // TODO: implement getAll
    throw UnimplementedError();
  }

  @override
  Future<InvoiceTempDto> getOne(double id) {
    // TODO: implement getOne
    throw UnimplementedError();
  }

  @override
  Future<InvoiceTempDto> update(InvoiceTempDto invoiceTempDto) {
    // TODO: implement update
    throw UnimplementedError();
  }
  }

  @override
  Future<void> delete(InvoiceTempDto invoiceTempDto) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<List<InvoiceTempDto>> getAll() {
    // TODO: implement getAll
    throw UnimplementedError();
  }

  @override
  Future<InvoiceTempDto> getOne(double id) {
    // TODO: implement getOne
    throw UnimplementedError();
  }

  @override
  Future<InvoiceTempDto> update(InvoiceTempDto invoiceTempDto) {
    // TODO: implement update
    throw UnimplementedError();
  }












