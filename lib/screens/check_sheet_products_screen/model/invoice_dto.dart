
class Invoice{
  int?id;
String? productCode;
String? name;
int? quantity;
int? realQuantity;
int? boxQuantity;

Invoice ({
  required this.id,
  required this.productCode,
  required this.name,
  required this.quantity,
  required this.realQuantity,
  required this.boxQuantity,
});

factory Invoice.fromJson(Map<String, dynamic> json) {
  return Invoice(
    id: json['id'],
    productCode: json['productCode'],
    name: json['name'],
    realQuantity: json['realQuantity'] ?? 0,
    boxQuantity: json['boxQuantity'] ?? 0,
    quantity: json['quantity'] ?? 0,
  );
}

}

