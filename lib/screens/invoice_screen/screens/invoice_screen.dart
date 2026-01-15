import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:stream_transform/stream_transform.dart' hide Switch;
import 'package:vibration/vibration.dart';
import 'package:flutter/scheduler.dart';
import '../../../constants/contains.dart';
import '../core/invoice_detail_temp_bloc.dart';
import '../core/invoice_detail_temp_event.dart';
import '../core/invoice_detail_temp_state.dart';
import '../model/invoice_detail_temp_dto.dart';
import '../model/invoice_temp_dto.dart';
import '../repository/invoice_detail_temp_repository.dart';
import '../repository/invoice_temp_repository.dart';

class InvoiceTempScreen extends StatefulWidget {
  static const String routeName = '/invoice-screen';

  const InvoiceTempScreen({Key? key}) : super(key: key);

  @override
  _InvoiceTempScreenState createState() => _InvoiceTempScreenState();
}

class _InvoiceTempScreenState extends State<InvoiceTempScreen> {
  bool scanCamera = true;
  String? selectedPalletOption = 'palletChan';
  final TextEditingController customerNameController = TextEditingController();
  TextEditingController barcodeController = TextEditingController();
  FocusNode _barcodeFocusNode = FocusNode();
  bool showOrderTable = true;
  bool showPromoTable = true;
  bool hasScan = false;
  bool _isLoading = false;
  QRViewController? _qrViewController;
  late ScrollController _scrollController;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final GlobalKey _mainSectionKey = GlobalKey(debugLabel: 'MainSection');
  final GlobalKey _promoSectionKey = GlobalKey(debugLabel: 'PromoSection');
  final GlobalKey _firstMainItemKey = GlobalKey(debugLabel: 'FirstMainItem');
  final GlobalKey _firstPromoItemKey = GlobalKey(debugLabel: 'FirstPromoItem');
  List<InvoiceDetailTempDto> invoices = [];
  List<InvoiceDetailTempDto> mainProducts = [];
  List<InvoiceDetailTempDto> promoProducts = [];
  late InvoiceDetailTempRepository _invoiceDetailTempRepository;
  InvoiceTempDto? _invoiceData;
  StreamSubscription? _qrSubscription;
  String? _lastScannedProductCode;
  final _storage = const FlutterSecureStorage();
  bool _isFromTypeAheadSelection = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _invoiceDetailTempRepository = InvoiceDetailTempRepository();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _barcodeFocusNode.requestFocus());
    _invoiceData = Get.arguments as InvoiceTempDto?;
    if (_invoiceData != null) {
      customerNameController.text = _invoiceData!.customerName ?? '';
      _loadInvoiceDetails();
    } else {
      setState(() => _isLoading = false);
      Get.snackbar('Lỗi', 'Dữ liệu hóa đơn không hợp lệ',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 2));
    }
  }

  Future<void> _loadInvoiceDetails() async {
    setState(() => _isLoading = true);

    final String key = 'invoice_temp_${_invoiceData!.idInvoice}';
    final String? storedJson = await _storage.read(key: key);

    List<InvoiceDetailTempDto> loadInvoices = [];
    if (storedJson != null && storedJson.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(storedJson);
        loadInvoices = jsonList
            .map((json) =>
            InvoiceDetailTempDto.fromJson(json as Map<String, dynamic>))
            .toList();
        setState(() {
          invoices = loadInvoices;
          mainProducts =
              invoices.where((item) => item.spchinh == true).toList();
          promoProducts =
              invoices.where((item) => item.spchinh == false).toList();
          _invoiceData?.isExporting = true; // Đánh dấu đã lưu tạm
          _isLoading = false;
        });

        Get.snackbar('Thông báo', 'Đã tải hóa đơn tạm từ bộ nhớ',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.blue,
            colorText: Colors.white);

        return; // Không cần load từ DB nữa
      } catch (e) {
        // Nếu lỗi parse JSON thì xóa key cũ và load từ DB
        await _storage.delete(key: key);
      }
    }

    if (loadInvoices.isEmpty) {
      try {
        final details = await _invoiceDetailTempRepository.searchInvoiceDetail(
          cm: 'list_invoice_detail_temps',
          idInvoice: _invoiceData!.idInvoice,
        );
        setState(() {
          invoices = details;
          mainProducts =
              invoices.where((item) => item.spchinh == true).toList();
          promoProducts =
              invoices.where((item) => item.spchinh == false).toList();
          _isLoading = false;
        });
      } catch (e) {}
    }
  }

  Future<bool> _initPermissions() async {
    final cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }
    return cameraStatus.isGranted;
  }

  void _playScanSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/Scanner-Beep-Sound.wav'));
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 100);
    }
  }

  void _toggleCamera() async {
    if (await _initPermissions()) {
      setState(() {
        scanCamera = !scanCamera;
        if (scanCamera) {
          _qrViewController?.resumeCamera();
        } else {
          _barcodeFocusNode.requestFocus();
          _qrViewController?.pauseCamera();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    customerNameController.dispose();
    barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _qrViewController?.dispose();
    _qrSubscription?.cancel();
    super.dispose();
  }

  void _scrollToSection(GlobalKey firstItemKey, GlobalKey sectionKey) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final firstItemContext = firstItemKey.currentContext;
      if (firstItemContext != null) {
        final firstItemBox = firstItemContext.findRenderObject() as RenderBox?;
        if (firstItemBox != null) {
          final position = firstItemBox
              .localToGlobal(Offset.zero)
              .dy;
          final scrollOffset = position - 30;
          _scrollController.animateTo(
            scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          return;
        }
      }
      final sectionContext = sectionKey.currentContext;
      if (sectionContext != null) {
        final sectionBox = sectionContext.findRenderObject() as RenderBox?;
        if (sectionBox != null) {
          final position = sectionBox
              .localToGlobal(Offset.zero)
              .dy;
          final scrollOffset = position - 30;
          _scrollController.animateTo(
            scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  bool _updateQuantities(InvoiceDetailTempDto element) {
    final maxQuantity = element.quantity?.toInt() ?? 0;
    final maxQuantityDVT = maxQuantity * (element.specification ?? 1);

    if (selectedPalletOption == 'palletChan') {
      final newQuantity =
      ((element.realQuantity ?? 0) + (element.boxQuantity ?? 1))
          .toInt()
          .toDouble();
      final newQuantityDVT =
      (newQuantity * (element.specification ?? 1)).toInt().toDouble();
      if (newQuantityDVT > maxQuantityDVT) {
        Get.snackbar(
          'Lỗi',
          'Số lượng thực tế (ĐVT) không được vượt quá SLYC: $maxQuantityDVT',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.red,
          duration: const Duration(seconds: 2),
          snackStyle: SnackStyle.FLOATING,
          // Quan trọng: đảm bảo màu nền được áp dụng
          margin: const EdgeInsets.all(16),
          // Tránh bị ép sát cạnh
          borderRadius: 12,
          isDismissible: true,
        );
        return false;
      }
      element.realQuantity = newQuantity;
      element.realQuantityDVT = newQuantityDVT;
    } else if (selectedPalletOption == 'palletLe') {
      final newQuantity = ((element.realQuantity ?? 0) + 1).toInt().toDouble();
      final newQuantityDVT =
      (newQuantity * (element.specification ?? 1)).toInt().toDouble();
      if (newQuantityDVT > maxQuantityDVT) {
        Get.snackbar(
          'Lỗi',
          'Số lượng thực tế (ĐVT) không được vượt quá SLYC: $maxQuantityDVT',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.red,
          duration: const Duration(seconds: 2),
          snackStyle: SnackStyle.FLOATING,
          // Quan trọng: đảm bảo màu nền được áp dụng
          margin: const EdgeInsets.all(16),
          // Tránh bị ép sát cạnh
          borderRadius: 12,
          isDismissible: true,
        );
        return false;
      }
      element.realQuantity = newQuantity;
      element.realQuantityDVT = newQuantityDVT;
    } else if (selectedPalletOption == 'leDonViTinh') {
      final newQuantityDVT =
      ((element.realQuantityDVT ?? 0) + 1).toInt().toDouble();
      final newQuantity =
      (newQuantityDVT / (element.specification ?? 1)).toInt().toDouble();
      if (newQuantityDVT > maxQuantityDVT) {
        Get.snackbar(
          'Lỗi',
          'Số lượng thực tế (ĐVT) không được vượt quá SLYC: $maxQuantityDVT',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade700,
          colorText: Colors.red,
          duration: const Duration(seconds: 2),
          snackStyle: SnackStyle.FLOATING,
          margin: const EdgeInsets.all(16),
          borderRadius: 12,
          isDismissible: true,
        );
        return false;
      }
      element.realQuantityDVT = newQuantityDVT;
      element.realQuantity = newQuantity;
    }
    return true;
  }

  void _bringItemToTop(int index, bool isPromo) {
    final item = invoices[index];
    setState(() {
      _lastScannedProductCode = item.productCode;
      invoices.removeAt(index);
      invoices.insert(0, item);
      mainProducts = invoices.where((e) => e.spchinh == true).toList();
      promoProducts = invoices.where((e) => e.spchinh == false).toList();
      if (isPromo) {
        final promoIndex =
        promoProducts.indexWhere((e) => e.productCode == item.productCode);
        if (promoIndex >= 0) {
          final promoItem = promoProducts.removeAt(promoIndex);
          promoProducts.insert(0, promoItem);
        }
      } else {
        final mainIndex =
        mainProducts.indexWhere((e) => e.productCode == item.productCode);
        if (mainIndex >= 0) {
          final mainItem = mainProducts.removeAt(mainIndex);
          mainProducts.insert(0, mainItem);
        }
      }
    });
  }

  void _saveTempLocal() async {
    if (invoices.isEmpty && mainProducts.isEmpty && promoProducts.isEmpty) {
      Get.snackbar(
        'Lỗi',
        'Chưa có sản phẩm nào để lưu',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    // === CẬP NHẬT SỐ LƯỢNG VÀ MÃ LÔ HÀNG TỪ CÁC TEXTFIELD ===
    // Tạo controller tạm để đọc giá trị hiện tại (vì ListView.builder tạo mới mỗi lần build)
    final realQuantityControllers = mainProducts
        .map((item) =>
        TextEditingController(
            text: item.realQuantity?.toInt().toString() ?? ''))
        .toList();
    final realQuantityDVTControllers = mainProducts
        .map((item) =>
        TextEditingController(
            text: item.realQuantityDVT?.toInt().toString() ?? ''))
        .toList();
    final noteBatchCodeControllers = mainProducts
        .map((item) =>
        TextEditingController(text: item.noteBatchCode?.toString() ?? ''))
        .toList();

    bool hasError = false;

    for (int i = 0; i < mainProducts.length; i++) {
      final item = mainProducts[i];

      // Cập nhật số lượng thùng
      final qtyText = realQuantityControllers[i].text.trim();
      final qty = qtyText.isEmpty ? 0.0 : double.tryParse(qtyText) ?? 0.0;

      // Cập nhật số lượng ĐVT
      final qtyDVTText = realQuantityDVTControllers[i].text.trim();
      final qtyDVT =
      qtyDVTText.isEmpty ? 0.0 : double.tryParse(qtyDVTText) ?? 0.0;

      // Cập nhật mã lô hàng
      final batchCode = noteBatchCodeControllers[i].text.trim();

      // Tính toán lại qtyDVT từ qty nếu cần (tùy mode pallet)
      final calculatedQtyDVT = (qty * (item.specification ?? 1)).toDouble();

      // Kiểm tra vượt số lượng yêu cầu
      final maxQuantityDVT =
          (item.quantity?.toInt() ?? 0) * (item.specification ?? 1);

      if (qtyDVT > maxQuantityDVT || calculatedQtyDVT > maxQuantityDVT) {
        Get.snackbar(
          'Lỗi',
          'Sản phẩm "${item
              .productName}" vượt số lượng yêu cầu: $maxQuantityDVT ĐVT',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
        hasError = true;
      }

      // Cập nhật vào model
      item.realQuantity = qty;
      item.realQuantityDVT =
      qtyDVT > 0 ? qtyDVT : calculatedQtyDVT; // ưu tiên nhập tay ĐVT nếu có
      item.noteBatchCode =
      batchCode.isEmpty ? null : batchCode; // lưu null nếu rỗng
    }

    // Nếu có lỗi thì dừng lại, không lưu
    if (hasError) {
      // Dispose controller để tránh leak
      for (var c in realQuantityControllers)
        c.dispose();
      for (var c in realQuantityDVTControllers)
        c.dispose();
      for (var c in noteBatchCodeControllers)
        c.dispose();
      return;
    }

    // Dispose các controller tạm
    for (var c in realQuantityControllers)
      c.dispose();
    for (var c in realQuantityDVTControllers)
      c.dispose();
    for (var c in noteBatchCodeControllers)
      c.dispose();

    // === CẬP NHẬT DANH SÁCH INVOICES ĐẦY ĐỦ ===
    setState(() {
      invoices = [...mainProducts, ...promoProducts];
      _invoiceData?.isExporting = true; // Đánh dấu đang chờ xuất
      _invoiceData?.isSaved = false;
    });

    // === LƯU VÀO FlutterSecureStorage ===
    final String key = 'invoice_temp_${_invoiceData!.idInvoice}';
    final List<Map<String, dynamic>> invoicesJson =
    invoices.map((item) => item.toJson()).toList();

    try {
      await _storage.write(key: key, value: jsonEncode(invoicesJson));

      Get.back(result: {'action': 'temp_saved'});
      Get.snackbar(
        'Thành công',
        'Đã lưu tạm thành công',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      Get.snackbar(
        'Lỗi',
        'Lưu tạm thất bại: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _saveInvoiceDetailTemp() {
    setState(() {
      _invoiceData?.isSaved = false;
    });
    context
        .read<InvoiceDetailTempBloc>()
        .add(SaveInvoiceDetailTempEvent(invoices));
    Get.snackbar(
      'Thành công',
      'Thao tác thành công',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  void _processBarcode(String barcode, {bool fromCamera = false}) async {
    if (barcode.isEmpty) return;

    if (selectedPalletOption == null) {
      Fluttertoast.showToast(
        msg: 'Chưa chọn hình thức',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
        textColor: Colors.white,
      );
      return;
    }

    setState(() {
      barcodeController.text = barcode;
      hasScan = true;
    });

    String productCodeToSearch = '';

    if (fromCamera) {
      try {
        Get.dialog(const Center(child: CircularProgressIndicator()),
            barrierDismissible: false);

        // Thử parse QR JSON trước
        try {
          final jsonData = jsonDecode(barcode) as Map<String, dynamic>?;

          if (jsonData != null && jsonData.containsKey('productLix')) {
            final productLix = jsonData['productLix'] as Map<String, dynamic>;
            final codeRaw = productLix['code'];
            productCodeToSearch = codeRaw?.toString().trim() ?? '';
          }
        } catch (_) {}

        // Nếu chưa có code từ JSON → gọi API lấy list
        if (productCodeToSearch.isEmpty) {
          final repo = InvoiceTempRepository();
          final productCodesFromApi = await repo.findProductCodeByBarcodeThung(
              barcode);

          Get.back(); // Đóng loading sớm

          if (productCodesFromApi.isEmpty) {
            _showErrorSnackbar('Không tìm thấy sản phẩm cho barcode: $barcode');
            return;
          }

          // Lọc chỉ những mã sản phẩm THỰC SỰ CÓ TRONG ĐƠN HÀNG (invoices)
          final Set<String> matchedProductCodes = {};
          for (final item in invoices) {
            if (productCodesFromApi.contains(item.productCode)) {
              matchedProductCodes.add(item.productCode!);
            }
          }

          final matchedCodesList = matchedProductCodes
              .toList(); // List unique đã lọc
          final int listSize = matchedCodesList.length;
          if (matchedCodesList.isEmpty) {
            _showErrorSnackbar(
                'Barcode này không có sản phẩm nào trong đơn hàng hiện tại');
            return;
          }

          String selectedCode;
          if (matchedCodesList.length == 1) {
            // Chỉ có đúng 1 sản phẩm trong đơn hàng → tự động xử lý
            selectedCode = matchedCodesList.first;
          } else {
            // Nhiều sản phẩm → show dialog chọn
            final selected = await _showProductSelectionDialog(
                matchedCodesList,listSize);
            if (selected == null) {
              return; // Người dùng hủy
            }
            selectedCode = selected;
          }

          // Tìm index của sản phẩm đã chọn (hoặc duy nhất)
          final index = invoices.indexWhere(
                (e) =>
            e.productCode?.toLowerCase() == selectedCode.toLowerCase(),
          );

          if (index == -1) {
            _showErrorSnackbar(
                'Không tìm thấy sản phẩm đã chọn trong đơn hàng');
            return;
          }

          final element = invoices[index];
          final isPromo = element.spchinh == false;

          if (fromCamera || !_isFromTypeAheadSelection) {
            if (!_updateQuantities(element)) {
              return;
            }
          }

          _bringItemToTop(index, isPromo);

          SchedulerBinding.instance.addPostFrameCallback((_) {
            setState(() {
              showOrderTable = true;
              showPromoTable = true;
            });
            _scrollToSection(
              isPromo ? _firstPromoItemKey : _firstMainItemKey,
              isPromo ? _promoSectionKey : _mainSectionKey,
            );
          });

          if (fromCamera || !_isFromTypeAheadSelection) {
            _playScanSound();
          }

          _isFromTypeAheadSelection = false;

          if (!fromCamera) {
            Future.delayed(const Duration(milliseconds: 100), () {
              barcodeController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: barcodeController.text.length,
              );
              _barcodeFocusNode.requestFocus();
            });
          }
        }
      } catch (e) {
        Get.back();
        _showErrorSnackbar('Lỗi xử lý QR/Barcode: $e');
        return;
      }
    } else {
      productCodeToSearch = barcode.trim();
    }
  }
  Future<String?> _showProductSelectionDialog(List<String> productCodes,int listSize) async {
    // Loại bỏ duplicate ngay từ đầu
    final uniqueCodes = productCodes.toSet().toList(); // Chỉ giữ mã duy nhất

    if (uniqueCodes.isEmpty) {
      Get.snackbar(
          'Thông báo', 'Không có sản phẩm nào', backgroundColor: Colors.orange);
      return null;
    }

    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery
                  .of(context)
                  .size
                  .height * 0.7,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, const Color(0xFFF0F4F8)],
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
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, color: kPrimaryColor,
                          size: 32),
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
                                color: kPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Barcode này trùng ${listSize} sản phẩm trong đơn hàng',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // List sản phẩm (unique)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: uniqueCodes.length,
                      itemBuilder: (ctx, index) {
                        final code = uniqueCodes[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).pop(code),
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
                                      crossAxisAlignment: CrossAxisAlignment
                                          .start,
                                      children: [
                                        Text(
                                          code,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Mã sản phẩm',
                                          style: TextStyle(fontSize: 13,
                                              color: Colors.grey[700]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: kPrimaryColor,
                                    size: 20,
                                  ),
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
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Hủy', style: TextStyle(
                            fontSize: 16)),
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
      backgroundColor: Colors.red,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  void scannerBarcode(String barcode) => _processBarcode(barcode);

  void scannerBarcodeByCam(String barcode) {
    if (scanCamera) _processBarcode(barcode, fromCamera: true);
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;
    if (scanCamera) controller.resumeCamera();
    _qrSubscription = controller.scannedDataStream
        .debounce(const Duration(milliseconds: 300))
        .listen((scanData) {
      if (scanData.code != null) scannerBarcodeByCam(scanData.code!);
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
    return BlocListener<InvoiceDetailTempBloc, InvoiceDetailTempState>(
      listener: (context, state) {
        if (state is InvoiceDetailTempSaved) {
          Get.snackbar(
            'Thành công',
            'Lưu hóa đơn tạm thành công',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
          _storage.delete(key: 'invoice_temp_${_invoiceData!.idInvoice}');
          Get.back(result: {'saved': _invoiceData?.isSaved ?? false});
        } else if (state is InvoiceDetailTempError) {
          Get.snackbar(
            'Lỗi',
            'Lưu hóa đơn tạm thất bại: ${state.message}',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primaryColor,
                  theme.primaryColor.withOpacity(0.8)
                ],
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
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white, size: 18),
                      ),
                      onPressed: () => Get.back(result: false),
                    ),
                    Expanded(
                      child: Center(
                        child: Image.asset('assets/logos/logo.png', height: 36),
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 18),
                      ),
                      tooltip: 'Làm mới',
                      onPressed: _loadInvoiceDetails,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: _isLoading
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation<Color>(theme.primaryColor),
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Đang tải dữ liệu...',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
              : Column(
            children: [
              if (scanCamera)
                Stack(
                  children: [
                    Container(
                      height: 260,
                      margin: const EdgeInsets.all(12),
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
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.primaryColor.withOpacity(0.1),
                                theme.primaryColor.withOpacity(0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.primaryColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.primaryColor
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.receipt_long_rounded,
                                  color: theme.primaryColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _invoiceData?.orderVoucher ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.primaryColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      customerNameController.text,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _buildModernFilterChip('Lẻ Pallet',
                                  'palletLe', Icons.view_module_outlined),
                              _buildModernFilterChip('Chẵn Pallet',
                                  'palletChan', Icons.grid_view_rounded),
                              _buildModernFilterChip(
                                  'Lẻ ĐVT',
                                  'leDonViTinh',
                                  Icons.straighten_rounded),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
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
                                child: TypeAheadField<String>(
                                  builder:
                                      (context, controller, focusNode) {
                                    barcodeController = controller;
                                    _barcodeFocusNode = focusNode;

                                    return TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      readOnly: scanCamera,
                                      textInputAction:
                                      TextInputAction.done,
                                      onChanged: (value) =>
                                          setState(() => hasScan = false),
                                      onSubmitted: (value) {
                                        if (!scanCamera &&
                                            value
                                                .trim()
                                                .isNotEmpty) {
                                          _processBarcode(value.trim());
                                        }
                                      },
                                      decoration: InputDecoration(
                                        hintText:
                                        'Quét hoặc nhập mã vạch / tên SP',
                                        hintStyle: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 14),
                                        border: InputBorder.none,
                                        contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16),
                                        prefixIcon: Container(
                                          margin: const EdgeInsets.only(
                                              left: 12, right: 8),
                                          padding:
                                          const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: theme.primaryColor
                                                .withOpacity(0.1),
                                            borderRadius:
                                            BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                              Icons
                                                  .qr_code_scanner_rounded,
                                              size: 22,
                                              color: theme.primaryColor),
                                        ),
                                        suffixIcon: controller
                                            .text.isNotEmpty
                                            ? IconButton(
                                          icon: Icon(
                                              Icons.close_rounded,
                                              size: 20,
                                              color: Colors
                                                  .grey.shade500),
                                          onPressed: () {
                                            controller.clear();
                                            setState(() =>
                                            hasScan = false);
                                          },
                                        )
                                            : null,
                                      ),
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500),
                                    );
                                  },
                                  debounceDuration:
                                  const Duration(milliseconds: 300),
                                  hideOnEmpty: true,
                                  hideOnLoading: true,
                                  hideOnError: true,
                                  hideOnUnfocus: false,
                                  hideWithKeyboard: false,
                                  suggestionsCallback: (pattern) async {
                                    final trimmed = pattern.trim();
                                    if (scanCamera ||
                                        trimmed.isEmpty ||
                                        hasScan) {
                                      return [];
                                    }
                                    final lowerPattern =
                                    trimmed.toLowerCase();
                                    return invoices
                                        .where((item) =>
                                    item.productCode
                                        ?.toLowerCase()
                                        .contains(
                                        lowerPattern) ==
                                        true ||
                                        item.productName
                                            ?.toLowerCase()
                                            .contains(
                                            lowerPattern) ==
                                            true)
                                        .map((item) => item.productCode!)
                                        .toSet()
                                        .toList();
                                  },
                                  itemBuilder:
                                      (context, String suggestionCode) {
                                    final product = invoices.firstWhere(
                                          (item) =>
                                      item.productCode ==
                                          suggestionCode,
                                    );
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding:
                                            const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: theme.primaryColor
                                                  .withOpacity(0.1),
                                              borderRadius:
                                              BorderRadius.circular(
                                                  8),
                                            ),
                                            child: Icon(
                                                Icons.inventory_2_rounded,
                                                size: 18,
                                                color:
                                                theme.primaryColor),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                              children: [
                                                Text(
                                                  product.productCode ??
                                                      '',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                    FontWeight.w600,
                                                    color: theme
                                                        .primaryColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  product.productName ??
                                                      '',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade600),
                                                  maxLines: 1,
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  onSelected: (String selectedCode) {
                                    setState(() {
                                      _isFromTypeAheadSelection = true;
                                      hasScan = true;
                                    });
                                    barcodeController.text = selectedCode;
                                    _processBarcode(selectedCode);
                                    FocusScope.of(context).unfocus();
                                  },
                                  loadingBuilder: (context) =>
                                  const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  ),
                                  emptyBuilder: (context) =>
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Text('Không tìm thấy sản phẩm',
                                            style: TextStyle(
                                                color: Colors.grey.shade500)),
                                      ),
                                ),
                              ),
                              Container(
                                height: 56,
                                width: 1,
                                color: Colors.grey.shade200,
                              ),
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
                                          borderRadius:
                                          BorderRadius.circular(10),
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
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () =>
                              setState(() =>
                              _invoiceData?.isExporting =
                              !(_invoiceData?.isExporting ?? false)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: (_invoiceData?.isExporting ?? false)
                                  ? Colors.green.shade50
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                (_invoiceData?.isExporting ?? false)
                                    ? Colors.green.shade300
                                    : Colors.grey.shade200,
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
                                    color: (_invoiceData?.isExporting ??
                                        false)
                                        ? Colors.green
                                        : Colors.transparent,
                                    borderRadius:
                                    BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (_invoiceData?.isExporting ??
                                          false)
                                          ? Colors.green
                                          : Colors.grey.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  child:
                                  (_invoiceData?.isExporting ?? false)
                                      ? const Icon(Icons.check,
                                      size: 16,
                                      color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Đã lưu tạm',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: (_invoiceData?.isExporting ??
                                        false)
                                        ? Colors.green.shade700
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          key: _mainSectionKey,
                          child: _buildModernSectionHeader(
                            'Sản phẩm đơn hàng',
                            mainProducts.length,
                            Icons.shopping_cart_rounded,
                            Colors.blue,
                            showOrderTable,
                                () =>
                                setState(
                                        () => showOrderTable = !showOrderTable),
                          ),
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState: showOrderTable
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: _buildItemList(mainProducts,
                              isPromoList: false,
                              firstItemKey: _firstMainItemKey),
                          secondChild: const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          key: _promoSectionKey,
                          child: _buildModernSectionHeader(
                            'Sản phẩm khuyến mãi',
                            promoProducts.length,
                            Icons.card_giftcard_rounded,
                            Colors.orange,
                            showPromoTable,
                                () =>
                                setState(
                                        () => showPromoTable = !showPromoTable),
                          ),
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          crossFadeState: showPromoTable
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: _buildItemList(promoProducts,
                              isPromoList: true,
                              firstItemKey: _firstPromoItemKey),
                          secondChild: const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _saveTempLocal,
                          child: Container(
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange.shade400,
                                  Colors.orange.shade600
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.save_rounded,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Lưu tạm',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _saveInvoiceDetailTemp,
                          child: Container(
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade400,
                                  Colors.green.shade600
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Hoàn thành',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernFilterChip(String label, String value, IconData icon) {
    final isSelected = selectedPalletOption == value;
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () =>
            setState(() => selectedPalletOption = isSelected ? null : value),
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
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
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

  Widget _buildModernSectionHeader(String title, int count, IconData icon,
      Color color, bool isVisible, VoidCallback onToggle) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count sản phẩm',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: isVisible ? 0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.grey.shade600, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrView(BuildContext context) {
    return QRView(
      key: qrKey,
      onQRViewCreated: _onQRViewCreated,
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
      overlay: QrScannerOverlayShape(
        borderColor: Colors.red,
        borderRadius: 12,
        borderLength: 30,
        borderWidth: 10,
        cutOutSize: MediaQuery
            .of(context)
            .size
            .width * 0.7,
      ),
      formatsAllowed: _listFormats,
    );
  }

  Widget _buildItemList(List<InvoiceDetailTempDto> items,
      {required bool isPromoList, required GlobalKey firstItemKey}) {
    if (items.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Column(
          children: [
            Icon(
              isPromoList
                  ? Icons.card_giftcard_outlined
                  : Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Không có sản phẩm',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final realQuantityControllers = items
        .map((item) =>
        TextEditingController(
            text: item.realQuantity?.toInt().toString() ?? ''))
        .toList();
    final realQuantityDVTControllers = items
        .map((item) =>
        TextEditingController(
            text: item.realQuantityDVT?.toInt().toString() ?? ''))
        .toList();
    final noteBatchCodeControllers = items
        .map((item) => TextEditingController(text: item.noteBatchCode ?? ''))
        .toList();
    final theme = Theme.of(context);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isLastScanned = item.productCode == _lastScannedProductCode;
        final maxQuantity = item.quantity?.toInt() ?? 0;
        final maxQuantityDVT = maxQuantity;
        final accentColor = isPromoList ? Colors.orange : Colors.blue;

        return Container(
          key: index == 0 ? firstItemKey : null,
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isLastScanned
                ? Border.all(color: theme.primaryColor, width: 2)
                : Border.all(color: Colors.grey.shade100, width: 1),
            boxShadow: [
              BoxShadow(
                color: isLastScanned
                    ? theme.primaryColor.withOpacity(0.15)
                    : Colors.black.withOpacity(0.04),
                blurRadius: isLastScanned ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: isLastScanned
                      ? LinearGradient(
                    colors: [
                      theme.primaryColor.withOpacity(0.08),
                      theme.primaryColor.withOpacity(0.02),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                      : null,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accentColor.withOpacity(0.8), accentColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productCode ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.productName ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border:
                        Border.all(color: Colors.red.shade200, width: 1),
                      ),
                      child: Text(
                        'YC: $maxQuantityDVT',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildModernTextField(
                            controller: realQuantityControllers[index],
                            label: 'SL Thùng',
                            icon: Icons.inventory_outlined,
                            enabled: selectedPalletOption != 'leDonViTinh',
                            onTap: () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _scrollController.animateTo(
                                  _scrollController.position.pixels + 100,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              });
                              realQuantityControllers[index].selection =
                                  TextSelection(
                                    baseOffset: 0,
                                    extentOffset:
                                    realQuantityControllers[index].text.length,
                                  );
                            },
                            onEditingComplete: () {
                              if (selectedPalletOption == null) {
                                Get.snackbar('Cảnh báo', 'Chưa chọn hình thức');
                                return;
                              }
                              final qty = double.tryParse(
                                  realQuantityControllers[index].text) ??
                                  0;
                              final qtyDVT = (qty * (item.specification ?? 1))
                                  .toInt()
                                  .toDouble();
                              if (qtyDVT > maxQuantityDVT) {
                                Get.snackbar(
                                  'Lỗi',
                                  'Số lượng thực tế (ĐVT) không được vượt quá SLYC: $maxQuantityDVT',
                                  snackPosition: SnackPosition.BOTTOM,
                                  backgroundColor: Colors.red,
                                  // Đỏ rõ ràng
                                  colorText: Colors.white,
                                  duration: const Duration(seconds: 3),
                                  // Tăng thời gian hiển thị để đọc rõ
                                  margin: const EdgeInsets.all(16),
                                  // Thêm margin để không sát cạnh màn hình
                                  borderRadius: 12,
                                  snackStyle: SnackStyle.FLOATING,
                                  // Đảm bảo màu nền được áp dụng
                                  icon: const Icon(Icons.error_outline_rounded,
                                      color: Colors.white, size: 28),
                                  shouldIconPulse: true,
                                  isDismissible: true,
                                );
                                realQuantityControllers[index].text =
                                    item.realQuantity?.toInt().toString() ?? '';
                                return;
                              }
                              item.realQuantity = qty.toInt().toDouble();
                              item.realQuantityDVT = qtyDVT;
                              realQuantityDVTControllers[index].text =
                                  item.realQuantityDVT?.toInt().toString() ??
                                      '';
                              setState(() =>
                              invoices = [
                                ...mainProducts,
                                ...promoProducts
                              ]);
                              FocusScope.of(context).unfocus();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildModernTextField(
                            controller: realQuantityDVTControllers[index],
                            label: 'SL ĐVT',
                            icon: Icons.straighten_outlined,
                            enabled: selectedPalletOption != 'palletLe',
                            onTap: () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _scrollController.animateTo(
                                  _scrollController.position.pixels + 100,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              });
                              realQuantityDVTControllers[index].selection =
                                  TextSelection(
                                    baseOffset: 0,
                                    extentOffset: realQuantityDVTControllers[index]
                                        .text
                                        .length,
                                  );
                            },
                            onEditingComplete: () {
                              final qtyDVT = double.tryParse(
                                  realQuantityDVTControllers[index].text) ??
                                  0;
                              if (qtyDVT > maxQuantityDVT) {
                                Get.snackbar(
                                  'Lỗi',
                                  'Số lượng thực tế (ĐVT) không được vượt quá SLYC: $maxQuantityDVT',
                                  snackPosition: SnackPosition.BOTTOM,
                                  backgroundColor: Colors.red,
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
                                realQuantityDVTControllers[index].text =
                                    item.realQuantityDVT?.toInt().toString() ??
                                        '';
                                return;
                              }
                              item.realQuantityDVT = qtyDVT.toInt().toDouble();
                              item.realQuantity =
                                  (qtyDVT / (item.specification ?? 1))
                                      .toInt()
                                      .toDouble();
                              realQuantityControllers[index].text =
                                  item.realQuantity?.toInt().toString() ?? '';
                              setState(() =>
                              invoices = [
                                ...mainProducts,
                                ...promoProducts
                              ]);
                              FocusScope.of(context).unfocus();
                            },
                          ),
                        ),
                      ],
                    ),
                    if (!isPromoList) ...[
                      const SizedBox(height: 12),
                      _buildModernTextField(
                        controller: noteBatchCodeControllers[index],
                        label: 'Mã lô hàng',
                        icon: Icons.qr_code_2_rounded,
                        hint: 'Nhập mã lô hàng',
                        isNumber: false,
                        onEditingComplete: () {
                          final text =
                          noteBatchCodeControllers[index].text.trim();
                          item.noteBatchCode = text.isEmpty ? null : text;
                          setState(() =>
                          invoices = [...mainProducts, ...promoProducts]);
                          FocusScope.of(context).unfocus();
                        },
                        onSubmitted: (value) {
                          final text = value.trim();
                          item.noteBatchCode = text.isEmpty ? null : text;
                          setState(() =>
                          invoices = [...mainProducts, ...promoProducts]);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInfoChip(Icons.layers_outlined, 'Thùng/pallet',
                              '${item.boxQuantity ?? 1}'),
                          Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey.shade300),
                          _buildInfoChip(Icons.aspect_ratio_rounded, 'Quy cách',
                              '${item.specification ?? 1}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernTextField({
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
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        inputFormatters:
        isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textAlign: isNumber ? TextAlign.center : TextAlign.start,
        onTap: onTap,
        onEditingComplete: onEditingComplete,
        onSubmitted: onSubmitted,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: enabled ? Colors.grey.shade800 : Colors.grey.shade500,
        ),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
          hintStyle: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade400,
          ),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const _listFormats = [
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
