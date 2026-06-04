import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:stream_transform/stream_transform.dart' hide Switch;
import 'package:vibration/vibration.dart';
import 'package:video_player/video_player.dart';
import '../../../constants/contains.dart';
import '../core/invoice_detail_temp_bloc.dart';
import '../core/invoice_detail_temp_event.dart';
import '../core/invoice_detail_temp_state.dart';
import '../model/invoice_detail_temp_dto.dart';
import '../model/invoice_temp_dto.dart';
import '../repository/invoice_detail_temp_repository.dart';
import '../repository/invoice_temp_repository.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kScanDebounce = Duration(milliseconds: 400);
const _kScanCooldown = Duration(milliseconds: 800);
const _kDuplicateScanWindow = Duration(milliseconds: 1400);
const _kLockDurationNormal = 1500;
const _kLockDurationError = 3000;
const _kTutorialSeenKey = 'has_seen_invoice_tutorial';
const _kTutorialDontShowKey = 'dont_show_invoice_tutorial_again';
const _kVideoAsset = 'assets/video/huong_dan_quet_barcode.mp4';
const _kScanSoundAsset = 'sounds/Scanner-Beep-Sound.wav';

enum PalletMode { palletChan, palletLe, leDonViTinh }

extension PalletModeExt on PalletMode {
  String get label {
    switch (this) {
      case PalletMode.palletChan:
        return 'Chẵn Pallet';
      case PalletMode.palletLe:
        return 'Lẻ Pallet';
      case PalletMode.leDonViTinh:
        return 'Lẻ ĐVT';
    }
  }

  IconData get icon {
    switch (this) {
      case PalletMode.palletChan:
        return Icons.grid_view_rounded;
      case PalletMode.palletLe:
        return Icons.view_module_outlined;
      case PalletMode.leDonViTinh:
        return Icons.straighten_rounded;
    }
  }
}

enum _AiAlertSeverity { warning, blocker }

