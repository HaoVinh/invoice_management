import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/contains.dart';
class AppUpdateManager {
  static bool _hasCheckUpdated = false;
  static const String updateJsonUrl =
      "http://erp.lixco.com:6065/LixcoResource/resources/appxuatkho/app_update.json";

  static Future<void> checkForUpdate(BuildContext context) async {
    if(_hasCheckUpdated){
      return;
    }

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      return;
    }

    try {
      final response = await http
          .get(Uri.parse(updateJsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;
      final decodedBody = utf8.decode(response.bodyBytes);
      final json = jsonDecode(decodedBody);


      final int serverVersionCode = json['version_code'] ?? 0;
      final String serverVersionName = json['version_name'] ?? "Unknown";
      final String apkUrl = json['apk_url'] ?? "";
      final String releaseNote = json['release_note'] ?? "Có bản cập nhật mới.";
      final bool forceUpdate = json['force_update'] ?? false;

      if (apkUrl.isEmpty) return;

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (serverVersionCode > currentVersionCode) {
        _showUpdateDialog(
          context: context,
          versionName: serverVersionName,
          releaseNote: releaseNote,
          apkUrl: apkUrl,
          forceUpdate: forceUpdate,
          versionCode: serverVersionCode,
        );
      } else if(serverVersionCode == currentVersionCode){
        _showCurrentDialog(
          context: context,
          versionName: serverVersionName,
          releaseNote: releaseNote,
          apkUrl: apkUrl,
          forceUpdate: forceUpdate,
          versionCode: serverVersionCode,
        );
      }
    _hasCheckUpdated = true;
    } catch (e) {
      print("Check update error: $e");
    }
  }

  static void _showUpdateDialog({
    required BuildContext context,
    required String versionName,
    required String releaseNote,
    required String apkUrl,
    required bool forceUpdate,
    required int versionCode,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !forceUpdate,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.system_update, color: Colors.blue, size: 28),
              SizedBox(width: 10),
              Text("Cập nhật mới", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Phiên bản: $versionName", style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: kPrimaryColor,
          ),),
              SizedBox(height: 12),
              Text("Nội dung cập nhật:", style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kPrimaryColor,
              ),),
              SizedBox(height: 6),
              Text(releaseNote, style: TextStyle(fontSize: 14, height: 1.4)),
            ],
          ),
          actions: [
            if (!forceUpdate)
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: Icon(
                  Icons.watch_later,
                  size: 12,
                  color: Colors.white,
                ),
                label: Text(
                  "Để sau",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _downloadAndInstallApk(apkUrl, versionName);
              },
              icon: Icon(
                Icons.download,
                size: 12,
                color: Colors.white,
              ),
              label: Text(
                forceUpdate ? "Cập nhật ngay" : "Tải về",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
  static void _showCurrentDialog({
    required BuildContext context,
    required String versionName,
    required String releaseNote,
    required String apkUrl,
    required bool forceUpdate,
    required int versionCode,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !forceUpdate,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Phiên bản: $versionName", style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kPrimaryColor,
              ),),
              SizedBox(height: 12),

              Text("Đang ở phiên bản mới nhất, vui lòng nhấn Tiếp tục", style: TextStyle(fontSize: 14, height: 1.4)),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Tiếp tục", style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kPrimaryColor,
                ),),
              ),
            ],
          ),

        ),
      ),
    );
  }
  static Future<void> _downloadAndInstallApk(String apkUrl,String versionName) async {
    Get.dialog(
      Center(child: CircularProgressIndicator(color: Colors.green)),
      barrierDismissible: false,
    );

    try {
      final dir = await getExternalStorageDirectory();
      final filePath = "${dir!.path}/app_update_${DateTime.now().millisecondsSinceEpoch}.apk";

      final dio = Dio(
        BaseOptions(
          method: 'GET',
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36",
            "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1",
          },
        ),
      );


      await dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            print("Tải APK: $progress%");
          }
        },
      );
      Get.back(); // Đóng loading

      Get.snackbar(
        "Thành công",
        "Đã tải thành công version $versionName",
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: Duration(seconds: 2),
      );

// Trước khi OpenFile.open
      if (await Permission.requestInstallPackages.isDenied) {
        await Permission.requestInstallPackages.request();
      }
      await OpenFile.open(filePath);
    } catch (e) {
      Get.back();
      Get.snackbar(
        "Lỗi",
        "Không thể tải bản cập nhật: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
    }
  }
}