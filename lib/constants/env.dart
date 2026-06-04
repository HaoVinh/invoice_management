

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Branch { HCM, BD, BN }

const Map<Branch, String> _branchSubdomains = {
  Branch.HCM: "192.168.0.6",
  // Branch.BD: "192.168.0.83",
  Branch.BN: "192.168.20.253",

  // Branch.HCM: "192.168.0.83",
  // Branch.HCM: "192.168.0.83:8096",

  Branch.BD: "192.168.10.11",
};

const Map<Branch, String> _branchPorts = {
  // Branch.HCM: "8089",
  Branch.BD: "8480",
  Branch.HCM: "8980",
  // Branch.HCM: "8099",
  // Branch.BD: "8089",
  Branch.BN: "8980",
};

class Environment {
  static Branch _currentBranch = Branch.HCM;

  static String get currentSubdomain => _branchSubdomains[_currentBranch]!;
  static String get currentPort => _branchPorts[_currentBranch]!;

  // baseDomain động theo branch
  static String get baseDomain => "http://$currentSubdomain";

  // baseUrl động theo branch
  static String get baseUrl => "$baseDomain:$currentPort/consumption/api";

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
        return "Hồ Chí Minh";
      case Branch.BD:
        return "Bình Dương";
      case Branch.BN:
        return "Bắc Ninh";
    }
  }

  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  static Future<void> initBranch() async {
    final prefs = await SharedPreferences.getInstance();
    final branchSelected = prefs.getString('selectedBranch');

    if (branchSelected != null) {
      _currentBranch = Branch.values.firstWhere(
            (b) => b.toString() == branchSelected,
        orElse: () => Branch.HCM,
      );
    }
    // Thông báo cho các widget lắng nghe nếu cần
    _notifyListeners();
  }

  static Future<void> switchBranch(Branch branch) async {
    _currentBranch = branch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedBranch', branch.toString());
    _notifyListeners(); // Thông báo thay đổi cho toàn bộ app
  }

  // Hàm tiện ích lấy baseUrl theo branch bất kỳ
  static String getBaseUrlForBranch(Branch branch) {
    final subdomain = _branchSubdomains[branch]!;
    final port = _branchPorts[branch]!;
    return "http://$subdomain:$port/consumption/api";
  }
}