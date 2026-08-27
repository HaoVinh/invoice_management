import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlkit;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:stream_transform/stream_transform.dart' hide Switch;
import 'package:vibration/vibration.dart';
import '../../../constants/contains.dart';
import '../repository/invoice_temp_repository.dart';

const _kScanDebounce = Duration(milliseconds: 80);
const _kScanCooldown = Duration(milliseconds: 120);
const _kDuplicateScanWindow = Duration(milliseconds: 1600);
const _kScanSoundAsset = 'sounds/Scanner-Beep-Sound.wav';
const _kBarcodeFormats = [
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
];

class BarcodeScanScreen extends StatefulWidget {
  static const String routeName = '/barcode-scan';

  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  bool scanCamera = true;
  final TextEditingController barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'BarcodeQR');
  QRViewController? _qrViewController;
  StreamSubscription? _qrSubscription;
  bool _isProcessingScan = false;
  String? _lastProcessedBarcode;
  DateTime? _lastProcessedAt;
  String? _lastNoticeKey;
  DateTime? _lastNoticeAt;
  bool _hasCameraPermission = false;
  final AudioPlayer _scanSoundPlayer = AudioPlayer();
  final InvoiceTempRepository _invoiceTempRepo = InvoiceTempRepository();
  final Map<String, List<String>> _barcodeProductCodesCache = {};
  final ImagePicker _imagePicker = ImagePicker();
  final mlkit.BarcodeScanner _barcodeImageScanner = mlkit.BarcodeScanner();

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
        _showManagedSnackbar(
          'Lỗi',
          'Không có quyền sử dụng camera',
          backgroundColor: Colors.red.shade700,
        );
      }
    } else {
      setState(() {
        _hasCameraPermission = true;
      });
    }
  }

  void _playScanSound() async {
    await _scanSoundPlayer.stop();
    await _scanSoundPlayer.play(AssetSource(_kScanSoundAsset));
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
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
    _scanSoundPlayer.dispose();
    _barcodeImageScanner.close();
    super.dispose();
  }

  bool _canShowNotice(String key, Duration minInterval) {
    final now = DateTime.now();
    if (_lastNoticeKey == key &&
        _lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < minInterval) {
      return false;
    }
    _lastNoticeKey = key;
    _lastNoticeAt = now;
    return true;
  }

  void _showManagedSnackbar(
    String title,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(milliseconds: 2200),
    Icon? icon,
  }) {
    final key = '$title|$message';
    if (!_canShowNotice(key, const Duration(milliseconds: 450))) return;
    Get.closeCurrentSnackbar();
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: backgroundColor ?? kPrimaryColor,
      colorText: Colors.white,
      duration: duration,
      margin: const EdgeInsets.all(16),
      borderRadius: 14,
      snackStyle: SnackStyle.FLOATING,
      icon: icon,
    );
  }

  String? _extractProductCodeFromQR(String raw) {
    try {
      for (final part in raw.split('||')) {
        final keyValue = part.split('=');
        if (keyValue.length == 2 && keyValue[0].trim() == 'productCode') {
          return keyValue[1].trim();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>> _lookupProductCodesByBarcode(String barcode) async {
    final cacheKey = barcode.trim();
    if (_barcodeProductCodesCache.containsKey(cacheKey)) {
      return _barcodeProductCodesCache[cacheKey]!;
    }
    final codes =
        await _invoiceTempRepo.findProductCodeByBarcodeThung(cacheKey);
    final uniqueCodes = codes.toSet().toList();
    _barcodeProductCodesCache[cacheKey] = uniqueCodes;
    return uniqueCodes;
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      if (!_hasCameraPermission && mounted) {
        setState(() => _hasCameraPermission = true);
      }
      return true;
    }

    final result = await Permission.camera.request();
    if (mounted) {
      setState(() => _hasCameraPermission = result.isGranted);
    }
    if (!result.isGranted) {
      _showManagedSnackbar(
        'Lỗi',
        'Không có quyền sử dụng camera',
        backgroundColor: Colors.red.shade700,
      );
    }
    return result.isGranted;
  }

  Future<List<String>> _extractBarcodesFromImage(mlkit.InputImage image) async {
    final barcodes = await _barcodeImageScanner.processImage(image);
    return barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .where((value) => value != null && value.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
  }

  Future<void> _captureBarcodeImage() async {
    if (!await _ensureCameraPermission()) return;

    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 65,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (file == null) return;

      _showOcrProcessingDialog('Đang nhận diện barcode...');
      final image = mlkit.InputImage.fromFilePath(file.path);
      final barcodeCandidates = await _extractBarcodesFromImage(image);
      if (Get.isDialogOpen == true) Get.back();

      if (barcodeCandidates.isEmpty) {
        _showErrorSnackbar(
            'Không thấy mã vạch trong ảnh. Vui lòng chụp rõ phần barcode.');
        return;
      }

      if (barcodeCandidates.length == 1) {
        await _processBarcode(barcodeCandidates.first);
        return;
      }

      final selected = await _showBarcodeSelectionDialog(barcodeCandidates);
      if (selected != null) {
        await _processBarcode(selected);
      }
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      _showErrorSnackbar('Không đọc được hình ảnh: $e');
    }
  }

  void _showOcrProcessingDialog(String message) {
    Get.dialog(
      Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  void _prepareManualBarcodeInputForNextScan() {
    barcodeController.clear();
    if (scanCamera) return;

    void focusIfNeeded() {
      if (!mounted || scanCamera) return;
      if (!_barcodeFocusNode.hasFocus) _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }

    focusIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) => focusIfNeeded());
    Future.delayed(const Duration(milliseconds: 120), focusIfNeeded);
    Future.delayed(const Duration(milliseconds: 350), focusIfNeeded);
  }

  Future<void> _processBarcode(String barcode,
      {bool fromCamera = false}) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return;
    if (_isProcessingScan) {
      return;
    }

    final now = DateTime.now();
    final isDuplicateCameraScan = fromCamera &&
        _lastProcessedBarcode == trimmed &&
        _lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < _kDuplicateScanWindow;
    if (isDuplicateCameraScan) return;

    _isProcessingScan = true;
    _lastProcessedBarcode = trimmed;
    _lastProcessedAt = now;

    setState(() {
      barcodeController.text = trimmed;
    });

    try {
      _playScanSound();
      _showManagedSnackbar(
        'Đã nhận diện barcode',
        '$trimmed\nĐang tra mã SP...',
        backgroundColor: Colors.blue.shade700,
        icon: const Icon(Icons.qr_code_scanner_rounded,
            color: Colors.white, size: 26),
      );

      final productCodeFromQr = _extractProductCodeFromQR(trimmed);
      if (productCodeFromQr != null && productCodeFromQr.isNotEmpty) {
        _showManagedSnackbar(
          'Đã nhận diện barcode',
          '$trimmed\nMã SP: $productCodeFromQr',
          backgroundColor: Colors.green,
          icon: const Icon(Icons.check_circle_outline_rounded,
              color: Colors.white, size: 26),
        );
        return;
      }

      final uniqueCodes = await _lookupProductCodesByBarcode(trimmed);
      if (uniqueCodes.isEmpty) {
        _showErrorSnackbar('Không tìm thấy sản phẩm cho barcode: $trimmed');
        return;
      }

      if (uniqueCodes.length == 1) {
        final singleCode = uniqueCodes.first;
        _showManagedSnackbar(
          'Thông tin',
          'Barcode này đang sử dụng cho mã sản phẩm: $singleCode',
          backgroundColor: Colors.green,
          icon: const Icon(Icons.info_rounded, color: Colors.white, size: 26),
        );
      } else {
        final selected = await _showProductSelectionDialog(uniqueCodes);
        if (selected == null) return;
        _showManagedSnackbar(
          'Đã chọn',
          'Mã sản phẩm: $selected',
          backgroundColor: Colors.green,
          icon: const Icon(Icons.check_circle_outline_rounded,
              color: Colors.white, size: 26),
        );
      }
    } catch (e) {
      _showErrorSnackbar('Lỗi xử lý QR/Barcode: $e');
    } finally {
      if (fromCamera) await Future.delayed(_kScanCooldown);
      _lastProcessedAt = DateTime.now();
      _isProcessingScan = false;
      if (!fromCamera) _prepareManualBarcodeInputForNextScan();
    }
  }

  Future<String?> _showProductSelectionDialog(List<String> productCodes) async {
    if (productCodes.isEmpty) return null;

    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
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
                  color: Colors.black.withValues(alpha: 0.25),
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
                    color: kPrimaryColor.withValues(alpha: 0.1),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded,
                          color: kPrimaryColor, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
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
                                      color:
                                          kPrimaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.inventory_2_rounded,
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
                                  const Icon(Icons.arrow_forward_ios_rounded,
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

  Future<String?> _showBarcodeSelectionDialog(List<String> barcodes) async {
    if (barcodes.isEmpty) return null;

    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.1),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.document_scanner_rounded,
                          color: kPrimaryColor, size: 30),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Đã nhận diện barcode',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    itemCount: barcodes.length,
                    itemBuilder: (_, index) {
                      final barcode = barcodes[index];
                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.qr_code_2_rounded,
                              color: kPrimaryColor),
                          title: Text(
                            barcode,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded,
                              color: kPrimaryColor, size: 18),
                          onTap: () => Navigator.pop(context, barcode),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
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
    _showManagedSnackbar(
      'Cảnh báo',
      message,
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.error_outline_rounded,
          color: Colors.white, size: 26),
    );
  }

  Future<void> scannerBarcode(String barcode) => _processBarcode(barcode);

  Future<void> scannerBarcodeByCam(String barcode) async {
    if (scanCamera) await _processBarcode(barcode, fromCamera: true);
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;
    if (scanCamera && _hasCameraPermission) controller.resumeCamera();
    bool processing = false;
    _qrSubscription = controller.scannedDataStream
        .debounce(_kScanDebounce)
        .listen((scanData) async {
      if (scanData.code == null || scanData.code!.isEmpty || processing) {
        return;
      }
      processing = true;
      try {
        await scannerBarcodeByCam(scanData.code!);
      } finally {
        processing = false;
      }
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      _showManagedSnackbar(
        'Lỗi',
        'Không có quyền bật camera',
        backgroundColor: Colors.red.shade700,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Quét barcode'),
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
                flex:
                    MediaQuery.of(context).orientation == Orientation.landscape
                        ? 2
                        : 3,
                child: _buildCameraPanel(context),
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
                        color: Colors.black.withValues(alpha: 0.06),
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
                          keyboardType: TextInputType.none,
                          textInputAction: TextInputAction.done,
                          onTap: () {
                            SystemChannels.textInput
                                .invokeMethod('TextInput.hide');
                          },
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              _processBarcode(value.trim());
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Quét mã vạch',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            prefixIcon: Container(
                              margin: const EdgeInsets.only(left: 12, right: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    theme.primaryColor.withValues(alpha: 0.1),
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

  Widget _buildCameraPanel(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final isTablet = screen.shortestSide >= 600;
    final isLandscape = screen.width > screen.height;

    return Container(
      margin: EdgeInsets.all(isLandscape ? 10 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 260;

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildQrView(
                  context,
                  panelWidth: constraints.maxWidth,
                  panelHeight: constraints.maxHeight,
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: compact ? 7 : 9),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code_scanner_rounded,
                                  color: Colors.white, size: 17),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isTablet
                                      ? 'Khung quét rộng cho tablet'
                                      : 'Đang quét barcode',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _toggleCamera,
                        child: Container(
                          width: compact ? 36 : 40,
                          height: compact ? 36 : 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Icon(Icons.keyboard_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!compact) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.center_focus_strong_rounded,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Giữ barcode trong khung, app sẽ quét lại sau 1.6 giây nếu không đổi camera',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      GestureDetector(
                        onTap: _captureBarcodeImage,
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: compact ? 9 : 11),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.document_scanner_rounded,
                                  color: kPrimaryColor, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Chụp barcode',
                                style: TextStyle(
                                  color: kPrimaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact)
                  Positioned(
                    right: 14,
                    top: 60,
                    child: GestureDetector(
                      onTap: _captureBarcodeImage,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.document_scanner_rounded,
                            color: kPrimaryColor, size: 20),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildQrView(
    BuildContext context, {
    required double panelWidth,
    required double panelHeight,
  }) {
    final screen = MediaQuery.of(context).size;
    final isTablet = screen.shortestSide >= 600;
    final isLandscape = screen.width > screen.height;
    final heightCutOutLimit =
        panelHeight * (isLandscape ? 0.58 : (isTablet ? 0.74 : 0.68));
    final widthCutOutLimit = panelWidth * (isTablet ? 0.78 : 0.74);
    final maxCutOut = heightCutOutLimit < widthCutOutLimit
        ? heightCutOutLimit
        : widthCutOutLimit;
    final preferredMinCutOut = isLandscape ? 150.0 : (isTablet ? 280.0 : 180.0);
    final minCutOut =
        maxCutOut < preferredMinCutOut ? maxCutOut : preferredMinCutOut;
    final preferredCutOut = panelWidth * (isTablet ? 0.72 : 0.68);
    final cutOutSize = preferredCutOut < minCutOut
        ? minCutOut
        : preferredCutOut > maxCutOut
            ? maxCutOut
            : preferredCutOut;
    final compact = panelHeight < 260;

    return QRView(
      key: _qrKey,
      onQRViewCreated: _onQRViewCreated,
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
      overlay: QrScannerOverlayShape(
        borderColor: kPrimaryColor,
        borderRadius: 14,
        borderLength: compact ? 26 : 34,
        borderWidth: compact ? 7 : 9,
        cutOutSize: cutOutSize,
      ),
      formatsAllowed: _kBarcodeFormats,
    );
  }
}
