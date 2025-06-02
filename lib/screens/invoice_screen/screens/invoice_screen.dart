
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:stream_transform/stream_transform.dart' hide Switch;
import 'package:vibration/vibration.dart';
import '../../../utils/date_utils.dart';
import '../core/invoice_detail_temp_bloc.dart';
import '../core/invoice_detail_temp_event.dart';
import '../core/invoice_detail_temp_state.dart';
import '../core/invoice_temp_bloc.dart';
import '../model/invoice_detail_temp_dto.dart';
import '../model/invoice_temp_dto.dart';
import '../repository/invoice_detail_temp_repository.dart';

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
final TextEditingController barcodeController = TextEditingController();
final FocusNode _barcodeFocusNode = FocusNode();
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

@override
void initState() {
super.initState();
_scrollController = ScrollController();
_invoiceDetailTempRepository = InvoiceDetailTempRepository();
WidgetsBinding.instance.addPostFrameCallback((_) => _barcodeFocusNode.requestFocus());
_invoiceData = Get.arguments as InvoiceTempDto?;
if (_invoiceData != null) {
customerNameController.text = _invoiceData!.customerName ?? '';
_loadInvoiceDetails();
} else {
setState(() => _isLoading = false);
Get.snackbar('Lỗi', 'Dữ liệu hóa đơn không hợp lệ', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white, duration: const Duration(seconds: 2));
}
}