String _formatQuantityInput(num? value) {
  if (value == null) return '0';
  if (value % 1 == 0) return value.toInt().toString();
  return value
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _AiInvoiceAlert {
  final _AiAlertSeverity severity;
  final String title;
  final String message;
  final String? productCode;

  const _AiInvoiceAlert({
    required this.severity,
    required this.title,
    required this.message,
    this.productCode,
  });
}

// ─── Item Controller Cache ────────────────────────────────────────────────────

/// Holds controllers for one InvoiceDetailTempDto row.
class _ItemControllers {
  final TextEditingController qty;
  final TextEditingController qtyDVT;
  final TextEditingController batchCode;

  _ItemControllers({
    required String initialQty,
    required String initialQtyDVT,
    required String initialBatch,
  })  : qty = TextEditingController(text: initialQty),
        qtyDVT = TextEditingController(text: initialQtyDVT),
        batchCode = TextEditingController(text: initialBatch);

  void dispose() {
    qty.dispose();
    qtyDVT.dispose();
    batchCode.dispose();
  }

  void sync(InvoiceDetailTempDto item) {
    qty.text = _formatQuantityInput(item.realQuantity);
    qtyDVT.text = _formatQuantityInput(item.realQuantityDVT);
    batchCode.text = item.noteBatchCode ?? '';
  }
}

class InvoiceTempScreen extends StatefulWidget {
  static const String routeName = '/invoice-screen';
  const InvoiceTempScreen({Key? key}) : super(key: key);

  @override
  _InvoiceTempScreenState createState() => _InvoiceTempScreenState();
}

class _InvoiceTempScreenState extends State<InvoiceTempScreen> {
  // ── UI state ──
  bool _cameraActive = true;
  bool _showOrderTable = true;
  bool _showPromoTable = true;
  bool _hasScan = false;
  bool _isLoading = false;
  bool _showTutorialBot = true;
  bool _dontShowAgain = false;
  bool _isVideoInitialized = false;
  PalletMode? _palletMode = PalletMode.palletChan;

  // ── Scan state ──
  bool _isProcessingScan = false;
  bool _isScanLocked = false;
  bool _hasShownError = false;
  bool _isFromTypeAheadSelection = false;
  String? _lastScannedCode;
  String? _lastProcessedBarcode;
  DateTime? _lastProcessedAt;
  Timer? _scanLockTimer;

  // ── Data ──
  InvoiceTempDto? _invoiceData;
  List<InvoiceDetailTempDto> _mainProducts = [];
  List<InvoiceDetailTempDto> _promoProducts = [];

  /// Single source of truth. mainProducts + promoProducts are derived views.
  List<InvoiceDetailTempDto> get _allItems =>
      [..._mainProducts, ..._promoProducts];

  // ── Controllers / keys ──
  final TextEditingController _customerNameCtrl = TextEditingController();
  TextEditingController _barcodeCtrl = TextEditingController();
  FocusNode _barcodeFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  final GlobalKey _mainSectionKey = GlobalKey(debugLabel: 'MainSection');
  final GlobalKey _promoSectionKey = GlobalKey(debugLabel: 'PromoSection');
  final GlobalKey _firstMainKey = GlobalKey(debugLabel: 'FirstMain');
  final GlobalKey _firstPromoKey = GlobalKey(debugLabel: 'FirstPromo');

  // ── Repositories / storage ──
  final _storage = const FlutterSecureStorage();
  final _detailRepo = InvoiceDetailTempRepository();
  final _invoiceTempRepo = InvoiceTempRepository();

  // ── QR ──
  QRViewController? _qrCtrl;
  StreamSubscription? _qrSub;

  // ── Video ──
  late VideoPlayerController _videoCtrl;

  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();

  // ── Per-row controller cache ──
  // Key = productCode, rebuilt whenever list changes.
  final Map<String, _ItemControllers> _mainCtrlCache = {};
  final Map<String, _ItemControllers> _promoCtrlCache = {};

  double _safeSpecification(InvoiceDetailTempDto item) {
    final spec = item.specification ?? 1;
    return spec == 0 ? 1 : spec;
  }

  double _requestedQuantityDVT(InvoiceDetailTempDto item) {
    return item.quantity ?? 0;
  }

  String _formatQty(num value) {
    return _formatQuantityInput(value);
  }

  double _parseQty(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0.0;
  }

  int _enteredItemCount(List<InvoiceDetailTempDto> items) {
    return items
        .where((e) => (e.realQuantity ?? 0) > 0 || (e.realQuantityDVT ?? 0) > 0)
        .length;
  }

  double _itemProgress(InvoiceDetailTempDto item) {
    final requested = _requestedQuantityDVT(item);
    if (requested <= 0) return 0;
    return ((item.realQuantityDVT ?? 0) / requested).clamp(0.0, 1.0);
  }

  List<_AiInvoiceAlert> _analyzeItem(
    InvoiceDetailTempDto item, {
    bool includeMissing = false,
  }) {
    final alerts = <_AiInvoiceAlert>[];
    final requestedDVT = _requestedQuantityDVT(item);
    final actualDVT = item.realQuantityDVT ?? 0;
    final productCode = item.productCode;
    final productName = item.productName ?? productCode ?? 'Sản phẩm';

    if (requestedDVT <= 0) return alerts;

    if (actualDVT > requestedDVT) {
      alerts.add(_AiInvoiceAlert(
        severity: _AiAlertSeverity.blocker,
        title: 'Vượt số lượng yêu cầu',
        message:
            '$productName đang ${_formatQty(actualDVT)} ĐVT, vượt SLYC ${_formatQty(requestedDVT)} ĐVT.',
        productCode: productCode,
      ));
    }

    // if (_palletMode != PalletMode.leDonViTinh &&
    //     actualDVT > 0 &&
    //     actualQty > 0) {
    //   final expectedDVT = actualQty * spec;
    //   // if ((expectedDVT - actualDVT).abs() >= 1) {
    //   //   alerts.add(_AiInvoiceAlert(
    //   //     severity: _AiAlertSeverity.warning,
    //   //     title: 'Lệch quy cách thùng/ĐVT',
    //   //     message:
    //   //         '$productName có SL thùng x quy cách = ${_formatQty(expectedDVT)} ĐVT nhưng đang nhập ${_formatQty(actualDVT)} ĐVT.',
    //   //     productCode: productCode,
    //   //   ));
    //   // }
    // }

    if (includeMissing && actualDVT <= 0) {
      alerts.add(_AiInvoiceAlert(
        severity: _AiAlertSeverity.blocker,
        title: 'Chưa xuất sản phẩm',
        message: '$productName chưa có số lượng thực xuất.',
        productCode: productCode,
      ));
    } else if (includeMissing && actualDVT < requestedDVT) {
      alerts.add(_AiInvoiceAlert(
        severity: _AiAlertSeverity.blocker,
        title: 'Chưa đủ số lượng',
        message:
            '$productName còn thiếu ${_formatQty(requestedDVT - actualDVT)} ĐVT.',
        productCode: productCode,
      ));
    }

    if (item.spchinh == true &&
        actualDVT > 0 &&
        (item.noteBatchCode == null || item.noteBatchCode!.trim().isEmpty)) {
      alerts.add(_AiInvoiceAlert(
        severity: _AiAlertSeverity.warning,
        title: 'Thiếu mã lô hàng',
        message: '$productName đã nhập số lượng nhưng chưa có mã lô.',
        productCode: productCode,
      ));
    }

    return alerts;
  }

  void _showAiWarningForItem(InvoiceDetailTempDto item) {
    _AiInvoiceAlert? alert;
    for (final itemAlert in _analyzeItem(item)) {
      if (itemAlert.severity == _AiAlertSeverity.warning) {
        alert = itemAlert;
        break;
      }
    }
    if (alert == null) return;

    Get.snackbar(
      'Cảnh báo: ${alert.title}',
      alert.message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange.shade700,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      snackStyle: SnackStyle.FLOATING,
      icon: const Icon(Icons.psychology_alt_rounded,
          color: Colors.white, size: 28),
    );
  }

  Map<String, num> _invoiceSummaryNumbers() {
    final totalItems = _allItems.length;
    final enteredItems = _enteredItemCount(_allItems);
    final requestedDVT = _allItems.fold<num>(
        0, (sum, item) => sum + _requestedQuantityDVT(item));
    final actualDVT = _allItems.fold<num>(
        0, (sum, item) => sum + (item.realQuantityDVT ?? 0));
    final completedItems = _allItems
        .where((item) =>
            _requestedQuantityDVT(item) > 0 &&
            (item.realQuantityDVT ?? 0) >= _requestedQuantityDVT(item))
        .length;
    final missingItems = _allItems
        .where(
            (item) => (item.realQuantityDVT ?? 0) < _requestedQuantityDVT(item))
        .length;
    final overItems = _allItems
        .where(
            (item) => (item.realQuantityDVT ?? 0) > _requestedQuantityDVT(item))
        .length;

    return {
      'totalItems': totalItems,
      'enteredItems': enteredItems,
      'completedItems': completedItems,
      'missingItems': missingItems,
      'overItems': overItems,
      'requestedDVT': requestedDVT,
      'actualDVT': actualDVT,
      'progress': totalItems == 0 ? 0 : completedItems / totalItems,
    };
  }

  Future<bool?> _showInvoiceSummaryDialog({bool canContinue = false}) async {
    _flushControllersToItems();
    final summary = _invoiceSummaryNumbers();
    final missing = _allItems
        .where(
            (item) => (item.realQuantityDVT ?? 0) < _requestedQuantityDVT(item))
        .take(6)
        .toList();
    final alerts = _allItems
        .expand((item) => _analyzeItem(item, includeMissing: true))
        .toList();

    return showDialog<bool>(
      context: context,
      barrierDismissible: !canContinue,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.summarize_rounded, color: Color(0xFF00A859)),
            SizedBox(width: 10),
            Expanded(child: Text('Tóm tắt hóa đơn')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _buildSummaryMetric('Đã thực hiện',
                            '${summary['completedItems']}/${summary['totalItems']}')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildSummaryMetric(
                            'Còn thiếu', '${summary['missingItems']}')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildSummaryMetric(
                            'SLYC ĐVT', _formatQty(summary['requestedDVT']!))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildSummaryMetric(
                            'Thực xuất', _formatQty(summary['actualDVT']!))),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (summary['progress'] as num).toDouble(),
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF00A859)),
                  ),
                ),
                if (alerts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'AI phát hiện ${alerts.length} cảnh báo',
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...missing.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.pending_actions_rounded,
                            color: Colors.orange),
                        title: Text(item.productCode ?? '',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            'Thiếu ${_formatQty(_requestedQuantityDVT(item) - (item.realQuantityDVT ?? 0))} ĐVT'),
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(canContinue ? 'Kiểm tra lại' : 'Đóng'),
          ),
          if (canContinue)
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hoàn thành'),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  String? _extractBatchFromOcr(String text) {
    final patterns = [
      RegExp(r'(?:LOT|BATCH|LO|LÔ|MA LO|MÃ LÔ)\s*[:\-]?\s*([A-Z0-9\-\/]+)',
          caseSensitive: false),
      RegExp(r'\b([A-Z]{1,4}\d{4,}[\-\/]?[A-Z0-9]*)\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  double? _extractQuantityFromOcr(String text) {
    final match = RegExp(
            r'(?:SL|QTY|SO LUONG|SỐ LƯỢNG)\s*[:\-]?\s*(\d+(?:[.,]\d+)?)',
            caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  List<String> _extractBarcodeCandidatesFromOcr(String text) {
    final candidates = <String>[];
    final labeledPatterns = [
      RegExp(r'(?:BARCODE|MA VACH|MÃ VẠCH|EAN|UPC)\s*[:\-]?\s*([A-Z0-9\-]+)',
          caseSensitive: false),
      RegExp(r'\b(\d{8,14})\b'),
      RegExp(r'\b([A-Z0-9]{6,30})\b', caseSensitive: false),
    ];

    for (final pattern in labeledPatterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(1)?.trim().replaceAll(RegExp(r'\s+'), '');
        if (value != null && value.length >= 6) candidates.add(value);
      }
    }

    return candidates.toSet().take(8).toList();
  }

  Future<({String barcode, String productCode})?> _findProductFromOcrBarcode(
      String text) async {
    final barcodeCandidates = _extractBarcodeCandidatesFromOcr(text);
    for (final barcode in barcodeCandidates) {
      final codesFromApi =
          await _invoiceTempRepo.findProductCodeByBarcodeThung(barcode);
      if (codesFromApi.isEmpty) continue;

      final matched = _allItems
          .where((e) => codesFromApi.contains(e.productCode))
          .map((e) => e.productCode!)
          .toSet()
          .toList();
      if (matched.isEmpty) continue;

      final selected = matched.length == 1
          ? matched.first
          : await _showProductSelectionDialog(matched);
      if (selected == null) return null;
      return (barcode: barcode, productCode: selected);
    }
    return null;
  }

  Future<void> _captureOcrImage() async {
    if (!await _ensureCameraPermission()) return;
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (file == null) return;

      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);
      final image = InputImage.fromFilePath(file.path);
      final recognizedText = await _textRecognizer.processImage(image);
      if (Get.isDialogOpen == true) Get.back();

      await _handleOcrResult(recognizedText.text);
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      _showErrorSnackbar('Không đọc được hình ảnh: $e');
    }
  }

  Future<void> _handleOcrResult(String text) async {
    if (text.trim().isEmpty) {
      _showErrorSnackbar('Không nhận diện được chữ trong ảnh');
      return;
    }

    final product = await _findProductFromOcrBarcode(text);
    final batchCode = _extractBatchFromOcr(text);
    final qtyDVT = _extractQuantityFromOcr(text);

    if (product == null) {
      await _showOcrPreviewDialog(text, null, null, batchCode, qtyDVT);
      return;
    }

    final productCode = product.productCode;
    final item = _allItems.firstWhere(
        (e) => e.productCode?.toLowerCase() == productCode.toLowerCase());
    final apply = await _showOcrPreviewDialog(
        text, item, product.barcode, batchCode, qtyDVT);
    if (apply != true) return;

    final cache = item.spchinh == false ? _promoCtrlCache : _mainCtrlCache;
    final ctrl = cache[item.productCode ?? ''];
    if (ctrl != null) {
      if (batchCode != null && batchCode.isNotEmpty && item.spchinh == true) {
        ctrl.batchCode.text = batchCode;
        item.noteBatchCode = batchCode;
      }
      if (qtyDVT != null && qtyDVT <= _requestedQuantityDVT(item)) {
        ctrl.qtyDVT.text = _formatQty(qtyDVT);
        _onQtyDVTChanged(item, ctrl, _requestedQuantityDVT(item));
      }
    }

    final idx = _allItems.indexWhere(
        (e) => e.productCode?.toLowerCase() == productCode.toLowerCase());
    if (idx >= 0) _bringToTop(idx);
    Get.snackbar('OCR/AI camera', 'Đã nhận diện $productCode',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white);
  }

  Future<bool?> _showOcrPreviewDialog(
    String rawText,
    InvoiceDetailTempDto? item,
    String? barcode,
    String? batchCode,
    double? qtyDVT,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.document_scanner_rounded, color: Color(0xFF00A859)),
            SizedBox(width: 10),
            Expanded(child: Text('OCR/AI camera')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sản phẩm: ${item?.productCode ?? 'Chưa khớp'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Barcode: ${barcode ?? 'Không thấy/không khớp'}'),
              const SizedBox(height: 6),
              Text('Mã lô: ${batchCode ?? 'Không thấy'}'),
              Text(
                  'Số lượng ĐVT: ${qtyDVT == null ? 'Không thấy' : _formatQty(qtyDVT)}'),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(rawText,
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Đóng')),
          if (item != null)
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Áp dụng')),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _invoiceData = Get.arguments as InvoiceTempDto?;
    if (_invoiceData != null) {
      _customerNameCtrl.text = _invoiceData!.customerName ?? '';
      _loadInvoiceDetails();
    } else {
      _isLoading = false;
      Get.snackbar('Lỗi', 'Dữ liệu hóa đơn không hợp lệ',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _barcodeFocus.requestFocus());
    _checkTutorialStatus();
    _initVideo();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _customerNameCtrl.dispose();
    _barcodeCtrl.dispose();
    _barcodeFocus.dispose();
    _qrCtrl?.dispose();
    _qrSub?.cancel();
    _scanLockTimer?.cancel();
    _videoCtrl.dispose();
    _textRecognizer.close();
    _disposeControllerCache(_mainCtrlCache);
    _disposeControllerCache(_promoCtrlCache);
    super.dispose();
  }

  void _disposeControllerCache(Map<String, _ItemControllers> cache) {
    for (final c in cache.values) c.dispose();
    cache.clear();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tutorial
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkTutorialStatus() async {
    final dontShow = await _storage.read(key: _kTutorialDontShowKey);
    if (mounted) {
      setState(() {
        _dontShowAgain = dontShow == 'true';
        _showTutorialBot = !_dontShowAgain;
      });
    }
  }

  Future<void> _markTutorialAsSeen() async {
    if (_dontShowAgain) {
      await Future.wait([
        _storage.write(key: _kTutorialDontShowKey, value: 'true'),
        _storage.write(key: _kTutorialSeenKey, value: 'true'),
      ]);
    }
    if (mounted) setState(() => _showTutorialBot = false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Video
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initVideo() async {
    _videoCtrl = VideoPlayerController.asset(_kVideoAsset);
    try {
      await _videoCtrl.initialize();
      if (mounted) setState(() => _isVideoInitialized = true);
    } catch (e) {
      debugPrint('Video init error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data loading
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadInvoiceDetails() async {
    setState(() => _isLoading = true);

    final key = 'invoice_temp_${_invoiceData!.idInvoice}';
    final storedJson = await _storage.read(key: key);

    if (storedJson != null && storedJson.isNotEmpty) {
      try {
        final list = (jsonDecode(storedJson) as List)
            .map(
                (j) => InvoiceDetailTempDto.fromJson(j as Map<String, dynamic>))
            .toList();
        _applyItems(list, fromCache: true);
        Get.snackbar('Thông báo', 'Đã tải hóa đơn tạm từ bộ nhớ',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.blue,
            colorText: Colors.white);
        return;
      } catch (_) {
        await _storage.delete(key: key);
      }
    }

    final completedKey = 'invoice_completed_${_invoiceData!.idInvoice}';
    final completedJson = await _storage.read(key: completedKey);
    if (_invoiceData?.isSaved == true &&
        completedJson != null &&
        completedJson.isNotEmpty) {
      try {
        final list = (jsonDecode(completedJson) as List)
            .map(
                (j) => InvoiceDetailTempDto.fromJson(j as Map<String, dynamic>))
            .toList();
        _applyItems(list);
        return;
      } catch (_) {
        await _storage.delete(key: completedKey);
      }
    }

    try {
      final details = await _detailRepo.searchInvoiceDetail(
        cm: 'list_invoice_detail_temps',
        idInvoice: _invoiceData!.idInvoice,
      );
      _applyItems(details);
    } catch (e) {
      debugPrint('Load error: $e');
    }
    _mergeDuplicatePromos();
  }

  /// Central method to update product lists + rebuild controller caches.
  void _applyItems(List<InvoiceDetailTempDto> items, {bool fromCache = false}) {
    final main = items.where((e) => e.spchinh == true).toList();
    final promo = items.where((e) => e.spchinh == false).toList();

    _rebuildCache(_mainCtrlCache, main);
    _rebuildCache(_promoCtrlCache, promo);

    setState(() {
      _mainProducts = main;
      _promoProducts = promo;
      if (fromCache) _invoiceData?.isExporting = true;
      _isLoading = false;
    });
  }

  void _rebuildCache(
      Map<String, _ItemControllers> cache, List<InvoiceDetailTempDto> items) {
    final newKeys = items.map((e) => e.productCode ?? '').toSet();

    // Remove stale entries
    cache.keys.where((k) => !newKeys.contains(k)).toList().forEach((k) {
      cache.remove(k)?.dispose();
    });

    // Add / update entries
    for (final item in items) {
      final code = item.productCode ?? '';
      if (code.isEmpty) continue;
      if (cache.containsKey(code)) {
        cache[code]!.sync(item);
      } else {
        cache[code] = _ItemControllers(
          initialQty: _formatQty(item.realQuantity ?? 0),
          initialQtyDVT: _formatQty(item.realQuantityDVT ?? 0),
          initialBatch: item.noteBatchCode ?? '',
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Promo dedup
  // ─────────────────────────────────────────────────────────────────────────

  void _mergeDuplicatePromos() {
    if (_promoProducts.length <= 1) return;

    final merged = <String, InvoiceDetailTempDto>{};
    for (final item in _promoProducts) {
      final code = (item.productCode ?? '').trim();
      if (code.isEmpty) continue;
      if (merged.containsKey(code)) {
        final ex = merged[code]!;
        ex.quantity = (ex.quantity ?? 0) + (item.quantity ?? 0);
        ex.realQuantity = (ex.realQuantity ?? 0) + (item.realQuantity ?? 0);
        ex.realQuantityDVT =
            (ex.realQuantityDVT ?? 0) + (item.realQuantityDVT ?? 0);
        ex.noteBatchCode ??= item.noteBatchCode;
      } else {
        merged[code] = InvoiceDetailTempDto.fromJson(item.toJson());
      }
    }

    _applyItems([..._mainProducts, ...merged.values]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions / camera
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (!status.isGranted) await Permission.camera.request();
    return (await Permission.camera.status).isGranted;
  }

  Future<void> _enableBarcodeScanner() async {
    if (!await _ensureCameraPermission()) return;
    setState(() {
      _cameraActive = true;
      _qrCtrl?.resumeCamera();
      _barcodeFocus.unfocus();
    });
  }

  void _enableManualInput() {
    setState(() {
      _cameraActive = false;
      _qrCtrl?.pauseCamera();
      _barcodeFocus.requestFocus();
    });
  }

  Future<void> _showScanOptions() async {
    await Get.bottomSheet(
      SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded,
                    color: Color(0xFF00A859)),
                title: const Text('Quét barcode'),
                subtitle: const Text('Dùng camera để quét barcode'),
                onTap: () {
                  Get.back();
                  _enableBarcodeScanner();
                },
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_rounded,
                    color: Color(0xFF00A859)),
                title: const Text('Chụp barcode'),
                subtitle: const Text('Dùng camera để nhận diện barcode'),
                onTap: () {
                  Get.back();
                  _captureOcrImage();
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.keyboard_rounded, color: Colors.grey.shade700),
                title: const Text('Nhập tay'),
                subtitle: const Text('Tắt camera để nhập mã bằng bàn phím'),
                onTap: () {
                  Get.back();
                  _enableManualInput();
                },
              ),
            ],
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scan / barcode logic
  // ─────────────────────────────────────────────────────────────────────────

  void _playScanSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource(_kScanSoundAsset));
    if (await Vibration.hasVibrator() ?? false)
      Vibration.vibrate(duration: 100);
  }

  Future<void> _processBarcode(String barcode,
      {bool fromCamera = false}) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty || _isProcessingScan || _isScanLocked) return;

    final now = DateTime.now();
    final isDuplicateCameraScan = fromCamera &&
        _lastProcessedBarcode == trimmed &&
        _lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < _kDuplicateScanWindow;
    if (isDuplicateCameraScan) return;

    _isProcessingScan = true;
    _lastProcessedBarcode = trimmed;
    _lastProcessedAt = now;

    _barcodeFocus.unfocus();

    try {
      if (_palletMode == null) {
        Fluttertoast.showToast(
          msg: 'Chưa chọn hình thức',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.orange,
          textColor: Colors.white,
        );
        return;
      }

      if (mounted) {
        setState(() {
          _barcodeCtrl.text = trimmed;
          _hasScan = true;
        });
      }

      if (fromCamera) {
        await _processCameraScan(trimmed);
      } else {
        await _processManualInput(trimmed);
      }
    } finally {
      if (fromCamera) await Future.delayed(_kScanCooldown);
      _isProcessingScan = false;
    }
  }

  Future<void> _processCameraScan(String raw) async {
    Get.dialog(const Center(child: CircularProgressIndicator()),
        barrierDismissible: false);

    try {
      final productCode = _extractProductCodeFromQR(raw);
      if (productCode != null && productCode.isNotEmpty) {
        _handleFoundProduct(productCode, updateQty: true);
      } else {
        await _handleBarcodeBoxScan(raw);
      }
    } catch (e) {
      _showErrorSnackbar('QR/Barcode không hợp lệ: $e');
    } finally {
      if (Get.isDialogOpen == true) Get.back();
    }
  }

  Future<void> _processManualInput(String code) async {
    final idx = _allItems.indexWhere(
      (e) => e.productCode?.toLowerCase() == code.toLowerCase(),
    );
    if (idx == -1) {
      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);
      await _handleBarcodeBoxScan(code);
      return;
    }
    final item = _allItems[idx];
    final isPromo = item.spchinh == false;

    setState(() => _lastScannedCode = code);
    _bringToTop(idx);
    _mergeDuplicatePromos();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      setState(() {
        if (isPromo)
          _showPromoTable = true;
        else
          _showOrderTable = true;
      });
      _scrollToSection(
        isPromo ? _firstPromoKey : _firstMainKey,
        isPromo ? _promoSectionKey : _mainSectionKey,
      );
    });
  }

  Future<void> _handleBarcodeBoxScan(String barcode) async {
    final codesFromApi =
        await _invoiceTempRepo.findProductCodeByBarcodeThung(barcode);
    if (Get.isDialogOpen == true) Get.back();

    if (codesFromApi.isEmpty) {
      _showErrorSnackbar('Không tìm thấy sản phẩm cho barcode: $barcode');
      return;
    }

    final matched = _allItems
        .where((e) => codesFromApi.contains(e.productCode))
        .map((e) => e.productCode!)
        .toSet()
        .toList();

    if (matched.isEmpty) {
      _showErrorSnackbar('Barcode này không có sản phẩm nào trong đơn hàng');
      return;
    }

    final selected = matched.length == 1
        ? matched.first
        : await _showProductSelectionDialog(matched);

    if (selected == null) return;
    _handleFoundProduct(selected, updateQty: true);
  }

  void _handleFoundProduct(String code, {required bool updateQty}) {
    final all = _allItems;
    final idx = all
        .indexWhere((e) => e.productCode?.toLowerCase() == code.toLowerCase());
    if (idx == -1) {
      _showErrorSnackbar('Không tìm thấy sản phẩm từ QR trong đơn hàng');
      return;
    }

    if (updateQty && !_updateQuantities(all[idx])) return;

    _bringToTop(idx);
    _playScanSound();
    _isFromTypeAheadSelection = false;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      final isPromo = all[idx].spchinh == false;
      setState(() {
        _showOrderTable = true;
        _showPromoTable = true;
      });
      _scrollToSection(
        isPromo ? _firstPromoKey : _firstMainKey,
        isPromo ? _promoSectionKey : _mainSectionKey,
      );
    });
  }

  /// Returns true if quantities were updated successfully.
  bool _updateQuantities(InvoiceDetailTempDto item) {
    final spec = _safeSpecification(item);
    final maxDVT = _requestedQuantityDVT(item);

    double newQty = item.realQuantity ?? 0;
    double newQtyDVT = item.realQuantityDVT ?? 0;

    switch (_palletMode) {
      case PalletMode.palletChan:
        newQty += (item.boxQuantity ?? 1);
        newQtyDVT = newQty * spec;
        break;
      case PalletMode.palletLe:
        newQty += 1;
        newQtyDVT = newQty * spec;
        break;
      case PalletMode.leDonViTinh:
        newQtyDVT += 1;
        newQty = newQtyDVT / spec;
        break;
      case null:
        return false;
    }

    if (newQtyDVT > maxDVT) {
      _showErrorSnackbar(
          'Số lượng thực tế (ĐVT) không được vượt quá SLYC: ${_formatQty(maxDVT)}');
      return false;
    }

    item.realQuantity = newQty;
    item.realQuantityDVT = newQtyDVT;

    // Sync controllers
    final codeKey = item.productCode ?? '';
    final cache = (item.spchinh == true) ? _mainCtrlCache : _promoCtrlCache;
    cache[codeKey]?.sync(item);
    _showAiWarningForItem(item);

    return true;
  }

  void _bringToTop(int indexInAll) {
    final all = _allItems;
    final item = all[indexInAll];
    final isPromo = item.spchinh == false;

    setState(() {
      _lastScannedCode = item.productCode;
      if (isPromo) {
        _promoProducts.removeWhere((e) => e.productCode == item.productCode);
        _promoProducts.insert(0, item);
      } else {
        _mainProducts.removeWhere((e) => e.productCode == item.productCode);
        _mainProducts.insert(0, item);
      }
    });
  }

  String? _extractProductCodeFromQR(String qr) {
    try {
      for (final part in qr.split('||')) {
        final kv = part.split('=');
        if (kv.length == 2 && kv[0].trim() == 'productCode') {
          final code = kv[1].trim();
          _barcodeCtrl.text = code;
          return code;
        }
      }
    } catch (e) {
      debugPrint('QR parse error: $e');
    }
    return null;
  }

  void _lockScanAfterError({bool longLock = false}) {
    _isProcessingScan = false;
    _isScanLocked = true;
    _scanLockTimer?.cancel();
    _scanLockTimer = Timer(
      Duration(
          milliseconds: longLock ? _kLockDurationError : _kLockDurationNormal),
      () {
        if (!mounted) return;
        _isScanLocked = false;
        _hasShownError = false;
      },
    );
    _barcodeCtrl.clear();
  }

  void _showErrorSnackbar(String message) {
    if (_hasShownError) return;
    _hasShownError = true;
    Get.snackbar(
      'Lỗi',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.shade700,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      snackStyle: SnackStyle.FLOATING,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      icon: const Icon(Icons.error_outline_rounded,
          color: Colors.white, size: 28),
      shouldIconPulse: true,
      isDismissible: true,
    );
    _lockScanAfterError(longLock: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // QR camera
  // ─────────────────────────────────────────────────────────────────────────

  void _onQRViewCreated(QRViewController controller) {
    _qrCtrl = controller;
    if (_cameraActive) controller.resumeCamera();

    bool processing = false;
    _qrSub = controller.scannedDataStream
        .debounce(_kScanDebounce)
        .listen((data) async {
      if (data.code == null || data.code!.isEmpty || processing) return;
      processing = true;
      try {
        if (_cameraActive) await _processBarcode(data.code!, fromCamera: true);
      } finally {
        processing = false;
      }
    });
  }

  void _onPermissionSet(BuildContext ctx, QRViewController ctrl, bool p) {
    if (!p) {
      Fluttertoast.showToast(
          msg: 'Không có quyền bật camera',
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Save actions
  // ─────────────────────────────────────────────────────────────────────────

  bool _flushControllersToItems() {
    for (final item in _allItems) {
      final code = item.productCode ?? '';
      final ctrl =
          item.spchinh == false ? _promoCtrlCache[code] : _mainCtrlCache[code];
      if (ctrl == null) continue;

      final qty = _parseQty(ctrl.qty.text);
      final qtyDVT = _parseQty(ctrl.qtyDVT.text);
      final maxDVT = _requestedQuantityDVT(item);
      final calcDVT = qty * _safeSpecification(item);
      final realDVT = qtyDVT > 0 ? qtyDVT : calcDVT;

      if (realDVT > maxDVT || calcDVT > maxDVT) {
        Get.snackbar('Lỗi',
            'Sản phẩm "${item.productName}" vượt số lượng yêu cầu: ${_formatQty(maxDVT)} ĐVT',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 3));
        return false;
      }

      item.realQuantity = qtyDVT > 0 ? qtyDVT / _safeSpecification(item) : qty;
      item.realQuantityDVT = realDVT;
      final batch = ctrl.batchCode.text.trim();
      item.noteBatchCode = batch.isEmpty ? null : batch;
    }
    return true;
  }

  Future<bool> _confirmAiAlertsBeforeSave(
      {required bool includeMissing}) async {
    if (!_flushControllersToItems()) return false;

    final alerts = _allItems
        .expand((item) => _analyzeItem(item, includeMissing: includeMissing))
        .toList();
    if (alerts.isEmpty) return true;

    final blockers =
        alerts.where((e) => e.severity == _AiAlertSeverity.blocker).toList();
    if (blockers.isNotEmpty) {
      await _showAiAlertsDialog(
        title: 'Phát hiện lỗi cần xử lý',
        alerts: blockers,
        canContinue: false,
      );
      return false;
    }

    final continueSave = await _showAiAlertsDialog(
      title: 'Cảnh báo trước khi hoàn thành',
      alerts: alerts,
      canContinue: true,
    );
    return continueSave == true;
  }

  Future<bool?> _showAiAlertsDialog({
    required String title,
    required List<_AiInvoiceAlert> alerts,
    required bool canContinue,
  }) {
    final displayAlerts = alerts.take(8).toList();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.psychology_alt_rounded,
                color: canContinue ? Colors.orange : Colors.red),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...displayAlerts.map((alert) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      alert.severity == _AiAlertSeverity.blocker
                          ? Icons.error_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: alert.severity == _AiAlertSeverity.blocker
                          ? Colors.red
                          : Colors.orange,
                    ),
                    title: Text(alert.title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(alert.message),
                  )),
              if (alerts.length > displayAlerts.length)
                Text(
                    'Còn ${alerts.length - displayAlerts.length} cảnh báo khác.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(canContinue ? 'Kiểm tra lại' : 'Đóng'),
          ),
          if (canContinue)
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Vẫn lưu'),
            ),
        ],
      ),
    );
  }

  void _saveTempLocal() async {
    if (_mainProducts.isEmpty && _promoProducts.isEmpty) {
      Get.snackbar('Lỗi', 'Chưa có sản phẩm nào để lưu',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
      return;
    }

    if (!await _confirmAiAlertsBeforeSave(includeMissing: false)) return;

    setState(() {
      _invoiceData?.isExporting = true;
      _invoiceData?.isSaved = false;
    });

    final key = 'invoice_temp_${_invoiceData!.idInvoice}';
    try {
      await _storage.write(
        key: key,
        value: jsonEncode(_allItems.map((e) => e.toJson()).toList()),
      );
      Get.back(result: {'action': 'temp_saved'});
      Get.snackbar('Thành công', 'Đã lưu tạm thành công',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Lỗi', 'Lưu tạm thất bại: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  void _saveInvoiceDetailTemp() async {
    if (!await _confirmAiAlertsBeforeSave(includeMissing: true)) return;
    if (await _showInvoiceSummaryDialog(canContinue: true) != true) return;

    setState(() => _invoiceData?.isSaved = false);
    context
        .read<InvoiceDetailTempBloc>()
        .add(SaveInvoiceDetailTempEvent(_allItems));
  }

  Future<void> _savePendingCompletionLocal(String reason) async {
    if (_invoiceData == null) return;
    final id = _invoiceData!.idInvoice;
    final idsJson = await _storage.read(key: 'pending_completed_invoices');
    final ids = <String>{};
    if (idsJson != null && idsJson.isNotEmpty) {
      try {
        ids.addAll(List<String>.from(jsonDecode(idsJson)));
      } catch (_) {}
    }
    ids.add(id.toString());
    await Future.wait([
      _storage.write(
        key: 'pending_completed_invoices',
        value: jsonEncode(ids.toList()),
      ),
      _storage.write(
        key: 'invoice_pending_complete_$id',
        value: jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'reason': reason,
          'items': _allItems.map((e) => e.toJson()).toList(),
        }),
      ),
    ]);
  }

  Future<void> _saveCompletedSnapshotLocal() async {
    if (_invoiceData == null) return;
    await _storage.write(
      key: 'invoice_completed_${_invoiceData!.idInvoice}',
      value: jsonEncode(_allItems.map((e) => e.toJson()).toList()),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scroll
  // ─────────────────────────────────────────────────────────────────────────

  void _scrollToSection(GlobalKey firstItemKey, GlobalKey sectionKey) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = firstItemKey.currentContext ?? sectionKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final offset = (box.localToGlobal(Offset.zero).dy - 30)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl.animateTo(offset,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialogs
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _showProductSelectionDialog(List<String> codes) async {
    if (codes.isEmpty) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProductSelectionDialog(
        productCodes: codes,
        onSelected: (code) => Navigator.of(context).pop(code),
        onCancel: () => Navigator.of(context).pop(null),
      ),
    );
  }

  void _showHelpDialog() {
    Get.dialog(AlertDialog(
      title: const Row(children: [
        Icon(Icons.help_outline_rounded, color: Color(0xFF00A859)),
        SizedBox(width: 12),
        Text('Hướng dẫn sử dụng'),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView(children: [
          ListTile(
            leading: const Icon(Icons.play_circle_fill_rounded,
                color: Color(0xFF00A859)),
            title: const Text('Quét mã vạch',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Cách thao tác máy ảnh để quét mã vạch'),
            onTap: () => Future.delayed(
              const Duration(milliseconds: 200),
              () => _showTutorialVideo(
                title: 'Hướng dẫn quét mã vạch',
                description:
                    'Video này hướng dẫn cách sử dụng camera quét mã vạch trong ứng dụng.',
              ),
            ),
          ),
          const Divider(height: 1),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Đóng'))
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ));
  }

  void _showTutorialVideo({required String title, String? description}) async {
    try {
      await _videoCtrl.seekTo(Duration.zero);
      _videoCtrl.play();
    } catch (_) {}

    Get.dialog(
      _TutorialVideoDialog(
        controller: _videoCtrl,
        isInitialized: _isVideoInitialized,
        title: title,
        description: description,
        dontShowAgain: _dontShowAgain,
        onDontShowChanged: (v) => setState(() => _dontShowAgain = v),
        onClose: () {
          _videoCtrl.pause();
          _markTutorialAsSeen();
          Get.back();
        },
      ),
      barrierDismissible: false,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<InvoiceDetailTempBloc, InvoiceDetailTempState>(
      listener: _onBlocState,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: _buildAppBar(theme),
        body: SafeArea(
          child: _isLoading ? _buildLoader(theme) : _buildBody(theme),
        ),
      ),
    );
  }

  void _onBlocState(BuildContext ctx, InvoiceDetailTempState state) {
    if (state is InvoiceDetailTempSaved) {
      setState(() => _invoiceData?.isSaved = true);
      _saveCompletedSnapshotLocal().then((_) {
        if (!mounted) return;
        Get.back(result: {'action': 'completed'});
        Get.snackbar('Thành công', 'Lưu phiếu xuất tạm thành công',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green,
            colorText: Colors.white);
        _storage.delete(key: 'invoice_temp_${_invoiceData!.idInvoice}');
        _storage.delete(
            key: 'invoice_pending_complete_${_invoiceData!.idInvoice}');
        _storage.read(key: 'pending_completed_invoices').then((idsJson) {
          if (idsJson == null || idsJson.isEmpty || _invoiceData == null) {
            return;
          }
          try {
            final ids = List<String>.from(jsonDecode(idsJson)).toSet();
            ids.remove(_invoiceData!.idInvoice.toString());
            _storage.write(
              key: 'pending_completed_invoices',
              value: jsonEncode(ids.toList()),
            );
          } catch (_) {}
        });
      });
    } else if (state is InvoiceDetailTempError) {
      _savePendingCompletionLocal(state.message).then((_) {
        if (!mounted) return;
        Get.snackbar(
          'Chờ đồng bộ',
          'Mạng/API lỗi nên phiếu đã được lưu chờ đồng bộ. Vui lòng thử lại khi mạng ổn định.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
        Get.back(result: {'action': 'pending_sync'});
      });
    }
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primaryColor, theme.primaryColor.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.primaryColor.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _appBarIconButton(Icons.arrow_back_ios_new,
                    size: 18, onPressed: () => Get.back(result: false)),
                Expanded(
                  child: Center(
                    child: Image.asset('assets/logos/logo.png', height: 36),
                  ),
                ),
                _appBarIconButton(Icons.refresh_rounded,
                    onPressed: _loadInvoiceDetails, tooltip: 'Làm mới'),
                _appBarIconButton(Icons.help_outline_rounded,
                    size: 22,
                    onPressed: _showHelpDialog,
                    tooltip: 'Hướng dẫn sử dụng'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appBarIconButton(IconData icon,
      {required VoidCallback onPressed, double size = 18, String? tooltip}) {
    return IconButton(
      tooltip: tooltip,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildLoader(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)
              ],
            ),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text('Đang tải dữ liệu...',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return Column(
      children: [
        if (_cameraActive) _buildCameraView(),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInvoiceHeader(theme),
                  const SizedBox(height: 14),
                  _buildOverviewCards(theme),
                  const SizedBox(height: 14),
                  _buildInlineInvoiceSummary(theme),
                  const SizedBox(height: 16),
                  _buildPalletModeSelector(),
                  const SizedBox(height: 20),
                  _buildBarcodeField(theme),
                  const SizedBox(height: 16),
                  _buildSavedCheckbox(),
                  const SizedBox(height: 24),
                  Container(
                    key: _mainSectionKey,
                    child: _buildSectionHeader(
                      'Sản phẩm đơn hàng',
                      _mainProducts.length,
                      Icons.shopping_cart_rounded,
                      Colors.blue,
                      _showOrderTable,
                      () => setState(() => _showOrderTable = !_showOrderTable),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: _showOrderTable
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: _buildItemList(_mainProducts,
                        isPromo: false, firstKey: _firstMainKey),
                    secondChild: const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    key: _promoSectionKey,
                    child: _buildSectionHeader(
                      'Sản phẩm khuyến mãi',
                      _promoProducts.length,
                      Icons.card_giftcard_rounded,
                      Colors.orange,
                      _showPromoTable,
                      () => setState(() => _showPromoTable = !_showPromoTable),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: _showPromoTable
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: _buildItemList(_promoProducts,
                        isPromo: true, firstKey: _firstPromoKey),
                    secondChild: const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        Container(
          height: 240,
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: QRView(
              key: _qrKey,
              onQRViewCreated: _onQRViewCreated,
              onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
              overlay: QrScannerOverlayShape(
                borderColor: Colors.red,
                borderRadius: 12,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: MediaQuery.of(context).size.width * 0.7,
              ),
              formatsAllowed: _kBarcodeFormats,
            ),
          ),
        ),
        Positioned(
          left: 28,
          right: 28,
          bottom: 26,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.58),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.center_focus_strong_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Đưa mã vào giữa khung để quét nhanh hơn',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 20,
          right: 20,
          child: GestureDetector(
            onTap: _enableManualInput,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 8)
                ],
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor.withOpacity(0.14),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: theme.primaryColor.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.receipt_long_rounded,
                color: theme.primaryColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _invoiceData?.orderVoucher ?? '',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                      fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  _customerNameCtrl.text,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCards(ThemeData theme) {
    final totalItems = _allItems.length;
    final enteredItems = _enteredItemCount(_allItems);
    final progress = totalItems == 0 ? 0.0 : enteredItems / totalItems;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildOverviewItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Tổng SP',
                  value: '$totalItems',
                  color: Colors.blue,
                ),
              ),
              Container(width: 1, height: 42, color: Colors.grey.shade200),
              Expanded(
                child: _buildOverviewItem(
                  icon: Icons.check_circle_rounded,
                  label: 'Đã nhập',
                  value: '$enteredItems',
                  color: Colors.green,
                ),
              ),
              Container(width: 1, height: 42, color: Colors.grey.shade200),
              Expanded(
                child: _buildOverviewItem(
                  icon: Icons.card_giftcard_rounded,
                  label: 'KM',
                  value: '${_promoProducts.length}',
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInlineInvoiceSummary(ThemeData theme) {
    final summary = _invoiceSummaryNumbers();
    final progress = (summary['progress'] as num).toDouble();
    final alerts = _allItems
        .expand((item) => _analyzeItem(item, includeMissing: true))
        .toList();
    final missing = _allItems
        .where(
            (item) => (item.realQuantityDVT ?? 0) < _requestedQuantityDVT(item))
        .take(3)
        .toList();
    final statusColor = alerts.isEmpty ? Colors.green : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(Icons.summarize_rounded, color: statusColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Text('Tóm tắt hóa đơn',
                    //     style: TextStyle(
                    //         color: Colors.grey.shade900,
                    //         fontWeight: FontWeight.w800,
                    //         fontSize: 14)),
                    // const SizedBox(height: 2),
                    Text(
                      alerts.isEmpty
                          ? 'Đã hoàn thành'
                          : 'Còn ${alerts.length} sản phẩm cần kiểm tra',
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildSummaryMetric('Đã đủ',
                      '${summary['completedItems']}/${summary['totalItems']}')),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSummaryMetric(
                      'Còn thiếu', '${summary['missingItems']}')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildSummaryMetric(
                      'SLYC ĐVT', _formatQty(summary['requestedDVT']!))),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildSummaryMetric(
                      'Thực xuất', _formatQty(summary['actualDVT']!))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1 ? Colors.green : theme.primaryColor,
              ),
            ),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...missing.map((item) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.pending_actions_rounded,
                          color: Colors.orange.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item.productCode ?? ''}: thiếu ${_formatQty(_requestedQuantityDVT(item) - (item.realQuantityDVT ?? 0))} ĐVT',
                          style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildPalletModeSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app_rounded,
                  size: 18, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text('Chọn hình thức quét',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children:
                PalletMode.values.map((mode) => _buildModeChip(mode)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(PalletMode mode) {
    final isSelected = _palletMode == mode;
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _palletMode = isSelected ? null : mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mode.icon,
                  size: 16,
                  color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarcodeField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TypeAheadField<String>(
              builder: (context, controller, focusNode) {
                _barcodeCtrl = controller;
                _barcodeFocus = focusNode;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: _cameraActive,
                  showCursor: !_cameraActive,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _hasScan = false),
                  onSubmitted: (v) {
                    if (!_cameraActive && v.trim().isNotEmpty) {
                      _processBarcode(v.trim());
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Quét hoặc nhập mã vạch / mã SP',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade400, fontSize: 14),
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
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 20, color: Colors.grey.shade500),
                            onPressed: () {
                              controller.clear();
                              setState(() => _hasScan = false);
                            },
                          )
                        : null,
                  ),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500),
                );
              },
              debounceDuration: const Duration(milliseconds: 300),
              hideOnEmpty: true,
              hideOnLoading: true,
              hideOnError: true,
              hideOnUnfocus: false,
              hideWithKeyboard: false,
              suggestionsCallback: (pattern) async {
                if (_cameraActive || pattern.trim().isEmpty || _hasScan)
                  return [];
                final lower = pattern.trim().toLowerCase();
                return _allItems
                    .where((e) =>
                        e.productCode?.toLowerCase().contains(lower) == true ||
                        e.productName?.toLowerCase().contains(lower) == true)
                    .map((e) => e.productCode!)
                    .toSet()
                    .toList();
              },
              itemBuilder: (_, code) {
                final product =
                    _allItems.firstWhere((e) => e.productCode == code);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.inventory_2_rounded,
                            size: 18, color: theme.primaryColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.productCode ?? '',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.primaryColor)),
                            const SizedBox(height: 2),
                            Text(product.productName ?? '',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              onSelected: (code) {
                final isPromo =
                    _promoProducts.any((e) => e.productCode == code);

                setState(() {
                  _isFromTypeAheadSelection = true;
                  _hasScan = true;
                  if (isPromo)
                    _showPromoTable = true;
                  else
                    _showOrderTable = true;
                });

                _barcodeCtrl.text = code;
                FocusScope.of(context).unfocus();

                // Cập nhật số lượng + đưa lên đầu
                _processBarcode(code);

                // Scroll tới item sau khi UI rebuild xong
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  _scrollToSection(
                    isPromo ? _firstPromoKey : _firstMainKey,
                    isPromo ? _promoSectionKey : _mainSectionKey,
                  );
                });
              },
              loadingBuilder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              emptyBuilder: (_) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Không tìm thấy sản phẩm',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            ),
          ),
          Container(height: 56, width: 1, color: Colors.grey.shade200),
          GestureDetector(
            onTap: _showScanOptions,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _cameraActive
                          ? theme.primaryColor
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.camera_alt_rounded,
                        size: 20,
                        color: _cameraActive
                            ? Colors.white
                            : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  // Text('Quét/chụp',
                  //     style: TextStyle(
                  //         fontSize: 10,
                  //         fontWeight: FontWeight.w600,
                  //         color: _cameraActive
                  //             ? theme.primaryColor
                  //             : Colors.grey.shade500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedCheckbox() {
    final isExporting = _invoiceData?.isExporting ?? false;
    return GestureDetector(
      onTap: () => setState(() => _invoiceData?.isExporting = !(isExporting)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isExporting ? Colors.green.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExporting ? Colors.green.shade300 : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isExporting ? Colors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isExporting ? Colors.green : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isExporting
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Text('Đã lưu tạm',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isExporting
                        ? Colors.green.shade700
                        : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, IconData icon,
      Color color, bool isVisible, VoidCallback onToggle) {
    final items =
        title.toLowerCase().contains('khuyến') ? _promoProducts : _mainProducts;
    final entered = _enteredItemCount(items);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3748))),
                  const SizedBox(height: 2),
                  Text('$count sản phẩm',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500)),
                  if (count > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: entered / count,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (count > 0)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$entered/$count',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            AnimatedRotation(
              turns: isVisible ? 0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.grey.shade600, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList(List<InvoiceDetailTempDto> items,
      {required bool isPromo, required GlobalKey firstKey}) {
    if (items.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(
              isPromo
                  ? Icons.card_giftcard_outlined
                  : Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text('Không có sản phẩm',
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    final cache = isPromo ? _promoCtrlCache : _mainCtrlCache;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (ctx, index) =>
          _buildItemCard(items[index], index, isPromo, cache, firstKey),
    );
  }

  Widget _buildItemCard(
    InvoiceDetailTempDto item,
    int index,
    bool isPromo,
    Map<String, _ItemControllers> cache,
    GlobalKey firstKey,
  ) {
    final theme = Theme.of(context);
    final isLastScanned = item.productCode == _lastScannedCode;
    final accentColor = isPromo ? Colors.orange : Colors.blue;
    final ctrl = cache[item.productCode ?? ''];

    // Tính toán SLYC
    final double spec = _safeSpecification(item);
    final double requestedThung = (item.quantity ?? 0) / spec; // ví dụ: 25.89
    final double requestedDVT = (item.quantity ?? 0).toDouble(); // tổng = 233
    final String donvitinh = item.unit ?? '';
    String displayThung = _formatQty(requestedThung);
    String displayDVT = _formatQty(requestedDVT);
    String? extraLeText;

    final hasEnteredQuantity =
        (item.realQuantity ?? 0) > 0 || (item.realQuantityDVT ?? 0) > 0;
    final progress = _itemProgress(item);

    if (isPromo) {
      final int thungNguyen = requestedThung.floor(); // 25
      final int dvtNguyen = (thungNguyen * spec).toInt();
      final double phanLeThung = requestedThung - thungNguyen; // 0.89
      final int leDVT = (phanLeThung * spec).round(); // 8

      displayThung = thungNguyen.toString();
      displayDVT = _formatQty(requestedDVT); // vẫn là tổng ĐVT

      if (leDVT > 0) {
        extraLeText = "$dvtNguyen lẻ $leDVT $donvitinh";
      } else {
        extraLeText = "$dvtNguyen lẻ $leDVT can/chai/gói";
      }
    } else {
      final num boxPerPallet = item.boxQuantity ?? 1;
      final int thungNguyen = requestedThung.floor();

      final int palletNguyen = thungNguyen ~/ boxPerPallet;
      final num thungLe = thungNguyen % boxPerPallet;

      if (palletNguyen > 0 || thungLe > 0) {
        extraLeText = "$palletNguyen pallet nguyên + $thungLe thùng lẻ";
      }
    }

    return Container(
      key: index == 0 ? firstKey : null,
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: hasEnteredQuantity ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isLastScanned
            ? Border.all(color: theme.primaryColor, width: 2)
            : hasEnteredQuantity
                ? Border.all(color: Colors.green.shade400, width: 1.5)
                : Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: isLastScanned
                ? theme.primaryColor.withOpacity(0.15)
                : hasEnteredQuantity
                    ? Colors.green.withOpacity(0.12)
                    : Colors.black.withOpacity(0.04),
            blurRadius: isLastScanned || hasEnteredQuantity ? 12 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: isLastScanned
                ? BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor.withOpacity(0.08),
                        theme.primaryColor.withOpacity(0.02),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIndexBadge(index, accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productCode ?? '',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: accentColor)),
                          const SizedBox(height: 4),
                          Text(item.productName ?? '',
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: Colors.grey.shade800),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusPill(
                      hasEnteredQuantity: hasEnteredQuantity,
                      isLastScanned: isLastScanned,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildQuantitySummary(
                  displayThung: displayThung,
                  displayDVT: displayDVT,
                  extraLeText: extraLeText,
                  unit: donvitinh,
                  progress: progress,
                  color: accentColor,
                ),
              ],
            ),
          ),

          // Phần nhập liệu
          if (ctrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: ctrl.qty,
                          label: 'SL Thùng',
                          icon: Icons.inventory_outlined,
                          enabled: _palletMode != PalletMode.leDonViTinh,
                          onTap: () => _selectAllText(ctrl.qty),
                          onEditingComplete: () =>
                              _onQtyChanged(item, ctrl, requestedDVT),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: ctrl.qtyDVT,
                          label: 'SL ĐVT',
                          icon: Icons.straighten_outlined,
                          enabled: _palletMode != PalletMode.palletLe,
                          onTap: () => _selectAllText(ctrl.qtyDVT),
                          onEditingComplete: () =>
                              _onQtyDVTChanged(item, ctrl, requestedDVT),
                        ),
                      ),
                    ],
                  ),
                  if (!isPromo) ...[
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: ctrl.batchCode,
                      label: 'Mã lô hàng',
                      icon: Icons.qr_code_2_rounded,
                      hint: 'Nhập mã lô hàng',
                      isNumber: false,
                      onEditingComplete: () => _onBatchChanged(item, ctrl),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildInfoRow(item),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _selectAllText(TextEditingController ctrl) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    });
  }

  void _onQtyChanged(
      InvoiceDetailTempDto item, _ItemControllers ctrl, num maxQtyDVT) {
    final qty = _parseQty(ctrl.qty.text);
    final calcDVT = qty * _safeSpecification(item);
    if (calcDVT > maxQtyDVT) {
      _showQtyError(maxQtyDVT);
      ctrl.qty.text = _formatQty(item.realQuantity ?? 0);
      return;
    }
    item.realQuantity = qty;
    item.realQuantityDVT = calcDVT;
    ctrl.qty.text = _formatQty(qty);
    ctrl.qtyDVT.text = _formatQty(calcDVT);
    setState(() {});
    _showAiWarningForItem(item);
    FocusScope.of(context).unfocus();
  }

  void _onQtyDVTChanged(
      InvoiceDetailTempDto item, _ItemControllers ctrl, num maxQtyDVT) {
    final qtyDVT = _parseQty(ctrl.qtyDVT.text);
    if (qtyDVT > maxQtyDVT) {
      _showQtyError(maxQtyDVT);
      ctrl.qtyDVT.text = _formatQty(item.realQuantityDVT ?? 0);
      return;
    }
    item.realQuantityDVT = qtyDVT;
    item.realQuantity = qtyDVT / _safeSpecification(item);
    ctrl.qtyDVT.text = _formatQty(qtyDVT);
    ctrl.qty.text = _formatQty(item.realQuantity ?? 0);
    setState(() {});
    _showAiWarningForItem(item);
    FocusScope.of(context).unfocus();
  }

  void _onBatchChanged(InvoiceDetailTempDto item, _ItemControllers ctrl) {
    final text = ctrl.batchCode.text.trim();
    item.noteBatchCode = text.isEmpty ? null : text;
    FocusScope.of(context).unfocus();
  }

  void _showQtyError(num maxDVT) {
    Get.snackbar(
      'Lỗi',
      'Số lượng thực tế (ĐVT) không được vượt quá SLYC: ${_formatQty(maxDVT)}',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.shade700,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      snackStyle: SnackStyle.FLOATING,
      icon: const Icon(Icons.error_outline_rounded,
          color: Colors.white, size: 28),
      shouldIconPulse: true,
      isDismissible: true,
    );
  }

  Widget _buildIndexBadge(int index, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Center(
        child: Text('${index + 1}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ),
    );
  }

  Widget _buildStatusPill({
    required bool hasEnteredQuantity,
    required bool isLastScanned,
  }) {
    final color = isLastScanned
        ? Theme.of(context).primaryColor
        : hasEnteredQuantity
            ? Colors.green
            : Colors.grey;
    final label = isLastScanned
        ? 'Vừa quét'
        : hasEnteredQuantity
            ? 'Đã nhập'
            : 'Chưa nhập';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildQuantitySummary({
    required String displayThung,
    required String displayDVT,
    required String unit,
    required double progress,
    required Color color,
    String? extraLeText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildQuantityCell(
                  label: 'Yêu cầu thùng',
                  value: displayThung,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuantityCell(
                  label: 'Yêu cầu ĐVT',
                  value: unit.isEmpty ? displayDVT : '$displayDVT $unit',
                  color: color,
                ),
              ),
            ],
          ),
          if (extraLeText != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    extraLeText,
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1 ? Colors.green : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityCell({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(InvoiceDetailTempDto item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoChip(Icons.layers_outlined, 'Thùng/pallet',
              '${item.boxQuantity ?? 1}'),
          Container(width: 1, height: 24, color: Colors.grey.shade300),
          _buildInfoChip(Icons.aspect_ratio_rounded, 'Quy cách',
              '${item.specification ?? 1}'),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool enabled = true,
    bool isNumber = true,
    VoidCallback? onTap,
    VoidCallback? onEditingComplete,
    Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        inputFormatters: isNumber
            ? [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*([.,]\d{0,6})?$'),
                ),
              ]
            : null,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textAlign: isNumber ? TextAlign.center : TextAlign.start,
        onTap: onTap,
        onEditingComplete: onEditingComplete,
        onTapOutside: (_) {
          onEditingComplete?.call();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        onSubmitted: onSubmitted,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.grey.shade800 : Colors.grey.shade500),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade500),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
                child: _buildActionButton(
              label: 'Lưu tạm',
              icon: Icons.save_rounded,
              colors: [Colors.orange.shade400, Colors.orange.shade600],
              shadowColor: Colors.orange,
              onTap: _saveTempLocal,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _buildActionButton(
              label: 'Hoàn thành',
              icon: Icons.check_circle_rounded,
              colors: [Colors.green.shade400, Colors.green.shade600],
              shadowColor: Colors.green,
              onTap: _saveInvoiceDetailTemp,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: shadowColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─── Extracted Dialogs ────────────────────────────────────────────────────────

class _ProductSelectionDialog extends StatelessWidget {
  final List<String> productCodes;
  final ValueChanged<String> onSelected;
  final VoidCallback onCancel;

  const _ProductSelectionDialog({
    required this.productCodes,
    required this.onSelected,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: 400, maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, const Color(0xFFF0F4F8)]),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                        Text('Chọn sản phẩm',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor)),
                        const SizedBox(height: 4),
                        Text(
                            'Barcode này trùng ${productCodes.length} sản phẩm trong đơn hàng',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: productCodes.length,
                  itemBuilder: (_, i) => Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(productCodes[i]),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(productCodes[i],
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Mã sản phẩm',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700])),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded,
                                color: kPrimaryColor, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Hủy', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialVideoDialog extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isInitialized;
  final String title;
  final String? description;
  final bool dontShowAgain;
  final ValueChanged<bool> onDontShowChanged;
  final VoidCallback onClose;

  const _TutorialVideoDialog({
    required this.controller,
    required this.isInitialized,
    required this.title,
    this.description,
    required this.dontShowAgain,
    required this.onDontShowChanged,
    required this.onClose,
  });

  @override
  State<_TutorialVideoDialog> createState() => _TutorialVideoDialogState();
}

class _TutorialVideoDialogState extends State<_TutorialVideoDialog> {
  late bool _dontShow;

  @override
  void initState() {
    super.initState();
    _dontShow = widget.dontShowAgain;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
                offset: const Offset(0, 10))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00A859), Color(0xFF008C4A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.school_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black,
                        child: widget.isInitialized
                            ? AspectRatio(
                                aspectRatio:
                                    widget.controller.value.aspectRatio,
                                child: VideoPlayer(widget.controller),
                              )
                            : const SizedBox(
                                height: 240,
                                child: Center(
                                    child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00A859)),
                                ))),
                      ),
                    ),
                    if (widget.isInitialized) ...[
                      const SizedBox(height: 24),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: widget.controller,
                        builder: (_, value, __) {
                          final pos = value.position.inSeconds.toDouble();
                          final dur = value.duration.inSeconds.toDouble();
                          return Column(
                            children: [
                              Slider(
                                value: pos.clamp(0, dur > 0 ? dur : 1),
                                min: 0,
                                max: dur > 0 ? dur : 1,
                                onChanged: (v) => widget.controller
                                    .seekTo(Duration(seconds: v.toInt())),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(value.position)),
                                    Text(_fmt(value.duration)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ctrl(Icons.replay_10, () {
                            final p = widget.controller.value.position;
                            widget.controller.seekTo(
                                p - const Duration(seconds: 10) >= Duration.zero
                                    ? p - const Duration(seconds: 10)
                                    : Duration.zero);
                          }),
                          const SizedBox(width: 32),
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: widget.controller,
                            builder: (_, value, __) => InkWell(
                              borderRadius: BorderRadius.circular(50),
                              onTap: () => value.isPlaying
                                  ? widget.controller.pause()
                                  : widget.controller.play(),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: const BoxDecoration(
                                    color: Color(0xFF00A859),
                                    shape: BoxShape.circle),
                                child: Icon(
                                  value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          _ctrl(Icons.forward_10, () {
                            final p = widget.controller.value.position;
                            final d = widget.controller.value.duration;
                            final next = p + const Duration(seconds: 10);
                            widget.controller.seekTo(next <= d ? next : d);
                          }),
                        ],
                      ),
                    ],
                    if (widget.description != null) ...[
                      const SizedBox(height: 32),
                      Text(widget.description!,
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.5),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _dontShow,
                          activeColor: const Color(0xFF00A859),
                          onChanged: (v) {
                            setState(() => _dontShow = v ?? false);
                            widget.onDontShowChanged(v ?? false);
                          },
                        ),
                        const Text('Không hiển thị lại lần sau',
                            style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A859),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: widget.onClose,
                child: const Text('Đóng',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrl(IconData icon, VoidCallback onPressed) {
    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF00A859).withOpacity(0.1),
            shape: BoxShape.circle),
        child: Icon(icon, color: const Color(0xFF00A859), size: 32),
      ),
    );
  }
}

// ─── Barcode formats ──────────────────────────────────────────────────────────

const _kBarcodeFormats = [
  BarcodeFormat.aztec,
  BarcodeFormat.codabar,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.code128,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.ean8,
  BarcodeFormat.ean13,
  BarcodeFormat.itf,
  BarcodeFormat.maxicode,
  BarcodeFormat.pdf417,
  BarcodeFormat.qrcode,
  BarcodeFormat.rss14,
  BarcodeFormat.rssExpanded,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.upcEanExtension,
];
