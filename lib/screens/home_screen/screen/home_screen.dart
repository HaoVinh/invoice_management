import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get/get.dart';
import 'package:invoice_management/screens/invoice_screen/model/invoice_detail_temp_dto.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_temp_repository.dart';
import 'package:invoice_management/constants/colors.dart';
import 'package:invoice_management/screens/auth_screen/core/auth_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../auth_screen/model/Brand.dart';
import '../../../constants/contains.dart';
import '../../auth_screen/repository/auth_repostory.dart';
import '../../invoice_screen/core/invoice_temp_bloc.dart';
import '../../invoice_screen/model/car_dto.dart';
import '../../invoice_screen/model/invoice_temp_dto.dart';
import '../../invoice_screen/repository/invoice_detail_temp_repository.dart';
import '../../invoice_screen/screens/invoice_screen.dart';
import '../../screens.dart';
import 'package:intl/intl.dart';

class HomeInvoiceScreen extends StatefulWidget {
  static const String routeName = '/home-screen';

  const HomeInvoiceScreen({Key? key}) : super(key: key);

  @override
  State<HomeInvoiceScreen> createState() => _HomeInvoiceScreenState();
}

class _HomeInvoiceScreenState extends State<HomeInvoiceScreen> {
  DateTime selectedStartDate =
      DateTime.now().subtract(Duration(days: 15)).copyWith(
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
            microsecond: 0,
          );

  DateTime selectedEndDate = DateTime.now().copyWith(
    hour: 23,
    minute: 59,
    second: 59,
    millisecond: 999,
    microsecond: 999999,
  );

  final _storage = const FlutterSecureStorage();
  String? _codeNV;
  bool _isLoadingCodeNV = true;
  String _selectedOrderType = 'LIX'; // 'LIX' hoac 'GIA_CONG'
  final Map<int, bool> _expandedInvoices = {};
  final Map<int, List<InvoiceDetailTempDto>> _invoiceDetailsCache = {};
  final Map<int, bool> _showAllMainProducts = {};
  final Map<int, bool> _showAllPromoProducts = {};

  @override
  void initState() {
    super.initState();
    _loadCodeNV(); // Tải codeNV khi khởi tạo
  }

