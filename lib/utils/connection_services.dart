import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectionServices {
  Future<bool> checkConnection() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      return true;
    }
    return false;
  }

  Future<bool> get isOnline => checkConnection();
}

final connectionServices = ConnectionServices();