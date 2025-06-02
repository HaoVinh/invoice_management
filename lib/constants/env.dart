//baseUrl
// const String baseUrl = "http://192.168.0.248:8088/VanPhongPham_WEB/api";
// const String baseUrl = "http://192.168.0.226:64/luongvp/api";
// const String baseDomain = "http://erp.lixco.com:91";
import 'package:shared_preferences/shared_preferences.dart';

const String baseDomain = "http://192.168.0.83:7500";
// const String baseDomain = "http://192.168.0.83:8089";
const String baseUrl = "$baseDomain/consumption/api";


class Environment {
  //
  // static String get centerUrl => "$baseUrl/invoicetemp";

  static final List<Function()> _listeners = [];

  static void addListener(Function() listener) {
    _listeners.add(listener);
  }

  static void removeListener(Function() listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }



}


