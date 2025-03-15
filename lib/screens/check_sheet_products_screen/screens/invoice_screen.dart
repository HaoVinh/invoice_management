import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:invoice_management/screens/check_sheet_products_screen/model/invoice_dto.dart';
import 'package:stream_transform/stream_transform.dart';

import '../../../utils/date_utils.dart';
import '../core/check_sheet/check_sheet_cubit.dart';
import '../core/detail_bloc/product_bloc.dart';

class OrderFormScreen extends StatefulWidget {
  static const String routeName = '/invoice-screen';
  @override
  _OrderFormScreenState createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  List<Invoice> orderItems = [
    Invoice(id : null,productCode: "SP1", name: "Sản phẩm 1", quantity: 10, realQuantity: 5, boxQuantity: 2),
    Invoice(id : null,productCode: "SP2", name: "Sản phẩm 2", quantity: 20, realQuantity: 10, boxQuantity: 3),
  ];

  List<Invoice> promoItems = [
    Invoice(id : null,productCode: "SP3", name: "Sản phẩm 3", quantity: 15, realQuantity: 8, boxQuantity: 1),
    Invoice(id : null,productCode: "SP4", name: "Sản phẩm 4", quantity: 25, realQuantity: 12, boxQuantity: 4),
  ];

  bool scanCamera = false;
  String? selectedPalletOption;
  TextEditingController customerNameController = TextEditingController();
  TextEditingController vehicleNumberController = TextEditingController();
  TextEditingController warehouseKeeperController = TextEditingController();
  TextEditingController barcodeController = TextEditingController();
  FocusNode _barcodeFocusNode = FocusNode();
  bool showOrderTable = true;
  bool showPromoTable = true;

