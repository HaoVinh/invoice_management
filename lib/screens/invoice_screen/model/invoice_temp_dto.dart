import 'package:intl/intl.dart';

import 'invoice_detail_temp_dto.dart';

DateTime _parseDateOrNow(dynamic value) {
  if (value == null || value.toString().trim().isEmpty) {
    return DateTime.now();
  }
  final text = value.toString();
  try {
    return DateFormat('dd/MM/yyyy HH:mm:ss').parse(text);
  } catch (_) {
    return DateTime.tryParse(text) ?? DateTime.now();
  }
}

double? _toDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _toIntOrZero(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool _toBoolOrFalse(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  return false;
}

class InvoiceTempDto {
  int idInvoice;
  String? customerCode;
  String? customerName;
  String? orderCode;
  String? orderVoucher;
  DateTime invoiceDate;
  double? taxValue; // Giá trị thuế
  String warehouseCode; // Mã kho
  String ieCategories; // Mã loại xuất/nhập
  String? content = ""; // Nội dung
  String? note = ""; // Ghi chú
  double? tongTien; // Tổng tiền
  double? thue; // Thuế
  String? poNo; // Mã đơn hàng PO
  String? lookupCode = ""; // Mã tra cứu
  DateTime delivery_date;
  String voucher_code;
  int? orderId;
  List<InvoiceDetailTempDto>? invoiceDetailTemps;
  bool exported;
  bool isSaved;
  bool? isExporting;
  String? codeNV;
  String? license_plate;
  String? orderType;
  bool scanonly;
  InvoiceTempDto({
    required this.idInvoice,
    this.customerCode,
    this.customerName,
    this.orderCode,
    this.orderVoucher,
    required this.invoiceDate,
    this.taxValue,
    required this.warehouseCode,
    required this.ieCategories,
    this.content,
    this.note,
    this.tongTien,
    this.thue,
    this.poNo,
    this.lookupCode,
    required this.delivery_date,
    required this.voucher_code,
    this.invoiceDetailTemps,
    this.orderId,
    required this.exported,
    required this.isSaved,
    this.codeNV,
    this.license_plate,
    this.orderType,
   required this.scanonly,
  });

  factory InvoiceTempDto.fromJson(Map<String, dynamic> json) {
    return InvoiceTempDto(
      idInvoice: _toIntOrZero(json['idInvoice']),
      customerCode: json['customerCode']?.toString(),
      customerName: json['customerName']?.toString(),
      orderCode: json['orderCode']?.toString(),
      orderVoucher: json['orderVoucher']?.toString(),
      invoiceDate: _parseDateOrNow(json['invoiceDate']),
      taxValue: _toDoubleOrNull(json['taxValue']),
      warehouseCode: json['warehouseCode']?.toString() ?? '',
      ieCategories: json['ieCategories']?.toString() ?? '',
      content: json['content']?.toString(),
      note: json['note']?.toString(),
      tongTien: _toDoubleOrNull(json['tongTien']),
      thue: _toDoubleOrNull(json['thue']),
      poNo: json['poNo']?.toString(),
      lookupCode: json['lookupCode']?.toString(),
      delivery_date: _parseDateOrNow(json['delivery_date']),
      voucher_code: json['voucher_code']?.toString() ?? '',
      orderId: _toIntOrNull(json['orderId']),
      invoiceDetailTemps: (json['invoiceDetailTemps'] as List<dynamic>?)
          ?.map((e) => InvoiceDetailTempDto.fromJson(e))
          .toList(),
      exported: _toBoolOrFalse(json['exported']),
      isSaved: _toBoolOrFalse(json['isSaved']),
      codeNV: json['codeNV']?.toString(),
      license_plate: json['license_plate']?.toString(),
      orderType: json['orderType']?.toString(),
      scanonly: _toBoolOrFalse(json['scanonly']),
    );
  }
  Map<String, dynamic> toJson() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    return {
      'idInvoice': idInvoice,
      'customerCode': customerCode,
      'customerName': customerName,
      'orderCode': orderCode,
      'orderVoucher': orderVoucher,
      'invoiceDate': dateFormat.format(invoiceDate),
      'taxValue': taxValue,
      'warehouseCode': warehouseCode,
      'ieCategories': ieCategories,
      'content': content,
      'note': note,
      'tongTien': tongTien,
      'thue': thue,
      'poNo': poNo,
      'lookupCode': lookupCode,
      'delivery_date': dateFormat.format(delivery_date),
      'voucher_code': voucher_code,
      'orderId': orderId,
      'invoiceDetailTemps': invoiceDetailTemps?.map((e) => e.toJson()).toList(),
      'exported': exported,
      'isSaved': isSaved,
      'codeNV': codeNV,
      'license_plate': license_plate,
      'orderType': orderType,
      'scanonly': scanonly,
    };
  }

  InvoiceTempDto copyWith({
    int? idInvoice,
    String? customerCode,
    String? customerName,
    String? orderCode,
    String? orderVoucher,
    required DateTime invoiceDate,
    double? taxValue, // Giá trị thuế
    required String warehouseCode, // Mã kho
    required String ieCategories, // Mã loại xuất/nhập
    String? content = "", // Nội dung
    String? note = "", // Ghi chú
    double? tongTien, // Tổng tiền
    double? thue, // Thuế
    String? poNo, // Mã đơn hàng PO
    String? lookupCode = "", // Mã tra cứu
    required DateTime delivery_date,
    required String voucher_code,
    int? orderId,
    required bool exported,
    required bool isSaved,
    String? codeNV,
    String? license_plate,
    String? orderType,
    required bool scanonly,
  }) {
    return InvoiceTempDto(
      idInvoice: idInvoice ?? this.idInvoice,
      customerCode: customerCode ?? this.customerCode,
      customerName: customerName ?? this.customerName,
      orderCode: orderCode ?? this.orderCode,
      orderVoucher: orderVoucher ?? this.orderVoucher,
      invoiceDate: invoiceDate,
      taxValue: taxValue ?? this.taxValue,
      warehouseCode: warehouseCode,
      ieCategories: ieCategories,
      content: content ?? this.content,
      note: note ?? this.note,
      tongTien: tongTien ?? this.tongTien,
      thue: thue ?? this.thue,
      poNo: poNo ?? this.poNo,
      lookupCode: lookupCode ?? this.lookupCode,
      delivery_date: delivery_date,
      voucher_code: voucher_code,
      orderId: orderId,
      exported: exported,
      isSaved: isSaved,
      codeNV: codeNV,
      license_plate: license_plate,
      orderType: orderType,
      scanonly:scanonly,
    );
  }
}

