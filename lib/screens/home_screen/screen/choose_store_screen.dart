import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invoice_management/constants/colors.dart';
import 'package:invoice_management/screens/auth_screen/core/auth_bloc.dart';
import '../../../utils/secure_storage.dart';
import '../../auth_screen/model/auth_response.dart';
import '../../check_sheet_products_screen/screens/invoice_screen.dart';
import '/screens/home_screen/repository/order_repository.dart';

import '../../../constants/contains.dart';
import '../../screens.dart';

class ChooseStoreScreen extends StatefulWidget {
  static const String routeName = '/choose-store-screen';

  const ChooseStoreScreen({Key? key}) : super(key: key);

  @override
  State<ChooseStoreScreen> createState() => _ChooseStoreScreenState();
}

class _ChooseStoreScreenState extends State<ChooseStoreScreen> {
  late OrderRepository _orderRepository;
  var data = {
    "total": 4,
    "pageSize": 20,
    "data": [
      {
        "id": 16413,
        "customer": "555 KINGMART 108",
        "docNumber": "108 BẠCH ĐẰNG",
        "carNumber": "",
        "modifiedDate": "2018-10-25T15:17:08.0130000",
        "createdDate": "2016-09-19T11:03:17.9200000"
      },
      {
        "id": 80204,
        "customer": "KHO TỔNG",
        "docNumber": "141a Trần Hưng Đạo",
        "carNumber": "",
        "modifiedDate": "2021-06-07T14:58:46.5500000",
        "createdDate": "2018-04-28T00:35:12.3030000"
      },
      {
        "id": 80203,
        "customer": "KING KONG 141",
        "docNumber": "141A TRẦN HƯNG ĐẠO",
        "carNumber": "",
        "modifiedDate": "2021-09-10T15:20:11.9530000",
        "createdDate": "2018-04-28T00:34:19.9700000"
      }
    ],
    "timestamp": "2022-12-15T14:45:19.4208364+07:00"
  };
  var _logoutStatus = '';

  var _dataDecode = [];

  @override
  void initState() {
    _orderRepository = OrderRepository();
    decodeData();
    super.initState();
  }

  decodeData() {
    _dataDecode = jsonDecode(jsonEncode(data))['data'];
  }


  DateTime? currentBackPressTime;

  _handleWillPop() async {
    final now = DateTime.now();
    final backButtonHasNotBeenPressedOrSnackBarHasBeenClosed =
        currentBackPressTime == null ||
            now.difference(currentBackPressTime!) > const Duration(seconds: 2);

    if (backButtonHasNotBeenPressedOrSnackBarHasBeenClosed) {
      currentBackPressTime = now;
      Get.snackbar(
        'Thông báo',
        'Nhấn lần nữa để thoát',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        margin: const EdgeInsets.all(10),
        borderRadius: 10,
        snackStyle: SnackStyle.FLOATING,
        animationDuration: const Duration(milliseconds: 300),
        duration: const Duration(seconds: 2),
        icon: const Icon(
          Icons.info,
          color: Colors.white,
        ),
        mainButton: TextButton(
          onPressed: () {
            Get.back();
          },
          child: const Icon(
            Icons.close,
            color: Colors.white,
          ),
        ),
      );
      return false;
    }
    SystemNavigator.pop();
    return null;
  }

  _handleLogout() {
    _logoutStatus = '';
    Get.snackbar(
      'Thông báo',
      'Đang đăng xuất',
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      margin: const EdgeInsets.all(10),
      borderRadius: 10,
      snackStyle: SnackStyle.FLOATING,
      animationDuration: const Duration(milliseconds: 300),
      duration: const Duration(seconds: 2),
      icon: const Icon(
        Icons.info,
        color: Colors.white,
      ),
      progressIndicatorValueColor:
          const AlwaysStoppedAnimation<Color>(Colors.green),
      mainButton: TextButton(
        onPressed: () {
          _logoutStatus = 'CANCEL';
          Get.back();
        },
        child: const Text("Huỷ", style: TextStyle(color: Colors.white)),
      ),
      showProgressIndicator: true,
      progressIndicatorBackgroundColor: Colors.white,
      snackbarStatus: (status) {
        if (status == SnackbarStatus.CLOSED && _logoutStatus != 'CANCEL') {
          BlocProvider.of<AuthBloc>(context).add(LogOutEvent());
          Get.offAllNamed(AuthScreen.routeName);
        }
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách đơn hàng', style: TextStyle(color: Colors.white)),
        backgroundColor: appColor,
        foregroundColor: primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => decodeData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
          //Quay lại đăng nhập
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
          ),
        ],
        //No back icon
        automaticallyImplyLeading: false,
      ),
      //ListView
      body: WillPopScope(
        onWillPop: () => _handleWillPop(),
        child: SafeArea(
          child: _listView(context, _dataDecode),
        ),
      ),
    );
  }

  _listView(BuildContext context, List<dynamic> data) {
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (context, index) {
        return _listTile(context, data[index]);
      },
    );
  }

  _listTile(BuildContext context, data) {
    var item = data;
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.grey.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(kDefaultPadding / 2.5),
        child: ListTile(
          onTap: () => {
          Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OrderFormScreen()),
          ),},
          key: ValueKey(item['id']),
          style: ListTileStyle.list,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          title: RichText(
            text: TextSpan(
              text: item['customer'],
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),

            ),
          ),

        ),
      ),
    );
  }
}
