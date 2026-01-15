import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../constants/env.dart';
import '../../../repositories/abstract_repository.dart';
import '../model/Brand.dart';
import '../model/LoginDTO.dart';

class AuthRepository extends AbstractRepository {
  Future<Map<String, dynamic>> login(String user, String password, Branch branch) async {
    try {
      // Kiểm tra kết nối mạng
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return {
          'success': false,
          'error': 'Không có kết nối internet. Vui lòng kiểm tra mạng và thử lại.'
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final brandKey = prefs.getString('brand') != null
          ? jsonDecode(prefs.getString('brand')!)['key']
          : '';

      String database;
      switch (brandKey) {
        case 'Brand.HCM':
          database = 'ho chi minh';
          break;
        case 'Brand.BD':
          database = 'binh duong';
          break;
        case 'Brand.BN':
          database = 'bac ninh';
          break;
        default:
          database = 'ho chi minh';
      }

      final params = {
        'user': user,
        'pass': password,
      };

      final client = http.Client();
      try {
        print('Request URL: ${Environment.getBaseUrlForBranch(branch)}/dangnhapapp');
        print('Request params: ${Uri(queryParameters: params).query}');

        final response = await client.post(
          Uri.parse('${Environment.getBaseUrlForBranch(branch)}/dangnhapapp'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: Uri(queryParameters: params).query,
        ).timeout(const Duration(seconds: 10)); // Tăng timeout lên 10s cho ổn định

        print('Login response status: ${response.statusCode}');
        print('Login response body: ${response.body}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> json = jsonDecode(response.body);

          // Kiểm tra xem API có trả access_token không
          final String? tokenFromApi = json['access_token'] as String?;

          if (tokenFromApi == null || tokenFromApi.isEmpty) {
            return {
              'success': false,
              'error': 'Đăng nhập thành công nhưng không nhận được access token từ server.'
            };
          }

          // Lưu token lấy từ API
          await prefs.setString('access_token', tokenFromApi);

          final loginDTO = LoginDTO(
            code: json['code'],
            name: json['name'],
            userName: json['user'],
            pass: json['pass'], // Cẩn thận: không nên lưu pass thật, nhưng nếu cần thì mã hóa
            access_token: tokenFromApi,
          );

          await prefs.setString('member', jsonEncode(loginDTO.toJson()));
          await prefs.setString(
            'brand',
            jsonEncode(
              Brand(
                key: branch.toString(),
                value: Environment.getNameBranch(branch),
              ).toJson(),
            ),
          );

          return {'success': true, 'member': loginDTO};
        } else {
          String errorMessage;
          switch (response.statusCode) {
            case 401:
              errorMessage = 'Sai tên đăng nhập hoặc mật khẩu.';
              break;
            case 404:
              errorMessage = 'Không tìm thấy dịch vụ đăng nhập. Vui lòng kiểm tra chi nhánh.';
              break;
            case 500:
              errorMessage = 'Lỗi máy chủ nội bộ. Vui lòng thử lại sau.';
              break;
            default:
              try {
                final errorJson = jsonDecode(response.body);
                errorMessage = errorJson['message'] ?? 'Lỗi không xác định từ server.';
              } catch (_) {
                errorMessage = 'Lỗi server: ${response.statusCode}';
              }
          }
          return {'success': false, 'error': errorMessage};
        }
      } on TimeoutException {
        return {
          'success': false,
          'error': 'Kết nối quá hạn. Vui lòng kiểm tra mạng và thử lại.'
        };
      } finally {
        client.close();
      }
    } catch (e) {
      print('Login exception: $e');
      String errorMessage = 'Đã xảy ra lỗi không mong muốn. Vui lòng thử lại.';

      if (e is SocketException) {
        errorMessage = 'Không thể kết nối đến máy chủ. Kiểm tra mạng của bạn.';
      } else if (e is FormatException) {
        errorMessage = 'Dữ liệu trả về từ server không hợp lệ.';
      }

      return {'success': false, 'error': errorMessage};
    }
  }

  Future<List<Branch>> getBranches() async {
    final branches = Branch.values.toSet().toList();
    print('Fetched branches: $branches');
    return branches;
  }

  Future<LoginDTO?> getSavedLoginDTO() async {
    final prefs = await SharedPreferences.getInstance();
    final memberStr = prefs.getString('member');
    if (memberStr != null && memberStr.isNotEmpty) {
      try {
        return LoginDTO.fromJson(jsonDecode(memberStr));
      } catch (e) {
        print('Lỗi lưu đăng nhập: $e');
      }
    }
    return null;
  }

  Future<Brand?> getSavedBrand() async {
    final prefs = await SharedPreferences.getInstance();
    final brandStr = prefs.getString('brand');
    print('Saved brand: $brandStr');
    if (brandStr != null && brandStr.isNotEmpty) {
      try {
        return Brand.fromJson(jsonDecode(brandStr));
      } catch (e) {
        print('Lỗi lưu chi nhánh: $e');
      }
    }
    return null;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Lưu thông tin đăng nhập để tự động điền lần sau
  Future<void> saveCredentials({
    required String username,
    required String password,
    required Branch branch,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_username', username);
    await prefs.setString('saved_password', password);
    await prefs.setString('saved_branch', branch.toString());
  }

  /// Lấy thông tin đăng nhập đã lưu
  Future<Map<String, dynamic>?> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('saved_username');
    final password = prefs.getString('saved_password');
    final branchStr = prefs.getString('saved_branch');

    if (username != null && password != null && branchStr != null) {
      Branch? branch;
      for (var b in Branch.values) {
        if (b.toString() == branchStr) {
          branch = b;
          break;
        }
      }
      return {
        'username': username,
        'password': password,
        'branch': branch,
      };
    }
    return null;
  }

  /// Xóa thông tin đăng nhập đã lưu (khi logout nếu cần)
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await prefs.remove('saved_branch');
  }
}