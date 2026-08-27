import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:invoice_management/screens/invoice_screen/barcode_screens/barcode_screen.dart';
import 'package:invoice_management/screens/invoice_screen/core/invoice_detail_temp_bloc.dart';
import 'package:invoice_management/screens/invoice_screen/core/invoice_temp_bloc.dart';
import 'package:invoice_management/screens/invoice_screen/pending_sync_screen.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_detail_temp_repository.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_temp_repository.dart';
import 'package:invoice_management/screens/invoice_screen/screens/invoice_screen.dart';
import '/screens/auth_screen/repository/auth_repostory.dart';

import 'package:url_strategy/url_strategy.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'config/route_settings.dart';
import 'constants/contains.dart';
import 'screens/auth_screen/core/auth_bloc.dart';
import 'screens/screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);


  //rotate the screen
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);



  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint(e.toString());
  }
  setPathUrlStrategy();
  // runApp(
  //   DevicePreview(
  //     enabled: !kReleaseMode,
  //     builder: (context) => const InvoiceManagementApp(), // Wrap your app
  //   ),
  // );
  runApp(const InvoiceManagementApp());
  // runApp(
  //   DevicePreview(
  //     enabled: !kReleaseMode,
  //     // tools: const [
  //     //   ...DevicePreview.defaultTools,
  //     // ],
  //     child: const InvoiceManagementApp(),
  //   ),
  // );
}

class InvoiceManagementApp extends StatefulWidget {
  const InvoiceManagementApp({Key? key}) : super(key: key);

  @override
  State<InvoiceManagementApp> createState() => _InvoiceManagementAppState();
}

class _InvoiceManagementAppState extends State<InvoiceManagementApp> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      void _showToast(String message) {
        Fluttertoast.showToast(
          msg: message,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      }

      if (results.contains(ConnectivityResult.none)) {
        _showToast('Không có  nối mạng');
        _timer = Timer.periodic(const Duration(seconds: 5),
                (t) => _showToast('Không có kết nối mạng'));
      } else {
        Fluttertoast.showToast(
            msg: 'Kết nối thành công',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0);
        _timer?.cancel();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => LoginBloc(AuthRepository())),
        BlocProvider(
          create: (context) =>
              InvoiceTempBloc(InvoiceTempRepository()),
        ),
        BlocProvider(
          create: (context) =>
              InvoiceDetailTempBloc(InvoiceDetailTempRepository()),
        ),
      ],
      child: GetMaterialApp(
        title: 'Đơn hàng LIX',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: ThemeData(
          primaryColor: kPrimaryColor,
          primarySwatch: MaterialColor(kPrimaryColor.value, kPrimaryColorMap),
          textTheme: Theme.of(context).textTheme.apply(
                fontFamily: GoogleFonts.openSans().fontFamily,
                bodyColor: kTextColor,
              ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        darkTheme: ThemeData.dark(),
        // initialRoute: HomeInvoiceScreen.routeName,
        getPages: [
          GetPage(name: HomeInvoiceScreen.routeName, page: () => HomeInvoiceScreen()),
          GetPage(name: InvoiceTempScreen.routeName, page: () => InvoiceTempScreen()),
          GetPage(name: LoginScreen.routeName, page: () => LoginScreen()),
          GetPage(name: BarcodeScanScreen.routeName, page: () => const BarcodeScanScreen()),
          GetPage(name: PendingSyncScreen.routeName, page: () => const PendingSyncScreen()),
        ],
        initialRoute: LoginScreen.routeName,
        onGenerateRoute: RouteSettingsWithArguments.generateRoute,
      ),
    );
  }
}