class InvoiceTempResponse {
  InvoiceTempResponse({
    this.err,
    this.msg,
    this.listInvoiceTemps,
  });

  int? err;
  String? msg;
  List<InvoiceTempDto>? listInvoiceTemps;

  factory InvoiceTempResponse.fromJson(Map<String, dynamic> json) {
    print('json["dt"]: ${json["dt"]}');
    print('json["dt"] runtimeType: ${json["dt"].runtimeType}');

    List<InvoiceTempDto>? invoiceTemps;
    if (json['dt'] != null) {
      if (json['dt'] is List) {
        invoiceTemps = (json['dt'] as List)
            .map((e) => InvoiceTempDto.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (json['dt'] is Map) {
        // Lấy list_invoice_temps từ dt
        var dtMap = json['dt'] as Map<String, dynamic>;
        if (dtMap['list_invoice_temps'] != null &&
            dtMap['list_invoice_temps'] is List) {
          invoiceTemps = (dtMap['list_invoice_temps'] as List)
              .map((e) => InvoiceTempDto.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          invoiceTemps = [];
        }
      }
    }

    return InvoiceTempResponse(
      err: json["err"],
      msg: json["msg"],
      listInvoiceTemps: invoiceTemps,
    );
  }

  Map<String, dynamic> toMap() => {
        "err": err,
        "msg": msg,
        "dt": listInvoiceTemps == null
            ? null
            : List<dynamic>.from(listInvoiceTemps!.map((x) => x.toJson())),
      };
}
