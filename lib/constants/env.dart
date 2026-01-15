//baseUrl
// const String baseUrl = "http://192.168.0.248:8088/VanPhongPham_WEB/api";
// const String baseUrl = "http://192.168.0.226:64/luongvp/api";
// const String baseDomain = "http://erp.lixco.com:91";
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
enum Branch { HCM, BD, BN }
// const String baseDomain = "http://192.168.0.98:8082";
const String baseDomain = "http://192.168.0.6:8980";
// const String baseDomain = "https://dev1.lixco.vn";
const String baseUrl = "$baseDomain/consumption/api";
// const String baseUrl = "https://dev1.lixco.vn/consumption/api";
Branch _currentBranch = Branch.HCM;
const Map<Branch, String> _branchPorts = {
  Branch.HCM: "8980",
  // Branch.HCM: "8089",
  Branch.BD: "8480",
  Branch.BN: "8980",
};
const Map<Branch, String> _branchSubdomains = {
  Branch.HCM: "192.168.0.6",
  // Branch.HCM: "192.168.0.83",
  // Branch.HCM: "192.168.0.83:8096",

  Branch.BD: "192.168.10.11",
  Branch.BN: "192.168.20.253",
};

class Environment {
  static String get baseUrl => "${_branchSubdomains[_currentBranch]}:${_branchPorts[_currentBranch]}/consumption/api";
  // static String get baseUrl => "https://dev1.lixco.vn/consumption/api";
  static final DateFormat dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

  static final List<Function()> _listeners = [];

  static void addListener(Function() listener) {
    _listeners.add(listener);
  }

  static void removeListener(Function() listener) {
    _listeners.remove(listener);
  }
  static String getNameBranch(Branch branch) {
    switch (branch) {
      case Branch.HCM:
        return "hồ chí minh";
      case Branch.BD:
        return "bình dương";
      case Branch.BN:
        return "bắc ninh";
    }
  }
  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }
  static Future<void> initBranch() async {
    final prefs = await SharedPreferences.getInstance();
    final branchSelected = prefs.getString('selectedBranch') ?? Branch.HCM.toString();
    _currentBranch = Branch.values.firstWhere(
          (b) => b.toString() == branchSelected,
      orElse: () => Branch.HCM,
    );
  }

  static Future<void> switchBranch(Branch branch) async {
    _currentBranch = branch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedBranch', branch.toString());
    _notifyListeners();
  }

  static String getBaseUrlForBranch(Branch branch) {
    return "http://${_branchSubdomains[branch]}:${_branchPorts[branch]}/consumption/api";
  }


}


