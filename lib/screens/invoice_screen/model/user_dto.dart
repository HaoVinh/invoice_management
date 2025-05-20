class UserDTO{
  String? username;
  String? fullname;
  String? departmentCode;
  String? departmentName;
  String? token;

  UserDTO({
    this.username,
    this.fullname,
    this.departmentCode,
    this.departmentName,
    this.token,
  });

  factory UserDTO.fromJson(Map<String, dynamic> json) {
    return UserDTO(
      username: json['username'],
      fullname: json['fullname'],
      departmentCode: json['departmentCode'],
      departmentName: json['departmentName'],
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'fullname': fullname,
      'departmentCode': departmentCode,
      'departmentName': departmentName,
      'token': token,
    };
  }

  UserDTO copyWith({
    String? username,
    String? fullname,
    String? departmentCode,
    String? departmentName,
    String? token,
  }) {
    return UserDTO(
      username: username ?? this.username,
      fullname: fullname ?? this.fullname,
      departmentCode: departmentCode ?? this.departmentCode,
      departmentName: departmentName ?? this.departmentName,
      token: token ?? this.token,
    );
  }

  static UserDTO empty() {
    return UserDTO(
      username: '',
      fullname: '',
      departmentCode: '',
      departmentName: '',
      token: '',
    );
  }
}