import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_temp_repository.dart';
import 'package:invoice_management/constants/colors.dart';
import 'package:invoice_management/screens/auth_screen/core/auth_bloc.dart';
import '../../../utils/secure_storage.dart';
import '../../auth_screen/model/auth_response.dart';
import '../../../constants/contains.dart';
import '../../invoice_screen/core/invoice_temp_bloc.dart';
import '../../invoice_screen/model/invoice_temp_dto.dart';
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

  DateTime selectedStartDate = DateTime.now().subtract(Duration(days: 15)).copyWith(
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
  @override
  void initState() {
    super.initState();
  }

  DateTime? currentBackPressTime;

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
      progressIndicatorValueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
      mainButton: TextButton(
        onPressed: () {
          logoutStatus = 'CANCEL';
          Get.back();
        },
        child: const Text("Huỷ", style: TextStyle(color: Colors.white)),
      ),
      showProgressIndicator: true,
      progressIndicatorBackgroundColor: Colors.white,
      snackbarStatus: (status) {
        if (status == SnackbarStatus.CLOSED && logoutStatus != 'CANCEL') {
          BlocProvider.of<AuthBloc>(context).add(LogOutEvent());
          Get.offAllNamed(AuthScreen.routeName);
        }
      },
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    DateTime initialDate = isStartDate ? selectedStartDate : selectedEndDate;

    final DateTime? picked = await showDatePicker(
      context: context, // Use the dialog's context
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          selectedStartDate = picked;
        } else {
          selectedEndDate = picked;
        }
      });
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
                const Icon(Icons.search, color: Colors.blueAccent, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Tìm kiếm phiếu tạm',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color:  Colors.blueAccent,
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
                  color:  Colors.blueAccent,
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
                    // Sử dụng blocContext để truy cập InvoiceTempBloc
                    blocContext.read<InvoiceTempBloc>().add(FetchInvoiceTempsEvent(
                      cm: 'list_invoice_temps',
                      sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
                      eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
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
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }




  @override
  Widget build(BuildContext context) {
  return BlocProvider(
  create: (context) => InvoiceTempBloc(InvoiceTempRepository())
  ..add(FetchInvoiceTempsEvent(
  cm: 'list_invoice_temps',
  sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
  eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
  )),
  child: WillPopScope(
  onWillPop: _handleWillPop,
  child: Scaffold(
  appBar: AppBar(
  elevation: 2,
  backgroundColor: Colors.blueAccent,
  foregroundColor: Colors.white,
  title: const Text(
  'Danh sách phiếu',
  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
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
  listener: (context, state) {
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
  } else if (state is InvoiceTempLoaded && state.invoiceTemps.isEmpty) {
  Get.snackbar(
  'Thông báo',
  'Không có phiếu nào trong khoảng thời gian từ ${DateFormat('dd/MM/yyyy').format(selectedStartDate)} đến ${DateFormat('dd/MM/yyyy').format(selectedEndDate)}',
  snackPosition: SnackPosition.BOTTOM,
  backgroundColor: Colors.orangeAccent.withOpacity(0.9),
  colorText: Colors.white,
  margin: const EdgeInsets.all(16),
  borderRadius: 12,
  duration: const Duration(seconds: 3),
  animationDuration: const Duration(milliseconds: 400),
  );
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
  return const Center(
  child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
  CircularProgressIndicator(color: Colors.blueAccent),
  SizedBox(height: 16),
  Text(
  'Đang tải dữ liệu...',
  style: TextStyle(fontSize: 10, color: Colors.grey),
  ),
  ],
  ),
  );
  }

  if (state is InvoiceTempLoaded) {
    final invoiceTemps = state.invoiceTemps;
    if (invoiceTemps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Không có dữ liệu',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                context.read<InvoiceTempBloc>().add(FetchInvoiceTempsEvent(
                  cm: 'list_invoice_temps',
                  sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
                  eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Tải lại',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    // Nhóm dữ liệu theo invoiceId và customerName, nhưng chỉ lấy một InvoiceTempDto duy nhất cho mỗi key
    Map<String, InvoiceTempDto> grouped = {};
    for (var invoice in invoiceTemps) {
      // Tạo key từ invoiceId và customerName, ví dụ: "30-ABC", "31-XYZ"
      String key = '${invoice.idInvoice}-${invoice.customerName ?? "N/A"}';
      // Chỉ lưu InvoiceTempDto đầu tiên cho mỗi key, tránh lặp
      if (!grouped.containsKey(key)) {
        grouped[key] = invoice;
      }
    }
    final groupedInvoices = grouped.entries.toList();

    return RefreshIndicator(
      color: Colors.blueAccent,
      onRefresh: () async {
        context.read<InvoiceTempBloc>().add(FetchInvoiceTempsEvent(
          cm: 'list_invoice_temps',
          sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
          eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
        ));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedInvoices.length,
        itemBuilder: (context, index) {
          return _buildInvoiceCard(context, groupedInvoices[index]);
        },
      ),
    );
  }

  if (state is InvoiceTempError) {
  return Center(
  child: Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
  const SizedBox(height: 16),
  Text(
  'Lỗi: ${state.message}',
  style: const TextStyle(fontSize: 18, color: Colors.redAccent),
  textAlign: TextAlign.center,
  ),
  const SizedBox(height: 16),
  ElevatedButton(
  onPressed: () {
  context.read<InvoiceTempBloc>().add(FetchInvoiceTempsEvent(
  cm: 'list_invoice_temps',
  sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
  eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
  ));
  },
  style: ElevatedButton.styleFrom(
  backgroundColor: Colors.blueAccent,
  shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
  child: const Text(
  'Thử lại',
  style: TextStyle(fontSize: 10, color: Colors.white),
  ),
  ),
  ],
  ),
  );
  }

  return Center(
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
  context.read<InvoiceTempBloc>().add(FetchInvoiceTempsEvent(
  cm: 'list_invoice_temps',
  sDate: DateFormat('dd/MM/yyyy').format(selectedStartDate),
  eDate: DateFormat('dd/MM/yyyy').format(selectedEndDate),
  ));
  },
  style: ElevatedButton.styleFrom(
  backgroundColor: Colors.blueAccent,
  shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(12),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
  child: const Text(
  'Tải dữ liệu',
  style: TextStyle(fontSize: 10, color: Colors.white),
  ),
  ),
  ],
  ),
  );
  }

  Widget _buildInvoiceCard(BuildContext context, MapEntry<String, InvoiceTempDto> group) {
    var invoice = group.value; // Lấy InvoiceTempDto trực tiếp
    return GestureDetector(
      onTap: () {
        Get.to(() => InvoiceTempScreen(), arguments: invoice);
      },
      child: Card(
        elevation: 6,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: invoice.isSaved ? Colors.green.shade300 : null,
            gradient: invoice.isSaved
                ? null
                : LinearGradient(
              colors: [Colors.blueAccent.shade100, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent.withOpacity(0.1),
              child: const Icon(Icons.receipt, color: Colors.white),
            ),
            title: Text(
              'Đơn hàng: ${invoice.orderVoucher}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: invoice.isSaved ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'Khách hàng: ${invoice.customerName ?? "N/A"}',
              style: TextStyle(
                fontSize: 8,
                color: invoice.isSaved ? Colors.white70 : Colors.grey[800],
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: invoice.isSaved ? Colors.white : Colors.grey[800],
            ),
          ),
        ),
      ),
    );
  }
  }
