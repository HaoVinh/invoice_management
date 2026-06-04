
class InvoiceDetailTempDto{
   int invoiceDetailId;
   double? quantity;// Số lượng yêu cầu
   String? productCode;
   String? productName;
   double? boxQuantity;// Số lượng thùng/pallet
   double? specification;
   String? productDHCode;
   bool? spchinh;
   double? realQuantity; // Số lượng thực xuất(thùng)
   double? realQuantityDVT; // Số lượng thực xuất (ĐVT)
   double? unit_price;
   int invoiceTempId;
   String? noteBatchCode;
   String? unit;
  InvoiceDetailTempDto({
    required this.invoiceDetailId,
     this.quantity,
     this.productCode,
     this.productName,
     this.boxQuantity,
     this.specification,
     this.productDHCode,
     this.spchinh,
    this.realQuantity,
    this.realQuantityDVT,
    this.unit_price,
    required this.invoiceTempId,
    this.noteBatchCode,
    this.unit,
  });




   factory InvoiceDetailTempDto.fromJson(Map<String, dynamic> json) {
     String? productDHCode = json['productDHCode'];
     return InvoiceDetailTempDto(
       invoiceDetailId: json['invoiceDetailId'],
       quantity: (json['quantity'] != null) ? json['quantity'].toDouble() : null,
       productCode: json['productCode'],
       productName: json['productName'],
       boxQuantity: (json['boxQuantity'] != null) ? json['boxQuantity'].toDouble() : null,
       specification: (json['specification'] != null) ? json['specification'].toDouble() : null,
       productDHCode: productDHCode,
       spchinh: json['spchinh'] != null ? json['spchinh'] as bool : (productDHCode == null), // Ưu tiên json['spchinh']
       unit_price: (json['unit_price'] != null) ? json['unit_price'].toDouble() : null,
       realQuantityDVT: (json['realQuantityDVT'] != null) ? json['realQuantityDVT'].toDouble() : null,
       invoiceTempId: json['invoiceTempId'],
       realQuantity: (json['realQuantity'] != null) ? json['realQuantity'].toDouble() : null,
       noteBatchCode:  json['noteBatchCode'],
       unit: json['unit'],
     );
   }
   Map<String, dynamic> toJson() {
     return {
'invoiceDetailId': invoiceDetailId, 'quantity': quantity,
       'productCode': productCode,
       'productName': productName,
       'boxQuantity': boxQuantity,
       'specification': specification,
       'productDHCode': productDHCode,
       'spchinh': spchinh,
       'realQuantity': realQuantity,
       'realQuantityDVT': realQuantityDVT,
       'unit_price': unit_price,
       'invoiceTempId':invoiceTempId,
       'noteBatchCode': noteBatchCode,
       'unit': unit,
     };
   }
   InvoiceDetailTempDto copyWith({
     int? invoiceDetailId,
     double? quantity,
     String? productCode,
     String? productName,
     double? boxQuantity,
     double? specification,
     String? productDHCode,
     bool? spchinh,
     double? realQuantity,
     double? realQuantityDVT,
     double? unit_price,
     int? invoiceTempId,
     String? noteBatchCode,
     String? unit,
   }) {
     return InvoiceDetailTempDto(
       invoiceDetailId: invoiceDetailId ?? this.invoiceDetailId,
       quantity: quantity ?? this.quantity,
       productCode: productCode ?? this.productCode,
       productName: productName ?? this.productName,
       boxQuantity: boxQuantity ?? this.boxQuantity,
       specification: specification ?? this.specification,
       productDHCode: productDHCode ?? this.productDHCode,
       spchinh: spchinh ?? this.spchinh,
       realQuantity: realQuantity ?? this.realQuantity,
       realQuantityDVT: realQuantityDVT ?? this.realQuantityDVT,
       unit_price:  unit_price ?? this.unit_price,
         invoiceTempId: invoiceTempId ?? this.invoiceTempId,
         noteBatchCode: noteBatchCode ?? this.noteBatchCode,
       unit: unit ?? this.unit,
     );
   }

}

class InvoiceDetailTempResponse {
  final int err;
  final String? msg;
  final List<InvoiceDetailTempDto>? listInvoiceDetailTemps;

  InvoiceDetailTempResponse({
    required this.err,
    this.msg,
    this.listInvoiceDetailTemps,
  });
  factory InvoiceDetailTempResponse.fromJson(Map<String, dynamic> json) {
    print('Raw JSON response: $json'); // Log JSON thô

    List<InvoiceDetailTempDto> details = [];
    final listData = json['dt']['list_invoice_detail_temps'];

    print('list_invoice_detail_temps value: $listData'); // Log giá trị khóa

    if (listData != null) {
      if (listData is List) {
        details = listData
            .map((item) {
          try {
            return InvoiceDetailTempDto.fromJson(item as Map<String, dynamic>);
          } catch (e) {
            print('Error parsing item: $item, error: $e');
            return null;
          }
        })
            .where((item) => item != null)
            .cast<InvoiceDetailTempDto>()
            .toList();
        print('Parsed details: ${details.map((e) => e.toJson())}');
      } else {
        print('list_invoice_detail_temps is not a List: $listData');
      }
    } else {
      print('list_invoice_detail_temps is null or missing');
    }

    return InvoiceDetailTempResponse(
      err: json['err'] ?? json['ret'] ?? -1,
      msg: json['msg']?.toString(),
      listInvoiceDetailTemps: details,
    );
  }
}

  // Map<String, dynamic> toMap() => {
  //   "err": err,
  //   "msg": msg,
  //   "dt": listInvoiceDetailTemps == null
  //       ? null
  //       : List<dynamic>.from(listInvoiceDetailTemps!.map((x) => x.toJson())),
  // };