  bool hasScan = false;
  QRViewController? _qrViewController;
  late String _date;
  late ProductBloc _productBloc;
  late CheckSheetCubit _checkSheetCubit;
  late ScrollController _scrollController;
  int indexFocus = -1;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  initPermissions() async {
    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }
    return cameraStatus.isGranted;
  }
  StreamSubscription? _productSubscription;







  soundWhenScanned() async {
    final player = AudioPlayer();
    player.play(AssetSource('sounds/Scanner-Beep-Sound.wav'));
    print('Sound');
  }

  hideShowCamera() async {
    var grand = await initPermissions();
    if (grand) {
      setState(() {
        scanCamera = !scanCamera;
      });
    }
  }

  _beforeDispose() {
    try {
      var currentDate =
      dateUtils.getFormattedDateByCustom(DateTime.now(), "dd/MM/yyyy");
      var selectDate = _date.substring(0, 10);

    } catch (e) {}
  }

  // Giải phóng tài nguyên
  @override
  void dispose() {
    //save data
    _beforeDispose();
    _scrollController.dispose();
    barcodeController.dispose();
    _barcodeFocusNode.dispose();
    if (_qrViewController != null) {
      _qrViewController!.dispose();
    }
    _productSubscription?.cancel();
    super.dispose();
  }


  void _onTyping(String barcode){
    setState(() {
      hasScan = false;
    });
  }
  void _onBarcodeEntered(String barcode) {
    if (barcode.isNotEmpty) {

      barcodeController.text = barcode;
      // scannerBarcode(barcode);
    }

    setState(() {
      hasScan = true;
    });

    Future.delayed(Duration(milliseconds: 100), () {
      barcodeController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: barcodeController.text.length,
      );

      _barcodeFocusNode.requestFocus();
      setState(() {});
    });
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;

    if (Platform.isAndroid) {
      if (scanCamera) {
        _qrViewController?.pauseCamera();
      } else {
        _qrViewController?.resumeCamera();
      }
    } else {
      _qrViewController?.resumeCamera();
    }
    controller.scannedDataStream
        .debounce(const Duration(milliseconds: 300))
        .listen((scanData) {
      // scannerBarcode(scanData.code!);
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      Fluttertoast.showToast(
        msg: 'Không có quyền bật camera',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }

  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Đơn Hàng'),
        backgroundColor: Colors.red[50],
        foregroundColor: Colors.grey[800],
        elevation: 1,
      ),
      body: Column(
        children: [
          Visibility(
            visible: scanCamera,
            child: SizedBox(
              height: 250,
              child: _buildQrView(context),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Phần thông tin đầu vào
                        Row(
                          children: [
                            Expanded(child: buildTextField(customerNameController, "Tên khách hàng")),
                            SizedBox(width: 16),
                            Expanded(child: buildTextField(vehicleNumberController, "Số xe")),
                          ],
                        ),
                        SizedBox(height: 16),
                        buildTextField(warehouseKeeperController, "Thủ kho"),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildRadioOption("Lẻ Pallet", "palletLe"),
                            _buildRadioOption("Chẵn Pallet", "palletChan"),
                            _buildRadioOption("Lẻ ĐVT", "leDonViTinh"),
                          ],
                        ),
                        SizedBox(height: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: scanCamera,
                              onChanged: (val) => setState(() => scanCamera = val!),
                              activeColor: Colors.blue[300],
                              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                            ),
                            SizedBox(width: 2 ),
                            Text("Quét Camera"),
                            SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: barcodeController,
                                focusNode: _barcodeFocusNode,
                                onChanged: (value) {
                                  _onTyping(value);
                                },
                                onSubmitted: (value) {
                                  _onBarcodeEntered(value);
                                },
                                decoration: InputDecoration(
                                  labelText: "Mã vạch đã quét",
                                  hintText: "Quét mã hoặc nhập sản phẩm...",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.blue, width: 2),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade600),
                                    onPressed: () => barcodeController.clear(),
                                  ),
                                ),
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 24),
                        // Bảng "Sản phẩm đơn hàng"
                        _buildSectionHeader("Sản phẩm đơn hàng", showOrderTable, () {
                          Future.delayed(Duration(milliseconds: 300), () {
                            setState(() => showOrderTable = !showOrderTable);
                          });


                        }),
                        AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          height: showOrderTable ? null : 0, // Để tự điều chỉnh theo nội dung
                          child: showOrderTable
                              ? _buildItemList(orderItems, (index, updatedItem) {
                            setState(() => orderItems[index] = updatedItem);
                          }, (index) {
                            setState(() => orderItems.removeAt(index));
                          })
                              : SizedBox.shrink(), // Dùng SizedBox.shrink() thay vì null để tránh lỗi
                        ),
                        SizedBox(height: 24),
                        // Bảng "Sản phẩm khuyến mãi"
                        _buildSectionHeader("Sản phẩm khuyến mãi", showPromoTable, () {
                          Future.delayed(Duration(milliseconds: 300), () {
                            setState(() => showPromoTable = !showPromoTable);
                          });
                        }),
                        AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          height: showPromoTable ? null : 0, // Để tự điều chỉnh theo nội dung
                          child: showPromoTable
                              ? _buildItemList(promoItems, (index, updatedItem) {
                            setState(() => promoItems[index] = updatedItem);
                          }, (index) {
                            setState(() => promoItems.removeAt(index));
                          })
                              : SizedBox.shrink(),
                        ),
                        SizedBox(height: 100), // Khoảng trống cho nút cố định
                      ],
                    ),
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrView(BuildContext context) {
    if(scanCamera){
      return QRView(
          key: qrKey,
          onQRViewCreated: _onQRViewCreated,
          overlay: QrScannerOverlayShape(
              borderColor: Colors.red,
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 10),
          onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
          formatsAllowed: _listFormats);
    }
    return Container(); // Return empty container when camera is off
  }

  _noDataSection(String message) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(
              child: Text(
                message,
                style: const TextStyle(fontSize: 20),
              )),
        )
      ],
    );
  }

  Widget buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue[300]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildRadioOption(String title, String value) {
    return Row(
      children: [
        Radio(
          value: value,
          groupValue: selectedPalletOption,
          onChanged: (val) => setState(() => selectedPalletOption = val as String?),
          activeColor: Colors.blue[300],
        ),
        Text(title, style: TextStyle(color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildSectionHeader(String title, bool isVisible, VoidCallback onToggle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        IconButton(
          icon: Icon(
            isVisible ? Icons.expand_less : Icons.expand_more,
            color: Colors.grey[600],
          ),
          onPressed: onToggle,
        ),
      ],
    );
  }

  Widget _buildItemList(List<Invoice> items, Function(int, Invoice) onUpdate, Function(int) onDelete) {
    return Column(
      children: [
        // Tiêu đề cột (chỉ render 1 lần)
        Container(
          padding: (EdgeInsets.fromLTRB(12.0, 0, 0, 0)),
          decoration: BoxDecoration(
            color: Colors.pink[50],
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text('Mã SP', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]))),
              SizedBox(width: 10),
              Expanded(flex: 1, child: Text('Tên SP', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]))),
              SizedBox(width: 26),
              Expanded(flex: 1, child: Text('SL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]))),
              Expanded(flex: 0, child: Text('TX', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]))),
              SizedBox(width: 26),
              Expanded(flex: 1, child: Text('Thùng', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]))),
              SizedBox(width: 16),
              SizedBox(width: 40), // Khoảng trống cho nút xóa
            ],
          ),
        ),
        // Danh sách sản phẩm
        Container(
          constraints: BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.pink[50]!, Colors.white], // Gradient từ xanh nhạt đến trắng
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: BouncingScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return OrderItemRow(
                item: items[index],
                index: index,
                onUpdate: (updatedItem) => onUpdate(index, updatedItem),
                onDelete: () => onDelete(index),
              );
            },
          ),
        ),
      ],
    );
  }


}

