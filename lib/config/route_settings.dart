//create route settings

import 'package:flutter/material.dart';
import 'package:invoice_management/screens/invoice_screen/pending_sync_screen.dart';
import 'package:invoice_management/screens/invoice_screen/screens/invoice_screen.dart';

import '../screens/screens.dart';

class RouteSettingsWithArguments extends RouteSettings {
  final RouteSettings settings;

  const RouteSettingsWithArguments({
    required this.settings,
  });

  @override
  String? get name => settings.name;

  @override
  dynamic get arguments => settings.arguments;

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case LoginScreen.routeName:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case HomeInvoiceScreen.routeName:
        return MaterialPageRoute(builder: (_) => const HomeInvoiceScreen());
      case InvoiceTempScreen.routeName:
        return MaterialPageRoute(builder: (_) => const InvoiceTempScreen());
      case PendingSyncScreen.routeName:
        return MaterialPageRoute(builder: (_) => const PendingSyncScreen());

      default:
        return MaterialPageRoute(
            builder: (_) => const NotFound(
                  message: '404 NOT FOUND\n'
                      'Không tìm thấy trang này.\n',
                ));
    }
  }
}

class NotFound extends StatelessWidget {
  final String? message;

  const NotFound({Key? key, this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //beautiful 404 page
      body: Container(
        padding:
            EdgeInsets.symmetric(vertical: MediaQuery.of(context).padding.top),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.4, 0.6],
            colors: [
              Colors.green,
              Colors.green.shade200,
            ],
          ),
        ),
        child: Center(
          child: Text(
            message ??
                '404 NOT FOUND\n'
                    'Không tìm thấy trang này.\n',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
