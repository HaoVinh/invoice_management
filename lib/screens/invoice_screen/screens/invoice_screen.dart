import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:invoice_management/screens/invoice_screen/model/invoice_detail_temp_dto.dart';
import 'package:invoice_management/screens/invoice_screen/model/invoice_temp_dto.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_detail_temp_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:stream_transform/stream_transform.dart';
import '../../../constants/colors.dart';
import '../../../utils/date_utils.dart';
import '../core/invoice_detail_temp_bloc.dart';
import '../core/invoice_detail_temp_event.dart';
import '../core/invoice_detail_temp_state.dart';
import '../core/invoice_temp_bloc.dart';
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
  TextEditingController customerNameController = TextEditingController();
  TextEditingController barcodeController = TextEditingController();
  FocusNode _barcodeFocusNode = FocusNode();
  bool showOrderTable = true;
  bool showPromoTable = true;
  bool hasScan = false;
  bool _isLoading = false;
  QRViewController? _qrViewController;
  late String _date;
  late ScrollController _scrollController;
  int indexFocus = -1;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  List<InvoiceDetailTempDto> details =[];
  List<InvoiceDetailTempDto> invoices = [];
  List<InvoiceDetailTempDto> mainProducts = [];
  List<InvoiceDetailTempDto> promoProducts = [];
  late InvoiceDetailTempRepository _invoiceDetailTempRepository;
  InvoiceTempDto? _invoiceData; // Lưu thông tin hóa đơn

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
    _scrollController = ScrollController();
    _date = dateUtils.getFormattedDateByCustom(DateTime.now(), "dd/MM/yyyy");
    _invoiceDetailTempRepository = InvoiceDetailTempRepository();
    _invoiceData = Get.arguments as InvoiceTempDto?;
    // print('Received invoice data: ${_invoiceData?.toJson()}');
    if (_invoiceData != null) {
      customerNameController.text = _invoiceData!.customerName ?? '';
      _loadInvoiceDetails();
    } else {
      setState(() {
        _isLoading = false;
      });
      Get.snackbar(
        'Lỗi',
        'Dữ liệu hóa đơn không hợp lệ',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
    _barcodeFocusNode.addListener(() {
      if (_barcodeFocusNode.hasFocus) {
        setState(() {});
      }
    });
  }

  Future<void> _loadInvoiceDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      details = await _invoiceDetailTempRepository.searchInvoiceDetail(
        cm: 'list_invoice_detail_temps',
        idInvoice: _invoiceData!.idInvoice,
      );
      // print('Received details: ${details.map((e) => e.toJson())}');

      for (var newItem in details) {
        final existingItem = invoices.firstWhere(
              (item) => item.productCode == newItem.productCode,
          orElse: () => newItem,
        );
        newItem.realQuantity = existingItem.realQuantity ?? newItem.realQuantity;
        newItem.realQuantityDVT = existingItem.realQuantityDVT ?? newItem.realQuantityDVT;
      }

      setState(() {
        invoices = details;
        // print('Updated invoices: ${invoices.map((e) => e.toJson())}');
        mainProducts = invoices.where((item) => item.spchinh == true).toList();
        promoProducts = invoices.where((item) => item.spchinh == false).toList();
        // print('Main products: ${mainProducts.map((e) => e.toJson())}');
        // print('Promo products: ${promoProducts.map((e) => e.toJson())}');
        _isLoading = false;
      });

      if (details.isEmpty) {
        Get.snackbar(
          'Thông báo',
          'Không có chi tiết hóa đơn cho ID: ${_invoiceData!.idInvoice}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e, stackTrace) {
      print('Error in _loadInvoiceDetails: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        invoices = [];
        mainProducts = [];
        promoProducts = [];
        _isLoading = false;
      });
      Get.snackbar(
        'Lỗi',
        'Không thể tải chi tiết hóa đơn: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  StreamSubscription? _productSubscription;

  Future<bool> initPermissions() async {
    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }
    return cameraStatus.isGranted;
  }

  void soundWhenScanned() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/Scanner-Beep-Sound.wav'));
    print('Sound played');
  }

  void hideShowCamera() async {
    var granted = await initPermissions();
    if (granted) {
      setState(() {
        scanCamera = !scanCamera;
        if (scanCamera) {
          // Tắt bàn phím và bỏ focus khi bật camera

          if (_qrViewController != null) {
            _qrViewController!.resumeCamera();
          }
        } else {
          // Bật lại focus cho TextField khi tắt camera
          _barcodeFocusNode.requestFocus();
          if (_qrViewController != null) {
            _qrViewController!.pauseCamera();
          }
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
    _productSubscription?.cancel();
    super.dispose();
  }

  void _onTyping(String barcode) {
    setState(() {
      hasScan = false;
    });
  }

  void _onBarcodeEntered(String barcode) {
    if (barcode.isNotEmpty) {
      barcodeController.text = barcode;
      scannerBarcode(barcode);
    }
    setState(() {
      hasScan = true;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      barcodeController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: barcodeController.text.length,
      );
      _barcodeFocusNode.requestFocus();
    });
  }

  void scannerBarcodeByCam(String barcode) {
    if (scanCamera && barcode.isNotEmpty) {
      setState(() {
        barcodeController.text = barcode;
        hasScan = true;
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        barcodeController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: barcodeController.text.length,
        );
      });

      // if (selectedPalletOption == null) {
      //   Fluttertoast.showToast(
      //     msg: 'Chưa chọn hình thức',
      //     toastLength: Toast.LENGTH_SHORT,
      //     gravity: ToastGravity.BOTTOM,
      //     backgroundColor: Colors.orange,
      //     textColor: Colors.white,
      //     fontSize: 16.0,
      //   );
      //   return;
      // }

      bool isBarcodeFound = false;
      for (var i = 0; i < invoices.length; i++) {
        var element = invoices[i];
        if (element.productCode == barcode) {
          setState(() {
            if (selectedPalletOption != null) {
              if (selectedPalletOption == 'palletChan') {
                element.realQuantity =  (element.realQuantity ?? 0) + (element.boxQuantity ?? 0);
                element.realQuantityDVT = (element.realQuantity ?? 0) * (element.specification ?? 0);
              } else if (selectedPalletOption == 'palletLe') {
                element.realQuantity = (element.realQuantity ?? 0) + 1;
                element.realQuantityDVT = (element.realQuantity ?? 0) * (element.specification ?? 0);
              } else if (selectedPalletOption == 'leDonViTinh') {
                element.realQuantityDVT = (element.realQuantityDVT ?? 0) + 1;
                element.realQuantity = (element.realQuantityDVT ?? 0) / (element.boxQuantity ?? 0);
              }
              _bringItemToTop(i);
            }
          });

          soundWhenScanned();
          isBarcodeFound = true;
          break;
        }
      }

      if (!isBarcodeFound) {
        Get.snackbar(
          'Cảnh báo',
          'Không tồn tại mã $barcode trong danh sách',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  void scannerBarcode(String barcode){
    if (barcode.isNotEmpty) {
      barcodeController.text = barcode;

      setState(() {
        hasScan = true;
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        barcodeController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: barcodeController.text.length,
        );
        FocusScope.of(context).requestFocus(_barcodeFocusNode);
      });


      if(selectedPalletOption == null){
        Fluttertoast.showToast(
          msg: 'Chưa chọn hình thức',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.orange,
          textColor: Colors.white,
          fontSize: 16.0,
        );
        return;
      }
       bool isBarcodeFound = false;
      for (var i = 0; i < invoices.length; i++) {
        var element = invoices[i];

        if (element.productCode == barcode) {
          setState(() {
            if(selectedPalletOption != null){

              if (selectedPalletOption == 'palletChan') {
                element.realQuantity = (element.realQuantity ?? 0) + (element.boxQuantity??0);
                element.realQuantityDVT = (element.realQuantityDVT ?? 0) +((element.boxQuantity??0) * (element.specification??0));
              }

              else if(selectedPalletOption == 'palletLe') {
                element.realQuantity = (element.realQuantity ?? 0) + 1;
                element.realQuantityDVT = (element.realQuantityDVT ?? 0) +((element.boxQuantity??0) * (element.specification??0));
              }else if(selectedPalletOption == 'leDonViTinh'){
                element.realQuantityDVT = (element.realQuantityDVT ?? 0) + 1;
                element.realQuantity = (element.realQuantityDVT ?? 0) / (element.boxQuantity ?? 0);
              }
            }
            _bringItemToTop(i);
          });

          isBarcodeFound = true;
          break;
        }

      }
  if(!isBarcodeFound){
    Get.snackbar(
      'Cảnh báo',
      'Không tồn tại mã $barcode trong danh sách',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red,
      colorText: Colors.white,
    );
  }
  return;
    }
  }
  void _bringItemToTop(int index) {
    setState(() {
      final item = invoices.removeAt(index);
      invoices.insert(0, item);
      mainProducts = invoices.where((item) => item.spchinh == true).toList();
      promoProducts = invoices.where((item) => item.spchinh == false).toList();
      indexFocus = 0;
    });
  }
  void _onQRViewCreated(QRViewController controller) {
    _qrViewController = controller;

    if (Platform.isAndroid) {
      if (!scanCamera) {
        _qrViewController!.resumeCamera();
      }
    } else {
      _qrViewController!.resumeCamera();
    }

    controller.scannedDataStream
        .debounce(const Duration(milliseconds: 300))
        .listen((scanData) {
      if (scanData.code != null) {
        scannerBarcodeByCam(scanData.code!);
      }
    });
  }

  // void _saveInvoice() {
  //   if (_invoiceData == null || invoices.isEmpty) {
  //     Get.snackbar(
  //       'Lỗi',
  //       'Dữ liệu hóa đơn hoặc chi tiết hóa đơn không hợp lệ',
  //       snackPosition: SnackPosition.BOTTOM,
  //       backgroundColor: Colors.red,
  //       colorText: Colors.white,
  //     );
  //     return;
  //   }
  //
  //   // Tạo InvoiceTempDTO để gửi lên BLoC
  //   final invoiceTempDTO = InvoiceTempDto(
  //     idInvoice: _invoiceData!.idInvoice,
  //     customerCode: _invoiceData!.customerCode,
  //     customerName: _invoiceData!.customerName,
  //     orderCode: _invoiceData!.orderCode,
  //     orderVoucher: _invoiceData!.orderVoucher,
  //       invoiceDate:_invoiceData!.invoiceDate,
  //       taxValue:  _invoiceData!.taxValue,
  //     warehouseCode:  _invoiceData!.warehouseCode ,
  //       ieCategories: _invoiceData!.ieCategories,
  //       content:  _invoiceData!.content,
  //       note : _invoiceData!.note,
  //       tongTien : _invoiceData!.tongTien,
  //       thue: _invoiceData!.thue,
  //       poNo : _invoiceData!.poNo,
  //       lookupCode:  _invoiceData!.lookupCode,
  //       delivery_date: _invoiceData!.delivery_date,
  //     voucher_code: _invoiceData!.voucher_code,
  //     orderId: _invoiceData!.orderId,
  //     invoiceDetailTemps: invoices.map((item) => InvoiceDetailTempDto(
  //       invoiceDetailId: item.invoiceDetailId,
  //       productCode: item.productCode,
  //       productName: item.productName,
  //       quantity: item.quantity,
  //       boxQuantity: item.boxQuantity,
  //       specification: item.specification,
  //       productDHCode: item.productDHCode,
  //       spchinh: item.spchinh,
  //       realQuantity: item.realQuantity,
  //       realQuantityDVT: item.realQuantityDVT,
  //       unit_price: item.unit_price,
  //     )).toList(),
  //   );
  //
  //   // Gửi sự kiện SaveInvoiceTempEvent đến BLoC
  //    context.read<InvoiceTempBloc>().add(SaveInvoiceTempEvent(invoiceTempDTO));
  //
  //
  // }

  void _saveInvoiceDetailTemp() {
    if (details.isEmpty) {
      Get.snackbar(
        'Lỗi',
        'Dữ liệu chi tiết hóa đơn không hợp lệ',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final invoiceDetailTempDtos = details.map((item) => InvoiceDetailTempDto(
      invoiceDetailId: item.invoiceDetailId,
      productCode: item.productCode,
      productName: item.productName,
      quantity: item.quantity,
      boxQuantity: item.boxQuantity,
      specification: item.specification,
      productDHCode: item.productDHCode,
      spchinh: item.spchinh,
      realQuantity: item.realQuantity,
      realQuantityDVT: item.realQuantityDVT,
      unit_price: item.unit_price,
        invoiceTempId:item.invoiceTempId,
    )).toList();

    context.read<InvoiceDetailTempBloc>().add(SaveInvoiceDetailTempEvent(invoiceDetailTempDtos));
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
    return MultiBlocListener(
      listeners: [
        BlocListener<InvoiceTempBloc, InvoiceTempState>(
          listener: (context, state) {
            if (state is InvoiceTempSaved) {
              Get.snackbar(
                'Thành công',
                'Chuyển hóa đơn thành công!',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            } else if (state is InvoiceTempError) {
              Get.snackbar(
                'Lỗi',
                state.message,
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            }
          },
        ),
        BlocListener<InvoiceDetailTempBloc, InvoiceDetailTempState>(
          listener: (context, state) {
            if (state is InvoiceDetailTempSaved) {
              Get.snackbar(
                'Thành công',
                'Lưu chi tiết hóa đơn tạm thành công!',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.green,
                colorText: Colors.white,
              );
            } else if (state is InvoiceDetailTempError) {
              Get.snackbar(
                'Lỗi',
                state.message,
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.red,
                colorText: Colors.white,
              );
            }
          },
        ),
      ],

    child: Scaffold(
      appBar: AppBar(
        title: Text('Phiếu tạm'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvoiceDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                  physics: const BouncingScrollPhysics(),
                  controller: _scrollController,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 0, top: 0.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hiển thị thông tin hóa đơn
                        Row(
                          children: [
                            Expanded(
                              child: buildLabel(
                                "",
                                '${_invoiceData?.orderVoucher} - ${customerNameController.text}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildRadioOption("Lẻ Pallet", "palletLe"),
                            _buildRadioOption("Chẵn Pallet", "palletChan"),
                            _buildRadioOption("Lẻ ĐVT", "leDonViTinh"),
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
                            showCursor: !scanCamera,
                            onChanged: (value) {
                              if (!scanCamera) {
                                _onTyping(value);
                              }},
                                onEditingComplete: () {
                                  if (!scanCamera) {
                                    _onBarcodeEntered(barcodeController.text);
                                  }

                                },
                                decoration: InputDecoration(
                                  labelText: "Mã vạch",
                                  labelStyle: const TextStyle(fontSize: 8),
                                  hintText: "Mã vạch đã quét",
                                  hintStyle: const TextStyle(fontSize: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.clear, size: 16, color: Colors.grey.shade600),
                                    onPressed: () {
                                      barcodeController.clear();
                                      _barcodeFocusNode.unfocus();
                                    },
                                  ),
                                ),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Checkbox(
                              value: scanCamera,
                              onChanged: (val) => hideShowCamera(),
                              activeColor: Colors.blue[300],
                              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: BorderSide(color: Colors.grey.shade400, width: 1),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "Camera",
                              style: TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // ElevatedButton(
                            //   onPressed: _saveInvoice,
                            //   style: ElevatedButton.styleFrom(
                            //     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            //     minimumSize: const Size(65, 30),
                            //     textStyle: const TextStyle(fontSize: 12),
                            //     foregroundColor: Colors.black,
                            //     shape: RoundedRectangleBorder(
                            //       borderRadius: BorderRadius.circular(5),
                            //     ),
                            //     elevation: 2,
                            //   ),
                            //   child: Row(
                            //     mainAxisSize: MainAxisSize.min,
                            //     children: const [
                            //       Icon(Icons.send, size: 12),
                            //       SizedBox(width: 4),
                            //       Text("Chuyển hóa đơn"),
                            //     ],
                            //   ),
                            // ),
                            // const SizedBox(width: 6),
                            Expanded(
                              flex: 1,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _invoiceData?.isSaved,
                                    onChanged: (value) {
                                      setState(() {
                                        _invoiceData?.isSaved= value ?? false;
                                      });
                                    },
                                    visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                                  ),
                                  Text(
                                    "Đã lưu tạm",
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _saveInvoiceDetailTemp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade500,
                                foregroundColor: Colors.white, // Màu icon và text
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                minimumSize: const Size(65, 30),
                                textStyle: const TextStyle(fontSize: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                elevation: 3,
                                shadowColor: Colors.green.shade500,
                              ).copyWith(
                                // Hover effect
                                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                                      (Set<MaterialState> states) {
                                    if (states.contains(MaterialState.hovered) || states.contains(MaterialState.pressed)) {
                                      return Colors.green.shade800; // Màu khi hover hoặc nhấn
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.save, size: 14, color: Colors.white), // icon trắng
                                  const SizedBox(width: 8),
                                  const Text("Lưu tạm", style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),

                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          "Sản phẩm đơn hàng",
                          showOrderTable,
                              () {
                            setState(() => showOrderTable = !showOrderTable);
                          },
                        ),
                        ClipRect(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            height: showOrderTable ? null : 0,
                            child: showOrderTable
                                ? _buildItemList(mainProducts, isPromoList: false) // Sản phẩm đơn hàng
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionHeader(
                          "Sản phẩm khuyến mãi",
                          showPromoTable,
                              () {
                            setState(() => showPromoTable = !showPromoTable);
                          },
                        ),
                        ClipRect(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            height: showPromoTable ? null : 0,
                            child: showPromoTable
                                ? _buildItemList(promoProducts, isPromoList: true)
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildQrView(BuildContext context) {
    if (scanCamera) {
      return QRView(
        key: qrKey,
        onQRViewCreated: _onQRViewCreated,
        overlay: QrScannerOverlayShape(
          borderColor: Colors.red,
          borderRadius: 10,
          borderLength: 30,
          borderWidth: 10,
        ),
        onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
        formatsAllowed: _listFormats,
      );
    }
    return Container();
  }
  Widget buildLabel(String label, String value) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200), // Giới hạn chiều rộng tối đa
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : "Chưa có thông tin",
            style: const TextStyle(
              fontSize: 18,
              color: Colors.black,
            ),
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
        ],
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
        Text(title, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      ],
    );
  }

  Widget _buildSectionHeader(String title, bool isVisible, VoidCallback onToggle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(color: Colors.grey[700], fontSize: 14, fontWeight: FontWeight.bold),
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

  Widget _buildItemList(List<InvoiceDetailTempDto> items, {required bool isPromoList}) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Không có sản phẩm',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    // Tạo danh sách TextEditingController cho từng sản phẩm trong items
    final List<TextEditingController> realQuantityControllers = [];
    final List<TextEditingController> realQuantityDVTControllers = [];

    for (var item in items) {
      realQuantityControllers.add(TextEditingController(text: item.realQuantity?.toString() ?? ''));
      realQuantityDVTControllers.add(TextEditingController(text: item.realQuantityDVT?.toString() ?? ''));
    }

    return Column(
      children: [
        // Container(
        //   padding: const EdgeInsets.fromLTRB(4.0, 8.0, 4.0, 8.0),
        //   decoration: BoxDecoration(
        //     color: Colors.grey[50],
        //     borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        //   ),
        //   child: Row(
        //     children: [
        //       SizedBox(
        //         width: 30,
        //         child: Text(
        //           'STT',
        //           style: TextStyle(
        //             fontWeight: FontWeight.bold,
        //             color: Colors.grey[800],
        //             fontSize: 12,
        //           ),
        //         ),
        //       ),
        //       Expanded(
        //         child: Text(
        //           'Sản phẩm',
        //           style: TextStyle(
        //             fontWeight: FontWeight.bold,
        //             color: Colors.grey[800],
        //             fontSize: 12,
        //           ),
        //         ),
        //       ),
        //     ],
        //   ),
        // ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.grey[50]!, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(items.length, (index) {
              final item = items[index];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${item.productCode} - ${item.productName}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const SizedBox(width: 30), // Cột STT
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Cột SLYC (item.quantity)
                                Container(
                                  width: 65, // Cố định chiều rộng cho cột SLYC
                                  child: Row(
                                    children: [
                                      Text(
                                        'SLYC: ',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                      Flexible(
                                        child: Text(
                                          '${item.quantity != null
                                              ? (item.quantity == item.quantity?.toInt()
                                              ? item.quantity?.toInt().toString() // Hiển thị số nguyên
                                              : item.quantity!.toStringAsFixed(2)) // Hiển thị số thập phân với 2 chữ số
                                              : '0'}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                          overflow: TextOverflow.visible,
                                          softWrap: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Hiển thị cột "SLTX (Thùng)" chỉ khi không phải là danh sách khuyến mãi
                                if (!isPromoList) ...[
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: realQuantityControllers[index],
                                      enabled:selectedPalletOption != 'leDonViTinh' && selectedPalletOption != 'palletChan' ,
                                      onEditingComplete: () {
                                        if (selectedPalletOption == null) {
                                          Get.snackbar(
                                            'Cảnh báo',
                                            'Chưa chọn hình thức ',
                                            snackPosition: SnackPosition.BOTTOM,
                                            backgroundColor: Colors.orange,
                                            colorText: Colors.white,
                                          );
                                          return;
                                        }
                                        // Cập nhật realQuantity cho sản phẩm chính
                                        final text = realQuantityControllers[index].text;
                                        final qty = double.tryParse(text) ?? 0;
                                        item.realQuantity = qty;
                                        item.realQuantityDVT = qty * (item.specification ?? 0);

                                        // Cập nhật ô DVT (chỉ khi khác text cũ)
                                        final newText = item.realQuantityDVT?.toString() ?? '';
                                        if (realQuantityDVTControllers[index].text != newText) {
                                          realQuantityDVTControllers[index].text = newText;
                                        }

                                        setState(() {});
                                      },
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.redAccent,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        hintText: 'SLTX(Thùng)',
                                        contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                                // Luôn hiển thị cột "SLTX (ĐVT)"
                                SizedBox(
                                  width: 100,
                                  child: TextField(
                                    controller: realQuantityDVTControllers[index],
                                    enabled: selectedPalletOption != 'palletLe' && selectedPalletOption != 'palletChan',
                                    onEditingComplete: () {
                                      // Cập nhật realQuantityDVT cho sản phẩm chính
                                      final text = realQuantityDVTControllers[index].text;
                                      final qty = double.tryParse(text) ?? 0;
                                      item.realQuantityDVT = qty;
                                      item.realQuantity = qty / (item.specification ?? 1);

                                      // Cập nhật ô DVT (chỉ khi khác text cũ)
                                      final newText = item.realQuantity?.toString() ?? '';
                                      if (realQuantityControllers[index].text != newText) {
                                        realQuantityControllers[index].text = newText;
                                      }

                                      setState(() {});
                                    },
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.redAccent,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'SLTX(ĐVT)',
                                      contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 30.0),
                        child: Text(
                          'Thùng/pallet: ${item.boxQuantity} | Quy cách: ${item.specification}',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
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