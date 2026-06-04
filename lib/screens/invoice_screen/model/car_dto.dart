import 'package:intl/intl.dart';


class CarDTO {
  final int id;
  final DateTime? createdDate;
  final String? license_plate;    // biển số
  final String? driver;          // người lái xe
  final String? phoneNumber;     // số điện thoại
  final String? note;
  final String? idfox;
  final bool disable;

  CarDTO({
    required this.id,
    this.createdDate,
    this.license_plate,
    this.driver,
    this.phoneNumber,
    this.note,
    this.idfox,
    required this.disable,
  });

  factory CarDTO.fromJson(Map<String, dynamic> json) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

    return CarDTO(
      id: json['id'] as int? ?? 0,
      createdDate: json['createdDate'] != null
          ? dateFormat.parse(json['createdDate'].toString())
          : null,
      license_plate: json['license_plate']?.toString(),
      driver: json['driver']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      note: json['note']?.toString(),
      idfox: json['idfox']?.toString(),
      disable: json['disable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

    return {
      'id': id,
      'createdDate': createdDate != null ? dateFormat.format(createdDate!) : null,
      'license_plate': license_plate,
      'driver': driver,
      'phoneNumber': phoneNumber,
      'note': note,
      'idfox': idfox,
      'disable': disable,
    };
  }

  CarDTO copyWith({
    int? id,
    DateTime? createdDate,
    String? license_plate,
    String? driver,
    String? phoneNumber,
    String? note,
    String? idfox,
    bool? disable,
  }) {
    return CarDTO(
      id: id ?? this.id,
      createdDate: createdDate ?? this.createdDate,
      license_plate: license_plate ?? this.license_plate,
      driver: driver ?? this.driver,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      note: note ?? this.note,
      idfox: idfox ?? this.idfox,
      disable: disable ?? this.disable,
    );
  }
}