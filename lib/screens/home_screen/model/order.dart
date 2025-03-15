class Order {
  int? id;
  String? docNumber;
  String? customer;
  String? carNumber;
  String? contactNumber;

  DateTime? modifiedDate;
  DateTime? createdDate;

  Order({
    this.id,
    this.docNumber,
    this.customer,
    this.carNumber,
    this.contactNumber,

    this.modifiedDate,
    this.createdDate,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'],
      docNumber: json['docNumber'],
      customer: json['customer'],
      carNumber: json['carNumber'],
      contactNumber: json['contactNumber'],
      modifiedDate: json['modifiedDate'] != null
          ? DateTime.parse(json['modifiedDate'])
          : null,
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'docNumber': docNumber,
      'customer': customer,
      'carNumber': carNumber,
      'contactNumber': contactNumber,

      'modifiedDate': modifiedDate,
      'createdDate': createdDate,
    };
  }

  @override
  String toString() {
    return 'Branch{id: $id, docNumber: $docNumber, customer: $customer, carNumber: $carNumber, contactNumber: $contactNumber, modifiedDate: $modifiedDate, createdDate: $createdDate}';
  }

  Order copyWith({
    int? id,
    String? docNumber,
    String? customer,
    String? carNumber,
    String? contactNumber,
    int? retailerId,
    DateTime? modifiedDate,
    DateTime? createdDate,
  }) {
    return Order(
      id: id ?? this.id,
      docNumber: docNumber ?? this.docNumber,
      customer: customer ?? this.customer,
      carNumber: carNumber ?? this.carNumber,
      contactNumber: contactNumber ?? this.contactNumber,

      modifiedDate: modifiedDate ?? this.modifiedDate,
      createdDate: createdDate ?? this.createdDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Order &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          docNumber == other.docNumber &&
          customer == other.customer &&
          carNumber == other.carNumber &&
          contactNumber == other.contactNumber &&
          modifiedDate == other.modifiedDate &&
          createdDate == other.createdDate;

  @override
  int get hashCode =>
      id.hashCode ^
      docNumber.hashCode ^
      customer.hashCode ^
      carNumber.hashCode ^
      contactNumber.hashCode ^
      modifiedDate.hashCode ^
      createdDate.hashCode;
}