  Future<void> _loadCodeNV() async {
    final authRepo = AuthRepository();
    final loginDTO = await authRepo.getSavedLoginDTO();
    if (loginDTO != null && loginDTO.code != null) {
      setState(() {
        _codeNV = loginDTO.code;
        _isLoadingCodeNV = false;
      });
      _refreshInvoiceList(context);
    } else {
      setState(() {
        _isLoadingCodeNV = false;
      });
      Get.snackbar(
        'Lỗi',
        'Không tìm thấy thông tin đăng nhập hoặc mã nhân viên',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      Get.offAllNamed(LoginScreen.routeName); // Chuyển về màn hình đăng nhập
    }
  }

  void _refreshInvoiceList(BuildContext context) {
    if (_codeNV == null) {
      Get.snackbar(
        'Lỗi',
        'Chưa có mã nhân viên, vui lòng đăng nhập lại',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    print(
        'Đang làm mới danh sách hóa đơn của mã NV: $_codeNV, loại: $_selectedOrderType');
    context.read<InvoiceTempBloc>().add(FetchInvoiceTempsEvent(
          cm: 'list_invoice_temps',
          sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
          eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
          codeNV: _codeNV!,
          maNX: _selectedOrderType == 'GIA_CONG' ? 'D' : null,
          statusNX: '0',
        ));
  }

  Future<bool> _handleWillPop() async {
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
        icon: const Icon(Icons.info, color: Colors.white),
        mainButton: TextButton(
          onPressed: () {
            Get.back();
          },
          child: const Icon(Icons.close, color: Colors.white),
        ),
      );
      return false;
    }
    SystemNavigator.pop();
    return true;
  }

  void _handleLogout() {
    String logoutStatus = '';
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
      icon: const Icon(Icons.info, color: Colors.white),
      progressIndicatorValueColor:
          const AlwaysStoppedAnimation<Color>(Colors.green),
      mainButton: TextButton(
        onPressed: () {
          logoutStatus = 'CANCEL';
          Get.back();
        },
        child: const Text("Huỷ", style: TextStyle(color: Colors.white)),
      ),
      showProgressIndicator: true,
      progressIndicatorBackgroundColor: Colors.white,
      snackbarStatus: (status) async {
        if (status == SnackbarStatus.CLOSED && logoutStatus != 'CANCEL') {
          await _storage.delete(key: 'exporting_invoices');
          await _storage.delete(key: 'member');
          await _storage.delete(key: 'access_token');
          print('Cleared exporting_invoices and login data on logout');
          Get.offAllNamed(LoginScreen.routeName);
        }
      },
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    DateTime initialDate = isStartDate ? selectedStartDate : selectedEndDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          selectedStartDate = picked.copyWith(
              hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
        } else {
          selectedEndDate = picked.copyWith(
              hour: 23,
              minute: 59,
              second: 59,
              millisecond: 999,
              microsecond: 999999);
        }
      });
      _refreshInvoiceList(context);
    }
  }

  Future<void> _loadDetailsExpanded(InvoiceTempDto invoice) async {
    final id = invoice.idInvoice;
    if (_invoiceDetailsCache.containsKey(id)) return; // Đã load rồi thì skip

    try {
      final repo = InvoiceDetailTempRepository();
      final details = await repo.searchInvoiceDetail(
        cm: 'list_invoice_detail_temps',
        idInvoice: id,
      );

      setState(() {
        _invoiceDetailsCache[id] = details;
      });
    } catch (e) {
      Get.snackbar('Lỗi', 'Không tải được chi tiết đơn hàng gia công: $e',
          backgroundColor: Colors.red);
    }
  }

  void _showSearchDialog(BuildContext blocContext) {
    showDialog(
      context: blocContext,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (BuildContext dialogContext) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            title: Row(
              children: [
                const Icon(Icons.search, color: kPrimaryColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Tìm kiếm',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
              ],
            ),
            content: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TextButton.icon(
                          onPressed: () async {
                            await _selectDate(dialogContext, true);
                            setDialogState(() {});
                          },
                          icon: const Icon(
                            Icons.date_range,
                            size: 20,
                            color: Colors.black,
                          ),
                          label: Text(
                            'Từ: ${DateFormat('dd/MM/yyyy').format(selectedStartDate)}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black87),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            minimumSize: const Size(double.infinity, 0),
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TextButton.icon(
                          onPressed: () async {
                            await _selectDate(dialogContext, false);
                            setDialogState(() {});
                          },
                          icon: const Icon(
                            Icons.date_range,
                            size: 20,
                            color: Colors.black,
                          ),
                          label: Text(
                            'Đến: ${DateFormat('dd/MM/yyyy').format(selectedEndDate)}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black87),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            minimumSize: const Size(double.infinity, 0),
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: Text(
                  'Hủy',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ElevatedButton(
                  onPressed: () {
                    if (selectedStartDate.isAfter(selectedEndDate)) {
                      Get.snackbar(
                        'Lỗi',
                        'Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.',
                        snackPosition: SnackPosition.BOTTOM,
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    _refreshInvoiceList(blocContext);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold),
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.search, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Tìm kiếm', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingCodeNV) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              const SizedBox(height: 16),
              const Text(
                'Đang tải thông tin đăng nhập...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_codeNV == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text(
                'Không tìm thấy thông tin đăng nhập',
                style: TextStyle(fontSize: 18, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Get.offAllNamed(LoginScreen.routeName);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text(
                  'Đăng nhập lại',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return BlocProvider(
      create: (context) => InvoiceTempBloc(InvoiceTempRepository()),
      child: WillPopScope(
        onWillPop: _handleWillPop,
        child: Scaffold(
          appBar: AppBar(
            elevation: 2,
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            title: SizedBox(
              height: 40,
              child: Image.asset('assets/logos/logo.png'),
            ),
            actions: [
              Builder(
                builder: (BuildContext innerContext) {
                  return Tooltip(
                    message: 'Tìm kiếm',
                    child: IconButton(
                      icon: const Icon(Icons.search, size: 24),
                      onPressed: () => _showSearchDialog(innerContext),
                    ),
                  );
                },
              ),
              Tooltip(
                message: 'Đăng xuất',
                child: IconButton(
                  icon: const Icon(Icons.logout, size: 24),
                  onPressed: _handleLogout,
                ),
              ),
            ],
          ),
          body: BlocListener<InvoiceTempBloc, InvoiceTempState>(
            listener: (context, state) async {
              if (state is InvoiceTempError) {
                Get.snackbar(
                  'Lỗi',
                  'Không thể tải dữ liệu: ${state.message}',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.redAccent.withOpacity(0.9),
                  colorText: Colors.white,
                  margin: const EdgeInsets.all(16),
                  borderRadius: 12,
                  duration: const Duration(seconds: 3),
                  animationDuration: const Duration(milliseconds: 400),
                );
              } else if (state is InvoiceTempLoaded) {
                final exportingIdsJson =
                    await _storage.read(key: 'exporting_invoices');
                List<String> exportingIds = [];
                if (exportingIdsJson != null) {
                  try {
                    exportingIds =
                        List<String>.from(jsonDecode(exportingIdsJson));
                    print('Loaded exporting_invoices: $exportingIds');
                  } catch (e) {
                    print('Error decoding exporting_invoices: $e');
                  }
                }
                for (var invoice in state.invoiceTemps) {
                  invoice.isExporting =
                      exportingIds.contains(invoice.idInvoice.toString());
                  print(
                      'Invoice ${invoice.idInvoice}: isExporting=${invoice.isExporting}, isSaved=${invoice.isSaved}');
                }
                if (_selectedOrderType == 'GIA_CONG') {
                  setState(() {
                    for (var invoice in state.invoiceTemps) {
                      final id = invoice.idInvoice;
                      _expandedInvoices[id] = true;
                      _loadDetailsExpanded(
                          invoice);
                    }
                  });
                } else {
                  setState(() {
                    _expandedInvoices.clear();
                  });
                }
                if (state.invoiceTemps.isEmpty) {
                  if (_selectedOrderType == 'GIA_CONG') {
                    Get.snackbar(
                      'Thông báo',
                      'Không có đơn hàng gia công nào trong khoảng thời gian từ ${DateFormat('dd/MM/yyyy').format(selectedStartDate)} đến ${DateFormat('dd/MM/yyyy').format(selectedEndDate)} cho mã nhân viên $_codeNV',
                      snackPosition: SnackPosition.BOTTOM,
                      backgroundColor: Colors.orangeAccent.withOpacity(0.9),
                      colorText: Colors.white,
                      margin: const EdgeInsets.all(16),
                      borderRadius: 12,
                      duration: const Duration(seconds: 3),
                      animationDuration: const Duration(milliseconds: 400),
                    );
                  }
                  Get.snackbar(
                    'Thông báo',
                    'Không có đơn hàng LIX   nào trong khoảng thời gian từ ${DateFormat('dd/MM/yyyy').format(selectedStartDate)} đến ${DateFormat('dd/MM/yyyy').format(selectedEndDate)} cho mã nhân viên $_codeNV',
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.orangeAccent.withOpacity(0.9),
                    colorText: Colors.white,
                    margin: const EdgeInsets.all(16),
                    borderRadius: 12,
                    duration: const Duration(seconds: 3),
                    animationDuration: const Duration(milliseconds: 400),
                  );
                }
              }
            },
            child: BlocBuilder<InvoiceTempBloc, InvoiceTempState>(
              builder: (context, state) {
                return _buildBody(context, state);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, InvoiceTempState state) {
    if (state is InvoiceTempLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kPrimaryColor),
            const SizedBox(height: 16),
            const Text(
              'Đang tải dữ liệu...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (state is InvoiceTempLoaded) {
      final invoiceTemps = state.invoiceTemps;
      if (invoiceTemps.isEmpty) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildOrderTypeFilter(context),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Không có dữ liệu',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _refreshInvoiceList(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      child: const Text(
                        'Tải lại',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      Map<String, InvoiceTempDto> grouped = {};
      for (var invoice in invoiceTemps) {
        String key = '${invoice.idInvoice}-${invoice.customerName ?? ""}';
        if (!grouped.containsKey(key)) {
          grouped[key] = invoice;
        }
      }
      final groupedInvoices = grouped.entries.toList();

      return RefreshIndicator(
        color: kPrimaryColor,
        onRefresh: () async {
          _refreshInvoiceList(context);
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedInvoices.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildOrderTypeFilter(context);
            }
            return _buildInvoiceCard(context, groupedInvoices[index - 1]);
          },
        ),
      );
    }

    if (state is InvoiceTempError) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildOrderTypeFilter(context),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    'Lỗi: ${state.message}',
                    style:
                        const TextStyle(fontSize: 18, color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _refreshInvoiceList(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text(
                      'Thử lại',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildOrderTypeFilter(context),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.touch_app, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Nhấn để tải dữ liệu',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _refreshInvoiceList(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text(
                    'Tải dữ liệu',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceCard(
      BuildContext context, MapEntry<String, InvoiceTempDto> group) {
    final invoice = group.value;
    final isGiaCong = _selectedOrderType == 'GIA_CONG';
    final isExpanded = _expandedInvoices[invoice.idInvoice] ?? true;

    // Màu nền & chữ
    Color? backgroundColor;
    Color? textColor;
    Gradient? gradient;

    if (invoice.isExporting == true) {
      backgroundColor = Colors.orange.shade100;
      textColor = Colors.orange.shade900;
    } else if (invoice.isSaved == true) {
      backgroundColor = Colors.lightGreen.shade400;
      textColor = Colors.white;
    }
    // } else {
    //   gradient = LinearGradient(
    //     colors: [Colors.lightBlue.shade100, Colors.white],
    //     begin: Alignment.topLeft,
    //     end: Alignment.bottomRight,
    //   );
    //   textColor = Colors.black87;
    // }

    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: backgroundColor,
          gradient: gradient,
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () async {
                final result = await Get.toNamed(InvoiceTempScreen.routeName,
                    arguments: invoice);

                if (result != null && result is Map<String, dynamic>) {
                  final String action = result['action'] ?? 'cancel';

                  if (action == 'temp_saved') {
                    setState(() {
                      invoice.isExporting = true;
                      invoice.isSaved = false;
                    });
                  } else if (action == 'completed') {
                    setState(() {
                      invoice.isExporting = false;
                      invoice.isSaved = true;
                    });
                  }
                }
              },
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                leading: CircleAvatar(
                  backgroundColor: kPrimaryColor.withOpacity(0.15),
                  radius: 24,
                  child: const Icon(Icons.receipt_long_rounded,
                      color: kPrimaryColor, size: 28),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đơn hàng: ${invoice.orderVoucher ?? "Chưa có"}',
                      style: TextStyle(
                        fontSize: 12.3,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[700],
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 6),

                    // Biển số xe (nhỏ gọn, dưới đơn hàng)
                    GestureDetector(
                      onTap: () async {
                        final selected = await _showCarSelectionDialog(
                            invoice.license_plate ?? '');
                        if (selected != null &&
                            selected != invoice.license_plate) {
                          final oldPlate = invoice.license_plate;
                          setState(() {
                            invoice.license_plate = selected;
                          });
                          try{
                            final invoiceTempRepository = InvoiceTempRepository();
                            final success = await invoiceTempRepository.updateInvoiceTemp(invoice);
                            if(success){
                              Get.snackbar(
                                'Thành công',
                                'Đã cập nhật biển số xe: $selected cho đơn hàng',
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            }else{
                              throw Exception('Cập nhật thất bại');
                            }
                          }catch(e){
                            Get.snackbar(
                              'Lỗi',
                              'Không thể cập nhật số xe: $e',
                              backgroundColor: Colors.red,
                              colorText: Colors.white,
                              snackPosition: SnackPosition.BOTTOM,
                            );

                            setState(() {
                              invoice.license_plate = oldPlate;
                            });
                          }

                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: textColor?.withOpacity(0.4) ?? Colors.grey,
                              width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_shipping_rounded,
                                size: 16, color: textColor),
                            const SizedBox(width: 6),
                            Text(
                              invoice.license_plate?.isNotEmpty == true
                                  ? (invoice.license_plate!.length > 10
                                      ? '${invoice.license_plate!.substring(0, 10)}...'
                                      : invoice.license_plate!)
                                  : 'Chọn xe',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit,
                                size: 10, color: textColor?.withOpacity(0.8)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khách hàng: ${invoice.customerName ?? "N/A"}',
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              textColor?.withOpacity(0.85) ?? Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (invoice.isExporting == true)
                        Text(
                          'Đang lưu tạm...',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold),
                        )
                      else if (invoice.isSaved == true)
                        Text(
                          'Đã hoàn thành',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                trailing: isGiaCong
                    ? IconButton(
                        icon: Icon(
                          isExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: textColor,
                          size: 28,
                        ),
                        onPressed: () async {
                          final id = invoice.idInvoice;
                          final shouldExpand =
                              !(_expandedInvoices[id] ?? false);

                          setState(() {
                            _expandedInvoices[id] = shouldExpand;
                          });

                          if (shouldExpand) {
                            await _loadDetailsExpanded(invoice);
                          }
                        },
                      )
                    : null, // Không có icon cho LIX
              ),
            ),

            // Chi tiết sản phẩm (chỉ hiện khi mở rộng và là GIA_CONG)
            if (isGiaCong && isExpanded)
              _buildInvoiceDetails(invoice.idInvoice),
          ],
        ),
      ),
    );
  }

  Color _getDetailBackgroundColor(int invoiceId) {
    // Chu kỳ 6 màu nhẹ nhàng, dựa trên id để cố định màu cho mỗi invoice
    final colors = [
      Colors.brown.shade100,
      Colors.green.shade100,
      Colors.purple.shade100,
      Colors.orange.shade100,
      Colors.teal.shade100,
      Colors.amber.shade100,
      Colors.limeAccent,
      Colors.yellow.shade100,
      Colors.pink.shade100
    ];

    // Dùng idInvoice để chọn màu cố định (không random mỗi lần render)
    return colors[invoiceId % colors.length];
  }

  Widget _buildInvoiceDetails(int invoiceId) {
    final details = _invoiceDetailsCache[invoiceId];

    if (details == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (details.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Không có chi tiết sản phẩm', style: TextStyle(color: Colors.grey)),
      );
    }

    final mainProducts = details.where((item) => item.spchinh == true).toList();
    final promoProducts = details.where((item) => item.spchinh == false).toList();

    final bgColor = _getDetailBackgroundColor(invoiceId);

    // Lấy trạng thái show all từ map (mặc định false)
    bool showAllMain = _showAllMainProducts[invoiceId] ?? false;
    bool showAllPromo = _showAllPromoProducts[invoiceId] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bgColor.withOpacity(0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mainProducts.isNotEmpty) ...[
            Text(
              'Sản phẩm chính',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: kPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),

            // Hiển thị 5 sản phẩm đầu hoặc tất cả nếu showAllMain
            ...mainProducts.asMap().entries.where((entry) {
              final index = entry.key;
              return showAllMain || index < 5;
            }).map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  ListTile(
                    dense: true,
                    minLeadingWidth: 24,
                    horizontalTitleGap: 8,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        size: 18,
                        color: kPrimaryColor,
                      ),
                    ),
                    title: Text(
                      '${item.productCode} - ${item.productName ?? ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'SỐ KG: ${item.quantity ?? 0} | SỐ THÙNG: ${item.boxQuantity ?? 0} | QUY CÁCH: ${item.specification ?? ''} | CA SX: ${item.noteBatchCode ?? ''}',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey[700]),
                    ),
                  ),
                  if (index < mainProducts.length - 1 && (showAllMain || index < 4))
                    Divider(
                      color: Colors.grey.shade300,
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              );
            }).toList(),

            // Nút toggle "Xem thêm" / "Thu gọn"
            if (mainProducts.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllMainProducts[invoiceId] = !(_showAllMainProducts[invoiceId] ?? false);
                      });
                    },
                    icon: Icon(
                      _showAllMainProducts[invoiceId] ?? false ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: kPrimaryColor,
                    ),
                    label: Text(
                      _showAllMainProducts[invoiceId] ?? false
                          ? 'Thu gọn'
                          : 'Xem thêm ${mainProducts.length - 5} sản phẩm',
                      style: TextStyle(color: kPrimaryColor, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],

          if (promoProducts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Khuyến mãi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 8),

            // Tương tự cho promo
            ...promoProducts.asMap().entries.where((entry) {
              final index = entry.key;
              return showAllPromo || index < 5;
            }).map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  ListTile(
                    dense: true,
                    minLeadingWidth: 24,
                    horizontalTitleGap: 8,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.card_giftcard_rounded,
                        size: 18,
                        color: Colors.orange,
                      ),
                    ),
                    title: Text(
                      item.productName ?? 'N/A',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'SL: ${item.quantity ?? 0}',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey[700]),
                    ),
                  ),
                  if (index < promoProducts.length - 1 && (showAllPromo || index < 4))
                    Divider(
                      color: Colors.grey.shade300,
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              );
            }).toList(),

            if (promoProducts.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllPromoProducts[invoiceId] = !(_showAllPromoProducts[invoiceId] ?? false);
                      });
                    },
                    icon: Icon(
                      _showAllPromoProducts[invoiceId] ?? false ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: Colors.orange,
                    ),
                    label: Text(
                      _showAllPromoProducts[invoiceId] ?? false
                          ? 'Thu gọn'
                          : 'Xem thêm ${promoProducts.length - 5} khuyến mãi',
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<String?> _showCarSelectionDialog(String currentLicensePlate) async {
    final repo = InvoiceTempRepository();
    String? selectedPlate;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
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
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_rounded,
                          color: kPrimaryColor, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chọn xe',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Số xe hiện tại: ${currentLicensePlate.isEmpty ? "Chưa có" : currentLicensePlate}',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // TypeAheadField
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TypeAheadField<String>(
                    debounceDuration: const Duration(milliseconds: 300),
                    hideOnEmpty: true,
                    hideOnLoading: true,
                    hideOnError: true,
                    hideOnUnfocus: false,
                    hideWithKeyboard: false,

                    // Phần input
                    builder: (context, controller, focusNode) {
                      if (currentLicensePlate.isNotEmpty) {
                        controller.text = currentLicensePlate;
                      }
                      focusNode.requestFocus();

                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Nhập biển số xe (ví dụ: 59A-12345)',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          labelText: 'Biển số xe',
                          // Thêm label nổi khi focus
                          labelStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          floatingLabelStyle: TextStyle(
                            color: kPrimaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            // Bo góc mềm hơn
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: kPrimaryColor,
                              width: 2.0, // Border đậm hơn khi focus
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          prefixIcon: Container(
                            margin: const EdgeInsets.only(left: 12, right: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              // Thêm hiệu ứng nhẹ khi focus
                              boxShadow: focusNode.hasFocus
                                  ? [
                                      BoxShadow(
                                        color: kPrimaryColor.withOpacity(0.3),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              Icons.directions_car_rounded,
                              size: 26, // Icon lớn hơn, nổi bật
                              color: focusNode.hasFocus
                                  ? kPrimaryColor
                                  : Colors.grey.shade600,
                            ),
                          ),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 22,
                                    color: focusNode.hasFocus
                                        ? kPrimaryColor
                                        : Colors.grey.shade500,
                                  ),
                                  onPressed: () {
                                    controller.clear();
                                    // Tùy chọn: focus lại để tiếp tục gõ
                                    focusNode.requestFocus();
                                  },
                                  splashRadius: 20,
                                )
                              : null,
                          filled: true,
                          fillColor: focusNode.hasFocus
                              ? kPrimaryColor.withOpacity(0.03)
                              : Colors.white,
                        ),
                        style: TextStyle(
                          fontSize: 16, // Chữ lớn hơn, dễ đọc
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        cursorColor: kPrimaryColor,
                      );
                    },

                    // Gợi ý
                    suggestionsCallback: (pattern) async {
                      final trimmed = pattern.trim();
                      if (trimmed.isEmpty) return [];

                      try {
                        final cars = await repo.searchCar(trimmed);
                        return cars
                            .map((car) => car.license_plate ?? '')
                            .where((plate) => plate.isNotEmpty)
                            .toSet()
                            .toList();
                      } catch (e) {
                        print('Lỗi tìm xe: $e');
                        return [];
                      }
                    },

                    itemBuilder: (context, String suggestionPlate) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kPrimaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.directions_car_rounded,
                                  size: 18, color: kPrimaryColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    suggestionPlate,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: kPrimaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FutureBuilder<List<CarDTO>>(
                                    future: repo.searchCar(suggestionPlate),
                                    builder: (context, snapshot) {
                                      final car = snapshot.data?.firstWhere(
                                            (c) =>
                                                (c.license_plate ?? '') ==
                                                suggestionPlate,
                                            orElse: () =>
                                                CarDTO(id: 0, disable: true),
                                          ) ??
                                          CarDTO(id: 0, disable: true);

                                      return Text(
                                        car.driver ?? 'Chưa có tài xế',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },

                    onSelected: (String selected) {
                      selectedPlate = selected;
                      Navigator.pop(context);
                    },

                    // Empty & Loading builder (tên mới)
                    emptyBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Không tìm thấy xe nào',
                          style: TextStyle(color: Colors.grey)),
                    ),

                    loadingBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
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
                            const Text('Hủy', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return selectedPlate;
  }

  DateTime? currentBackPressTime;

  Widget _buildOrderTypeFilter(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          _buildFilterOption(
            context,
            label: 'Đơn hàng LIX',
            value: 'LIX',
            imageAsset: 'assets/logos/lix.png',
          ),
          _buildFilterOption(
            context,
            label: 'Đơn hàng GC',
            value: 'GIA_CONG',
            icon: Icons.precision_manufacturing_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
    String? imageAsset,
  }) {
    final isSelected = _selectedOrderType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_selectedOrderType != value) {
            setState(() => _selectedOrderType = value);
            _refreshInvoiceList(context);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (imageAsset != null)
                Image.asset(
                  imageAsset,
                  height: 20,
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
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
}