Future<void> _loadInvoiceDetails() async {
setState(() => _isLoading = true);
try {
final details = await _invoiceDetailTempRepository.searchInvoiceDetail(
cm: 'list_invoice_detail_temps',
idInvoice: _invoiceData!.idInvoice,
);
setState(() {
invoices = details;
mainProducts = invoices.where((item) => item.spchinh == true).toList();
promoProducts = invoices.where((item) => item.spchinh == false).toList();
_isLoading = false;
});
if (details.isEmpty) {
Get.snackbar('Thông báo', 'Không có chi tiết hóa đơn', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.orange, colorText: Colors.white, duration: const Duration(seconds: 2));
}
} catch (e) {
setState(() {
invoices = [];
mainProducts = [];
promoProducts = [];
_isLoading = false;
});
Get.snackbar('Lỗi', 'Không thể tải chi tiết hóa đơn: $e', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white, duration: const Duration(seconds: 2));
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
final firstItemBox = firstItemKey.currentContext?.findRenderObject() as RenderBox?;
final sectionBox = sectionKey.currentContext?.findRenderObject() as RenderBox?;
if (firstItemBox != null) {
final position = firstItemBox.localToGlobal(Offset.zero).dy;
final scrollOffset = position + _scrollController.offset - 100;
_scrollController.animateTo(scrollOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
} else if (sectionBox != null) {
final position = sectionBox.localToGlobal(Offset.zero).dy;
final scrollOffset = position + _scrollController.offset - 100;
_scrollController.animateTo(scrollOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
}
}

void _updateQuantities(InvoiceDetailTempDto element) {
if (selectedPalletOption == 'palletChan') {
element.realQuantity = ((element.realQuantity ?? 0) + (element.boxQuantity ?? 1)).toInt().toDouble();
element.realQuantityDVT = (element.realQuantity! * (element.specification ?? 1)).toInt().toDouble();
} else if (selectedPalletOption == 'palletLe') {
element.realQuantity = ((element.realQuantity ?? 0) + 1).toInt().toDouble();
element.realQuantityDVT = (element.realQuantity! * (element.specification ?? 1)).toInt().toDouble();
} else if (selectedPalletOption == 'leDonViTinh') {
element.realQuantityDVT = ((element.realQuantityDVT ?? 0) + 1).toInt().toDouble();
element.realQuantity = (element.realQuantityDVT! / (element.boxQuantity ?? 1)).toInt().toDouble();
}
}

void _bringItemToTop(int index, bool isPromo) {
final item = invoices.removeAt(index);
invoices.insert(0, item);
setState(() {
_lastScannedProductCode = item.productCode;
if (isPromo) {
promoProducts = invoices.where((e) => e.spchinh == false).toList();
final promoIndex = promoProducts.indexWhere((e) => e.productCode == item.productCode);
if (promoIndex > 0) {
final promoItem = promoProducts.removeAt(promoIndex);
promoProducts.insert(0, promoItem);
}
mainProducts = invoices.where((e) => e.spchinh == true).toList();
} else {
mainProducts = invoices.where((e) => e.spchinh == true).toList();
final mainIndex = mainProducts.indexWhere((e) => e.productCode == item.productCode);
if (mainIndex > 0) {
final mainItem = mainProducts.removeAt(mainIndex);
mainProducts.insert(0, mainItem);
}
promoProducts = invoices.where((e) => e.spchinh == false).toList();
}
});
}

void _processBarcode(String barcode, {bool fromCamera = false}) {
if (barcode.isEmpty) return;
if (selectedPalletOption == null) {
Fluttertoast.showToast(msg: 'Chưa chọn hình thức', gravity: ToastGravity.BOTTOM, backgroundColor: Colors.orange, textColor: Colors.white);
return;
}

setState(() {
barcodeController.text = barcode;
hasScan = true;
});

final index = invoices.indexWhere((e) => e.productCode?.toLowerCase() == barcode.toLowerCase());
if (index == -1) {
Get.snackbar('Cảnh báo', 'Không tồn tại mã $barcode', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white, duration: const Duration(seconds: 2));
return;
}

final element = invoices[index];
_updateQuantities(element);
_bringItemToTop(index, element.spchinh == false);

setState(() {
if (element.spchinh == false) {
showOrderTable = false;
showPromoTable = true;
} else {
showOrderTable = true;
showPromoTable = true;
}
});

WidgetsBinding.instance.addPostFrameCallback((_) {
_scrollToSection(element.spchinh == false ? _firstPromoItemKey : _firstMainItemKey, element.spchinh == false ? _promoSectionKey : _mainSectionKey);
});

_playScanSound();

if (!fromCamera) {
Future.delayed(const Duration(milliseconds: 100), () {
barcodeController.selection = TextSelection(baseOffset: 0, extentOffset: barcodeController.text.length);
_barcodeFocusNode.requestFocus();
});
}
}

void scannerBarcode(String barcode) => _processBarcode(barcode);

void scannerBarcodeByCam(String barcode) {
if (scanCamera) _processBarcode(barcode, fromCamera: true);
}

void _onQRViewCreated(QRViewController controller) {
_qrViewController = controller;
if (scanCamera) controller.resumeCamera();
_qrSubscription = controller.scannedDataStream.debounce(const Duration(milliseconds: 300)).listen((scanData) {
if (scanData.code != null) scannerBarcodeByCam(scanData.code!);
});
}

void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
if (!p) {
Fluttertoast.showToast(msg: 'Không có quyền bật camera', gravity: ToastGravity.BOTTOM, backgroundColor: Colors.red, textColor: Colors.white);
}
}

void _saveInvoiceDetailTemp() {
context.read<InvoiceDetailTempBloc>().add(SaveInvoiceDetailTempEvent(invoices));
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
appBar: AppBar(
title: const Text('Phiếu tạm', style: TextStyle(fontWeight: FontWeight.w500)),
backgroundColor: theme.scaffoldBackgroundColor,
elevation: 0,
actions: [
IconButton(
icon: const Icon(Icons.refresh),
tooltip: 'Làm mới',
onPressed: _loadInvoiceDetails,
),
],
),
floatingActionButton: FloatingActionButton.extended(
onPressed: _saveInvoiceDetailTemp,
label: const Text(
  'Lưu tạm',
  style: TextStyle(fontSize: 14, color: Colors.white),
),
icon: const Icon(Icons.save, color: Colors.white),
backgroundColor: Colors.green,
),
body: _isLoading
? const Center(child: LinearProgressIndicator())
    : Column(
children: [
if (scanCamera)
Stack(
children: [
SizedBox(
height: 180,
child: _buildQrView(context),
),
Positioned(
top: 8,
right: 8,
child: IconButton(
icon: const Icon(Icons.close, color: Colors.white),
onPressed: _toggleCamera,
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
Text(
'${_invoiceData?.orderVoucher ?? ''} - ${customerNameController.text}',
style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
),
const SizedBox(height: 16),
Wrap(
spacing: 8,
children: [
FilterChip(
label: const Text('Lẻ Pallet'),
selected: selectedPalletOption == 'palletLe',
onSelected: (selected) => setState(() => selectedPalletOption = selected ? 'palletLe' : null),
selectedColor: Colors.blue.shade100,
),
FilterChip(
label: const Text('Chẵn Pallet'),
selected: selectedPalletOption == 'palletChan',
onSelected: (selected) => setState(() => selectedPalletOption = selected ? 'palletChan' : null),
selectedColor: Colors.blue.shade100,
),
FilterChip(
label: const Text('Lẻ ĐVT'),
selected: selectedPalletOption == 'leDonViTinh',
onSelected: (selected) => setState(() => selectedPalletOption = selected ? 'leDonViTinh' : null),
selectedColor: Colors.blue.shade100,
),
],
),
const SizedBox(height: 16),
Row(
children: [
Expanded(
child: TextField(
controller: barcodeController,
focusNode: _barcodeFocusNode,
readOnly: scanCamera,
textInputAction: TextInputAction.done,
onChanged: (value) => setState(() => hasScan = false),
onSubmitted: (value) {
if (!scanCamera) {
scannerBarcode(value);
FocusScope.of(context).unfocus();
}
},
  decoration: InputDecoration(
    labelText: 'Nhập mã vạch',
    hintText: 'Quét hoặc nhập mã vạch',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade400),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade400),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
    ),
    prefixIcon: const Icon(Icons.qr_code_scanner),
    suffixIcon: IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () => barcodeController.clear(),
    ),
    filled: true,
    fillColor: Colors.grey.shade50,
  ),
style: const TextStyle(fontSize: 13),
),
),
const SizedBox(width: 4),
Switch(
value: scanCamera,
onChanged: (val) => _toggleCamera(),
activeColor: Colors.blue,
),
const Text('Camera', style: TextStyle(fontSize: 11)),
],
),
const SizedBox(height: 8),
Container(
padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(8),
),
child: Row(
children: [
  Checkbox(
    value: _invoiceData?.isSaved ?? false,
    onChanged: (value) => setState(() => _invoiceData?.isSaved = value ?? false),
    checkColor: Colors.white,
    fillColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return Colors.green;
      }
      return Colors.grey[300];
    }),
  ),
const Text(
'Đã lưu tạm',
style: TextStyle(fontSize: 14, color: Colors.black),
),
],
),
),
const SizedBox(height: 24),
Container(
key: _mainSectionKey,
child: _buildSectionHeader('Sản phẩm đơn hàng 🛒 (${mainProducts.length})', showOrderTable, () => setState(() => showOrderTable = !showOrderTable)),
),
AnimatedContainer(
duration: const Duration(milliseconds: 300),
height: showOrderTable ? null : 0,
child: showOrderTable ? _buildItemList(mainProducts, isPromoList: false, firstItemKey: _firstMainItemKey) : const SizedBox.shrink(),
),
const SizedBox(height: 24),
Container(
key: _promoSectionKey,
child: _buildSectionHeader('Sản phẩm khuyến mãi 🎁 (${promoProducts.length})', showPromoTable, () => setState(() => showPromoTable = !showPromoTable)),
),
AnimatedContainer(
duration: const Duration(milliseconds: 300),
height: showPromoTable ? null : 0,
child: showPromoTable ? _buildItemList(promoProducts, isPromoList: true, firstItemKey: _firstPromoItemKey) : const SizedBox.shrink(),
),
const SizedBox(height: 100),
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
key: qrKey,
onQRViewCreated: _onQRViewCreated,
onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
overlay: QrScannerOverlayShape(borderColor: Colors.red, borderRadius: 10, borderLength: 30, borderWidth: 10),
formatsAllowed: _listFormats,
);
}