class OrderItemRow extends StatefulWidget {
  final Invoice item;
  final int index;
  final Function(Invoice) onUpdate;
  final VoidCallback onDelete;

  OrderItemRow({
    required this.item,
    required this.index,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  _OrderItemRowState createState() => _OrderItemRowState();
}

class _OrderItemRowState extends State<OrderItemRow> {
  late TextEditingController productCodeController;
  late TextEditingController nameController;
  late TextEditingController quantityController;
  late TextEditingController realQuantityController;
  late TextEditingController boxQuantityController;

  @override
  void initState() {
    super.initState();
    productCodeController = TextEditingController(text: widget.item.productCode);
    nameController = TextEditingController(text: widget.item.name);
    quantityController = TextEditingController(text: widget.item.quantity.toString());
    realQuantityController = TextEditingController(text: widget.item.realQuantity.toString());
    boxQuantityController = TextEditingController(text: widget.item.boxQuantity.toString());
  }


  //Giải phóng tài nguyên
  @override
  void dispose() {
    productCodeController.dispose();
    nameController.dispose();
    quantityController.dispose();
    realQuantityController.dispose();
    boxQuantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(

      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Colors.red[200],
      child: Padding(

        padding: EdgeInsets.all(12.0),
        child: Row(

          children: [

            Expanded(flex: 1, child: buildTableTextField(productCodeController, '')),
            SizedBox(width: 8),
            Expanded(flex: 2, child: buildTableTextField(nameController, '')),
            SizedBox(width: 8),
            Expanded(flex: 1, child: buildTableTextField(quantityController, '', isNumber: true)),
            SizedBox(width: 8),
            Expanded(flex: 1, child: buildTableTextField(realQuantityController, '', isNumber: true)),
            SizedBox(width: 8),
            Expanded(flex: 1, child: buildTableTextField(boxQuantityController, '', isNumber: true)),
            SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red[300]),
              onPressed: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTableTextField(TextEditingController controller, String label, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
        border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue[300]!)),
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontSize: 14),
      onChanged: (value) {
        widget.onUpdate(
          Invoice(
            id : null,
            productCode: productCodeController.text,
            name: nameController.text,
            quantity: int.tryParse(quantityController.text) ?? 0,
            realQuantity: int.tryParse(realQuantityController.text) ?? 0,
            boxQuantity: int.tryParse(boxQuantityController.text) ?? 0,
          ),
        );
      },
    );
  }
}
const _listFormats = [
  BarcodeFormat.aztec,

  /// CODABAR 1D format.
  /// Not supported in iOS
  BarcodeFormat.codabar,

  /// Code 39 1D format.
  BarcodeFormat.code39,

  /// Code 93 1D format.
  BarcodeFormat.code93,

  /// Code 128 1D format.
  BarcodeFormat.code128,

  /// Data Matrix 2D barcode format.
  BarcodeFormat.dataMatrix,

  /// EAN-8 1D format.
  BarcodeFormat.ean8,

  /// EAN-13 1D format.
  BarcodeFormat.ean13,

  /// ITF (Interleaved Two of Five) 1D format.
  BarcodeFormat.itf,

  /// MaxiCode 2D barcode format.
  /// Not supported in iOS.
  BarcodeFormat.maxicode,

  /// PDF417 format.
  BarcodeFormat.pdf417,

  /// QR Code 2D barcode format.
  BarcodeFormat.qrcode,

  /// RSS 14
  /// Not supported in iOS.
  BarcodeFormat.rss14,

  /// RSS EXPANDED
  /// Not supported in iOS.
  BarcodeFormat.rssExpanded,

  /// UPC-A 1D format.
  /// Same as ean-13 on iOS.
  BarcodeFormat.upcA,

  /// UPC-E 1D format.
  BarcodeFormat.upcE,

  /// UPC/EAN extension format. Not a stand-alone format.
  BarcodeFormat.upcEanExtension,
];