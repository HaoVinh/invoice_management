import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:stream_transform/stream_transform.dart' hide Switch;
import 'package:vibration/vibration.dart';
import '../../../constants/contains.dart';
import '../repository/invoice_temp_repository.dart';

class BarcodeScanScreen extends StatefulWidget {
  static const String routeName = '/barcode-scan';

  const BarcodeScanScreen({Key? key}) : super(key: key);

  @override
  _BarcodeScanScreenState createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  bool scanCamera = true;
  final TextEditingController barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  QRViewController? _qrViewController;
  StreamSubscription? _qrSubscription;
  bool _isProcessingScan = false;
  DateTime? _lastScanTime;
  bool _hasCameraPermission = false;

  static const Duration _scanCooldown = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _checkAndRequestCameraPermission();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _barcodeFocusNode.requestFocus());
  }

  Future<void> _checkAndRequestCameraPermission() async {
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final result = await Permission.camera.request();
      setState(() {
        _hasCameraPermission = result.isGranted;
      });
      if (!result.isGranted) {
        Fluttertoast.showToast(
          msg: 'Không có quyền sử dụng camera',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    } else {
      setState(() {
        _hasCameraPermission = true;
      });
    }
  }

  void _playScanSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/Scanner-Beep-Sound.wav'));
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 100);
    }
  }

  void _toggleCamera() async {
    if (_hasCameraPermission) {
      setState(() {
        scanCamera = !scanCamera;
        if (scanCamera) {
          _qrViewController?.resumeCamera();
        } else {
          _barcodeFocusNode.requestFocus();
          _qrViewController?.pauseCamera();
        }
      });
    } else {
      await _checkAndRequestCameraPermission();
    }
  }

  @override
  void dispose() {
    barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _qrViewController?.dispose();
    _qrSubscription?.cancel();
    super.dispose();
  }

  void _processBarcode(String barcode, {bool fromCamera = false}) async {
    if (barcode.isEmpty) return;

    final now = DateTime.now();
    if (_isProcessingScan ||
        (_lastScanTime != null &&
            now.difference(_lastScanTime!) < _scanCooldown)) {
      return;
    }

    _isProcessingScan = true;
    _lastScanTime = now;

    setState(() {
      barcodeController.text = barcode;
    });

    try {
      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);

      String productCodeToSearch = '';

      try {
        final parts = barcode.split('||');

        for (final part in parts) {
          final keyValue = part.split('=');
          if (keyValue.length == 2) {
            final key = keyValue[0].trim();
            final value = keyValue[1].trim();

            if (key == 'productCode') {
              productCodeToSearch = value;
              barcode = productCodeToSearch;
              break;
            }
          }
        }

        if (productCodeToSearch.isNotEmpty) {
          print('Product code tìm được: $productCodeToSearch');

        } else {
          print('Không tìm thấy productCode trong QR');
        }
      } catch (e) {
        print('Lỗi parse QR: $e');
      }
      if (productCodeToSearch.isEmpty) {
        final repo = InvoiceTempRepository();
        final productCodesFromApi =
            await repo.findProductCodeByBarcodeThung(barcode);

        Get.back();

        if (productCodesFromApi.isEmpty) {
          _showErrorSnackbar('Không tìm thấy sản phẩm cho barcode: $barcode');
          return;
        }

        final uniqueCodes = productCodesFromApi.toSet().toList();

        if (uniqueCodes.length == 1) {
          final singleCode = uniqueCodes.first;
          Get.snackbar(
            'Thông tin',
            'Barcode này đang sử dụng cho mã sản phẩm: $singleCode',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.blue.shade700,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
            margin: const EdgeInsets.all(16),
            borderRadius: 12,
            snackStyle: SnackStyle.FLOATING,
            icon: const Icon(Icons.info_rounded, color: Colors.white, size: 28),
          );
        } else {
          final selected = await _showProductSelectionDialog(uniqueCodes);
          if (selected == null) return;

          Get.snackbar(
            'Đã chọn',
            'Mã sản phẩm: $selected',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(16),
            borderRadius: 12,
            snackStyle: SnackStyle.FLOATING,
          );
        }
      }
    } catch (e) {
      Get.back();
      _showErrorSnackbar('Lỗi xử lý QR/Barcode: $e');
    } finally {
      _isProcessingScan = false;
    }


  }

  Future<String?> _showProductSelectionDialog(List<String> productCodes) async {
    if (productCodes.isEmpty) return null;

    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Color(0xFFF0F4F8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_scanner_rounded,
                          color: kPrimaryColor, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chọn sản phẩm',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: kPrimaryColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Barcode này trùng ${productCodes.length} sản phẩm',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Danh sách
                Flexible(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: productCodes.length,
                      itemBuilder: (ctx, index) {
                        final code = productCodes[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pop(context, code),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: kPrimaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.inventory_2_rounded,
                                        color: kPrimaryColor, size: 28),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          code,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Mã sản phẩm',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      color: kPrimaryColor, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child:
                            const Text('Hủy', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorSnackbar(String message) {
    Get.snackbar(
      'Cảnh báo',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.shade700,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      snackStyle: SnackStyle.FLOATING,
    );
  }

  void scannerBarcode(String barcode) => _processBarcode(barcode);

  void scannerBarcodeByCam(String barcode) {
    if (scanCamera) _processBarcode(barcode, fromCamera: true);
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;
    if (scanCamera && _hasCameraPermission) controller.resumeCamera();
    _qrSubscription = controller.scannedDataStream
        .debounce(const Duration(milliseconds: 400))
        .listen((scanData) {
      if (scanData.code != null) {
        scannerBarcodeByCam(scanData.code!);
      }
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      Fluttertoast.showToast(
          msg: 'Không có quyền bật camera',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Quét Barcode'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(scanCamera ? Icons.keyboard : Icons.camera_alt),
            onPressed: _toggleCamera,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (scanCamera && _hasCameraPermission)
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _buildQrView(context),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      right: 20,
                      child: GestureDetector(
                        onTap: _toggleCamera,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeController,
                          focusNode: _barcodeFocusNode,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              _processBarcode(value.trim());
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Quét hoặc nhập mã vạch',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            prefixIcon: Container(
                              margin: const EdgeInsets.only(left: 12, right: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.qr_code_scanner_rounded,
                                  size: 22, color: theme.primaryColor),
                            ),
                            suffixIcon: barcodeController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded,
                                        size: 20, color: Colors.grey.shade500),
                                    onPressed: () => barcodeController.clear(),
                                  )
                                : null,
                          ),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Container(
                          height: 56, width: 1, color: Colors.grey.shade200),
                      GestureDetector(
                        onTap: _toggleCamera,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: scanCamera
                                      ? theme.primaryColor
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  size: 20,
                                  color: scanCamera
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Camera',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: scanCamera
                                      ? theme.primaryColor
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrView(BuildContext context) {
    return QRView(
      key: GlobalKey(debugLabel: 'QR'),
      onQRViewCreated: _onQRViewCreated,
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
      overlay: QrScannerOverlayShape(
        borderColor: Colors.red,
        borderRadius: 12,
        borderLength: 30,
        borderWidth: 10,
        cutOutSize: MediaQuery.of(context).size.width * 0.7,
      ),
      formatsAllowed: const [
        BarcodeFormat.qrcode,
        BarcodeFormat.code128,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.itf,
        BarcodeFormat.pdf417,
        BarcodeFormat.aztec,
        BarcodeFormat.dataMatrix,
      ],
    );
  }
}
