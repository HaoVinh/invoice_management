import '../../../constants/env.dart';


class Brand {
  final String key;
  final String value;

  Brand({required this.key, required this.value});

  factory Brand.fromJson(Map<String, dynamic> json) {
    return Brand(
      key: json['key']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'value': value,
    };
  }

  Branch? toBranch() {
    try {
      return Branch.values.firstWhere((b) => b.toString() == key);
    } catch (e) {
      return null;
    }
  }
}