class LoginDTO {
  final String? userName;
  final String? code;
  final String? name;
  final String? pass;
  final String? access_token;
  final int? expires_in;
  final String? token_type;

  LoginDTO({this.userName, this.code, this.name,this.pass, this.access_token, this.expires_in, this.token_type});

  factory LoginDTO.fromJson(Map<String, dynamic> json) {
    return LoginDTO(
      userName: json['userName'],
      code: json['code'],
      name: json['name'],
      pass: json['pass'],
      access_token: json['access_token'],
      expires_in: json['expires_in'],
      token_type: json['token_type'],
    );
  }

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'code': code,
    'name': name,
    'pass':pass,
    'access_token': access_token,
    'expires_in': expires_in,
    'token_type': token_type,
  };
}