Widget _buildSectionHeader(String title, bool isVisible, VoidCallback onToggle) {
return GestureDetector(
onTap: onToggle,
child: Container(
padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
decoration: BoxDecoration(
color: Colors.grey.shade100,
borderRadius: BorderRadius.circular(8),
),
child: Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
Icon(isVisible ? Icons.expand_less : Icons.expand_more, color: Colors.grey[600]),
],
),
),
);
}

Widget _buildItemList(List<InvoiceDetailTempDto> items, {required bool isPromoList, required GlobalKey firstItemKey}) {
if (items.isEmpty) {
return const Padding(
padding: EdgeInsets.all(16.0),
child: Text('Không có sản phẩm', style: TextStyle(fontSize: 16, color: Colors.grey)),
);
}

final realQuantityControllers = items.map((item) => TextEditingController(text: item.realQuantity?.toInt().toString() ?? '')).toList();
final realQuantityDVTControllers = items.map((item) => TextEditingController(text: item.realQuantityDVT?.toInt().toString() ?? '')).toList();

return Column(
children: List.generate(items.length, (index) {
final item = items[index];
final isLastScanned = item.productCode == _lastScannedProductCode;
return AnimatedContainer(
duration: const Duration(milliseconds: 300),
decoration: BoxDecoration(
border: isLastScanned ? Border.all(color: Colors.blue, width: 2) : null,
borderRadius: BorderRadius.circular(12),
),
child: Card(
key: index == 0 ? firstItemKey : null,
margin: const EdgeInsets.symmetric(vertical: 6.0),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
elevation: isLastScanned ? 4 : 1,
child: Padding(
padding: const EdgeInsets.all(12.0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
SizedBox(width: 30, child: Text('${index + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
Expanded(
child: Text(
'${item.productCode} - ${item.productName}',
style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
),
),
],
),
const SizedBox(height: 8),
Row(
children: [
const SizedBox(width: 30),
Expanded(
child: Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Text('SLYC: ${item.quantity?.toInt() ?? 0}', style: const TextStyle(fontSize: 14, color: Colors.red)),
if (!isPromoList)
SizedBox(
width: 100,
child: TextField(
controller: realQuantityControllers[index],
enabled: selectedPalletOption != 'leDonViTinh' && selectedPalletOption != 'palletChan',
inputFormatters: [FilteringTextInputFormatter.digitsOnly],
onSubmitted: (value) {
if (selectedPalletOption == null) {
Get.snackbar('Cảnh báo', 'Chưa chọn hình thức', snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.orange, colorText: Colors.white, duration: const Duration(seconds: 2));
return;
}
final qty = double.tryParse(value) ?? 0;
item.realQuantity = qty.toInt().toDouble();
item.realQuantityDVT = (qty * (item.specification ?? 1)).toInt().toDouble();
realQuantityDVTControllers[index].text = item.realQuantityDVT?.toInt().toString() ?? '';
setState(() {});
},
decoration: const InputDecoration(
isDense: true,
hintText: 'SLTX(Thùng)',
border: OutlineInputBorder(),
contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
),
keyboardType: TextInputType.number,
textAlign: TextAlign.center,
style: const TextStyle(fontSize: 14),
),
),
SizedBox(
width: 100,
child: TextField(
controller: realQuantityDVTControllers[index],
enabled: selectedPalletOption != 'palletLe' && selectedPalletOption != 'palletChan',
inputFormatters: [FilteringTextInputFormatter.digitsOnly],
onSubmitted: (value) {
final qty = double.tryParse(value) ?? 0;
item.realQuantityDVT = qty.toInt().toDouble();
item.realQuantity = (qty / (item.specification ?? 1)).toInt().toDouble();
realQuantityControllers[index].text = item.realQuantity?.toInt().toString() ?? '';
setState(() {});
},
decoration: const InputDecoration(
isDense: true,
hintText: 'SLTX(ĐVT)',
border: OutlineInputBorder(),
contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
),
keyboardType: TextInputType.number,
textAlign: TextAlign.center,
style: const TextStyle(fontSize: 14),
),
),
],
),
),
],
),
const SizedBox(height: 8),
Padding(
padding: const EdgeInsets.only(left: 30.0),
child: Text(
'Thùng/pallet: ${item.boxQuantity ?? 1} | Quy cách: ${item.specification ?? 1}',
style: TextStyle(fontSize: 12, color: Colors.grey[600]),
),
),
],
),
),
),
);
}),
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
