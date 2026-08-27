import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get/get.dart';
import 'package:invoice_management/screens/invoice_screen/model/invoice_detail_temp_dto.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_temp_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../constants/contains.dart';
import '../../auth_screen/repository/auth_repostory.dart';
import '../../invoice_screen/barcode_screens/barcode_screen.dart';
import '../../invoice_screen/core/invoice_temp_bloc.dart';
import '../../invoice_screen/pending_sync_screen.dart';
import '../../invoice_screen/model/car_dto.dart';
import '../../invoice_screen/model/invoice_temp_dto.dart';
import '../../invoice_screen/repository/invoice_detail_temp_repository.dart';
import '../../invoice_screen/screens/invoice_screen.dart';
import '../../screens.dart';
import 'package:intl/intl.dart';

enum _InvoiceUiStatus { pendingSync, temp, fresh, done }

enum _InvoiceStatusFilter { all, pendingSync, temp, fresh, done }

class _InvoiceStatusStats {
  int all = 0;
  int pendingSync = 0;
  int temp = 0;
  int fresh = 0;
  int done = 0;

  void add(_InvoiceUiStatus status) {
    all++;
    switch (status) {
      case _InvoiceUiStatus.pendingSync:
        pendingSync++;
        break;
      case _InvoiceUiStatus.temp:
        temp++;
        break;
      case _InvoiceUiStatus.fresh:
        fresh++;
        break;
      case _InvoiceUiStatus.done:
        done++;
        break;
    }
  }

  int countFor(_InvoiceStatusFilter filter) {
    switch (filter) {
      case _InvoiceStatusFilter.all:
        return all;
      case _InvoiceStatusFilter.pendingSync:
        return pendingSync;
      case _InvoiceStatusFilter.temp:
        return temp;
      case _InvoiceStatusFilter.fresh:
        return fresh;
      case _InvoiceStatusFilter.done:
        return done;
    }
  }
}

class _ScoredInvoiceEntry {
  const _ScoredInvoiceEntry({
    required this.entry,
    required this.priorityScore,
  });

  final MapEntry<String, InvoiceTempDto> entry;
  final int priorityScore;
}

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
  String _smartSearchQuery = '';
  _InvoiceStatusFilter _selectedStatusFilter = _InvoiceStatusFilter.all;
  DateTime? _lastUpdatedAt;
  Timer? _smartSearchDebounce;
  Completer<void>? _refreshCompleter;
  final TextEditingController _smartSearchCtrl = TextEditingController();
  final Map<int, bool> _expandedInvoices = {};
  final Map<int, List<InvoiceDetailTempDto>> _invoiceDetailsCache = {};
  final Map<int, bool> _showAllMainProducts = {};
  final Map<int, bool> _showAllPromoProducts = {};
  final Set<int> _pendingSyncInvoices = {};

  Future<List<String>> _loadExportingInvoiceIds() async {
    final exportingIdsJson = await _storage.read(key: 'exporting_invoices');
    if (exportingIdsJson == null || exportingIdsJson.isEmpty) return [];

    try {
      return List<String>.from(jsonDecode(exportingIdsJson));
    } catch (e) {
      print('Error decoding exporting_invoices: $e');
      return [];
    }
  }

  Future<void> _setPersistedTempState(int idInvoice, bool isTempSaved) async {
    final ids = (await _loadExportingInvoiceIds()).toSet();
    final id = idInvoice.toString();

    if (isTempSaved) {
      ids.add(id);
    } else {
      ids.remove(id);
      await _storage.delete(key: 'invoice_temp_$idInvoice');
    }

    await _storage.write(
      key: 'exporting_invoices',
      value: jsonEncode(ids.toList()),
    );
  }

  Future<void> _applyPersistedTempStates(List<InvoiceTempDto> invoices) async {
    final storageValues = await _storage.readAll();
    final exportingIdsJson = storageValues['exporting_invoices'];
    final exportingIds = <String>{};
    if (exportingIdsJson != null && exportingIdsJson.isNotEmpty) {
      try {
        exportingIds.addAll(List<String>.from(jsonDecode(exportingIdsJson)));
      } catch (e) {
        print('Error decoding exporting_invoices: $e');
      }
    }
    final pendingIdsJson = storageValues['pending_completed_invoices'];
    _pendingSyncInvoices.clear();
    if (pendingIdsJson != null && pendingIdsJson.isNotEmpty) {
      try {
        _pendingSyncInvoices.addAll(
          List<String>.from(jsonDecode(pendingIdsJson)).map(int.parse),
        );
      } catch (_) {}
    }

    for (final invoice in invoices) {
      final id = invoice.idInvoice.toString();
      final tempJson = storageValues['invoice_temp_${invoice.idInvoice}'];
      invoice.isExporting = exportingIds.contains(id) ||
          (tempJson != null && tempJson.isNotEmpty) ||
          _pendingSyncInvoices.contains(invoice.idInvoice);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCodeNV();
  }

  @override
  void dispose() {
    _smartSearchDebounce?.cancel();
    _smartSearchCtrl.dispose();
    super.dispose();
  }

  void _onSmartSearchChanged(String value) {
    _smartSearchDebounce?.cancel();
    _smartSearchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (value == _smartSearchQuery) return;
      setState(() => _smartSearchQuery = value);
    });
  }

  void _commitSmartSearch(String value) {
    _smartSearchDebounce?.cancel();
    if (value == _smartSearchQuery) return;
    setState(() => _smartSearchQuery = value);
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
      Get.offAllNamed(LoginScreen.routeName);
    }
  }

  Future<void> _refreshInvoiceList(BuildContext context) {
    if (_codeNV == null) {
      Get.snackbar(
        'Lỗi',
        'Chưa có mã nhân viên, vui lòng đăng nhập lại',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return Future.value();
    }
    if (_refreshCompleter?.isCompleted == false) {
      _refreshCompleter?.complete();
    }
    final completer = Completer<void>();
    _refreshCompleter = completer;
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
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  void _completeRefresh() {
    if (_refreshCompleter?.isCompleted == false) {
      _refreshCompleter?.complete();
    }
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
    if (_invoiceDetailsCache.containsKey(id)) return;

    try {
      final repo = InvoiceDetailTempRepository();
      final details = await repo.searchInvoiceDetail(
        cm: 'list_invoice_detail_temps',
        idInvoice: id,
      );

      if (!mounted) return;
      setState(() {
        _invoiceDetailsCache[id] = details;
      });
    } catch (e) {
      Get.snackbar('Lỗi', 'Không tải được chi tiết đơn hàng gia công: $e',
          backgroundColor: Colors.red);
    }
  }

  String _normalizeSmartText(String value) {
    const from =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var result = value.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _invoiceSearchText(InvoiceTempDto invoice) {
    final status = _statusOf(invoice);
    return _normalizeSmartText([
      invoice.idInvoice,
      invoice.customerCode,
      invoice.customerName,
      invoice.orderCode,
      invoice.orderVoucher,
      invoice.poNo,
      invoice.lookupCode,
      invoice.voucher_code,
      invoice.license_plate,
      invoice.note,
      invoice.content,
      _statusSearchTokens(status),
      DateFormat('dd/MM/yyyy').format(invoice.invoiceDate),
      DateFormat('dd/MM/yyyy').format(invoice.delivery_date),
    ].where((e) => e != null).join(' '));
  }

  bool _matchesSmartSearch(InvoiceTempDto invoice, String query) {
    if (query.isEmpty) return true;
    final searchable = _invoiceSearchText(invoice);
    final tokens = query.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    return tokens.every(searchable.contains);
  }

  _InvoiceUiStatus _statusOf(InvoiceTempDto invoice) {
    if (_pendingSyncInvoices.contains(invoice.idInvoice)) {
      return _InvoiceUiStatus.pendingSync;
    }
    if (invoice.isExporting == true) return _InvoiceUiStatus.temp;
    if (invoice.isSaved == true) return _InvoiceUiStatus.done;
    return _InvoiceUiStatus.fresh;
  }

  String _statusLabel(_InvoiceUiStatus status) {
    switch (status) {
      case _InvoiceUiStatus.pendingSync:
        return 'Chờ đồng bộ';
      case _InvoiceUiStatus.temp:
        return 'Lưu tạm';
      case _InvoiceUiStatus.fresh:
        return 'Chờ xử lý';
      case _InvoiceUiStatus.done:
        return 'Hoàn thành';
    }
  }

  Color _statusColor(_InvoiceUiStatus status) {
    switch (status) {
      case _InvoiceUiStatus.pendingSync:
        return Colors.deepOrange;
      case _InvoiceUiStatus.temp:
        return Colors.orange;
      case _InvoiceUiStatus.fresh:
        return Colors.blueGrey;
      case _InvoiceUiStatus.done:
        return Colors.green;
    }
  }

  String _statusSearchTokens(_InvoiceUiStatus status) {
    switch (status) {
      case _InvoiceUiStatus.pendingSync:
        return 'cho dong bo pending sync uu tien';
      case _InvoiceUiStatus.temp:
        return 'luu tam dang xuat uu tien';
      case _InvoiceUiStatus.fresh:
        return 'moi chua xu ly cho xu ly uu tien';
      case _InvoiceUiStatus.done:
        return 'hoan thanh da xu ly';
    }
  }

  bool _statusMatchesFilter(
      _InvoiceUiStatus status, _InvoiceStatusFilter filter) {
    switch (filter) {
      case _InvoiceStatusFilter.all:
        return true;
      case _InvoiceStatusFilter.pendingSync:
        return status == _InvoiceUiStatus.pendingSync;
      case _InvoiceStatusFilter.temp:
        return status == _InvoiceUiStatus.temp;
      case _InvoiceStatusFilter.fresh:
        return status == _InvoiceUiStatus.fresh;
      case _InvoiceStatusFilter.done:
        return status == _InvoiceUiStatus.done;
    }
  }

  bool _matchesStatusFilter(InvoiceTempDto invoice) {
    return _statusMatchesFilter(_statusOf(invoice), _selectedStatusFilter);
  }

  int _invoicePriorityScore(InvoiceTempDto invoice, {DateTime? today}) {
    var score = 0;
    final now = DateTime.now();
    final dueDate = DateTime(invoice.delivery_date.year,
        invoice.delivery_date.month, invoice.delivery_date.day);
    final effectiveToday = today ?? DateTime(now.year, now.month, now.day);
    final daysToDue = dueDate.difference(effectiveToday).inDays;

    if (invoice.isExporting == true) score += 1000;
    if (invoice.isSaved != true) score += 600;
    if (daysToDue < 0) {
      score += 500 + (daysToDue.abs() * 10).clamp(0, 200);
    } else if (daysToDue == 0) {
      score += 420;
    } else if (daysToDue <= 2) {
      score += 260 - (daysToDue * 40);
    }
    if (invoice.note?.trim().isNotEmpty == true) score += 40;
    if (invoice.license_plate?.trim().isEmpty != false) score += 25;
    return score;
  }

  String _invoicePriorityLabel(InvoiceTempDto invoice) {
    return _statusLabel(_statusOf(invoice));
  }

  List<MapEntry<String, InvoiceTempDto>> _filterAndPrioritizeInvoices(
      List<MapEntry<String, InvoiceTempDto>> invoices) {
    final query = _normalizeSmartText(_smartSearchQuery);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final filtered = invoices.where((entry) {
      final invoice = entry.value;
      return _matchesStatusFilter(invoice) &&
          _matchesSmartSearch(invoice, query);
    }).map((entry) {
      return _ScoredInvoiceEntry(
        entry: entry,
        priorityScore: _invoicePriorityScore(entry.value, today: today),
      );
    }).toList();

    filtered.sort((a, b) {
      final scoreCompare = b.priorityScore.compareTo(a.priorityScore);
      if (scoreCompare != 0) return scoreCompare;
      return a.entry.value.delivery_date.compareTo(b.entry.value.delivery_date);
    });
    return filtered.map((item) => item.entry).toList();
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
          backgroundColor: const Color(0xFFF3F6FB),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            centerTitle: true,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kPrimaryColor,
                    kPrimaryColor.withOpacity(0.78),
                    const Color(0xFF0F766E),
                  ],
                ),
              ),
            ),
            title: Column(
              children: [
                SizedBox(
                  height: 34,
                  child: Image.asset('assets/logos/logo.png'),
                ),
                const SizedBox(height: 2),
              ],
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
              _buildPendingSyncAction(context),
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
                _completeRefresh();
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
                await _applyPersistedTempStates(state.invoiceTemps);
                if (!mounted) return;
                _completeRefresh();
                setState(() {
                  _lastUpdatedAt = DateTime.now();
                  if (_selectedOrderType == 'GIA_CONG') {
                    for (var invoice in state.invoiceTemps) {
                      final id = invoice.idInvoice;
                      _expandedInvoices.putIfAbsent(id, () => false);
                    }
                  } else {
                    _expandedInvoices.clear();
                  }
                });
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
                    'Không có đơn hàng LIX nào trong khoảng thời gian từ ${DateFormat('dd/MM/yyyy').format(selectedStartDate)} đến ${DateFormat('dd/MM/yyyy').format(selectedEndDate)} cho mã nhân viên $_codeNV',
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
          bottomNavigationBar: _buildBottomScanBar(),
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
      final statusStats = _buildStatusStats(groupedInvoices);
      final visibleInvoices = _filterAndPrioritizeInvoices(groupedInvoices);

      return RefreshIndicator(
        color: kPrimaryColor,
        onRefresh: () async {
          await _refreshInvoiceList(context);
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: visibleInvoices.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderTypeFilter(context),
                  _buildSmartSearchBox(),
                  _buildStatusQuickFilters(statusStats),
                  const SizedBox(height: 10),
                  _buildPrioritySummaryHeader(
                      groupedInvoices, visibleInvoices.length, statusStats),
                  const SizedBox(height: 8),
                  if (visibleInvoices.isEmpty) _buildEmptySearchResult(context),
                ],
              );
            }
            return _buildInvoiceCard(context, visibleInvoices[index - 1]);
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

  Widget _buildPendingSyncAction(BuildContext context) {
    final count = _pendingSyncInvoices.length;
    return Tooltip(
      message: count > 0 ? '$count đơn chờ đồng bộ' : 'Đơn chờ đồng bộ',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: const Icon(Icons.cloud_sync_rounded, size: 24),
            onPressed: () async {
              await Get.toNamed(PendingSyncScreen.routeName);
              _refreshInvoiceList(context);
            },
          ),
          if (count > 0)
            Positioned(
              right: 6,
              top: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepOrange,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomScanBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Get.toNamed(BarcodeScanScreen.routeName),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kPrimaryColor,
                  kPrimaryColor.withOpacity(0.82),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner_rounded,
                    size: 24, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Quét mã barcode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartSearchBox() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimaryColor.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: TextField(
        controller: _smartSearchCtrl,
        textInputAction: TextInputAction.search,
        onChanged: _onSmartSearchChanged,
        onSubmitted: _commitSmartSearch,
        decoration: InputDecoration(
          border: InputBorder.none,
          icon: const Icon(Icons.manage_search_rounded, color: kPrimaryColor),
          hintText: 'Tìm kiếm: khách, mã đơn, biển số, ghi chú...',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          suffixIcon: _smartSearchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _smartSearchDebounce?.cancel();
                    _smartSearchCtrl.clear();
                    setState(() => _smartSearchQuery = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildStatusQuickFilters(_InvoiceStatusStats stats) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(top: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildStatusFilterChip(
              _InvoiceStatusFilter.all, 'Tất cả', stats, kPrimaryColor),
          _buildStatusFilterChip(_InvoiceStatusFilter.pendingSync, 'Chờ sync',
              stats, Colors.deepOrange),
          _buildStatusFilterChip(
              _InvoiceStatusFilter.temp, 'Lưu tạm', stats, Colors.orange),
          _buildStatusFilterChip(
              _InvoiceStatusFilter.fresh, 'Chờ xử lý', stats, Colors.blueGrey),
          _buildStatusFilterChip(
              _InvoiceStatusFilter.done, 'Hoàn thành', stats, Colors.green),
        ],
      ),
    );
  }

  _InvoiceStatusStats _buildStatusStats(
      List<MapEntry<String, InvoiceTempDto>> invoices) {
    final stats = _InvoiceStatusStats();
    for (final entry in invoices) {
      stats.add(_statusOf(entry.value));
    }
    return stats;
  }

  Widget _buildStatusFilterChip(_InvoiceStatusFilter value, String label,
      _InvoiceStatusStats stats, Color color) {
    final selected = _selectedStatusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text('$label (${stats.countFor(value)})'),
        selectedColor: color.withOpacity(0.16),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? color.withOpacity(0.55) : Colors.grey.shade200,
        ),
        labelStyle: TextStyle(
          color: selected ? color : Colors.grey.shade700,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
        onSelected: (_) => setState(() => _selectedStatusFilter = value),
      ),
    );
  }

  Widget _buildPrioritySummaryHeader(
      List<MapEntry<String, InvoiceTempDto>> invoices,
      int visibleCount,
      _InvoiceStatusStats stats) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            kPrimaryColor.withOpacity(0.06),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child:
                    const Icon(Icons.inventory_outlined, color: kPrimaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _smartSearchQuery.trim().isEmpty
                          ? '${invoices.length} đơn trong danh sách'
                          : '$visibleCount/${invoices.length} đơn phù hợp',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937)),
                    ),
                    // const SizedBox(height: 2),
                    // Text(
                    //   'Ưu tiên: đang xử lý, chưa xử lý',
                    //   style: TextStyle(
                    //       fontSize: 12,
                    //       fontWeight: FontWeight.w500,
                    //       color: Colors.grey.shade600),
                    // ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  tooltip: 'Làm mới',
                  onPressed: () => _refreshInvoiceList(context),
                  icon: const Icon(Icons.refresh_rounded, color: kPrimaryColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildPriorityMetric(
                      'Chờ sync', '${stats.pendingSync}', Colors.deepOrange)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildPriorityMetric(
                      'Lưu tạm', '${stats.temp}', Colors.orange)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildPriorityMetric(
                      'Chờ xử lý', '${stats.fresh}', kPrimaryColor)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildPriorityMetric(
                      'Hoàn thành', '${stats.done}', Colors.green)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildSummaryMeta(
                Icons.date_range_rounded,
                '${DateFormat('dd/MM/yyyy').format(selectedStartDate)} - ${DateFormat('dd/MM/yyyy').format(selectedEndDate)}',
              ),
              _buildSummaryMeta(
                Icons.update_rounded,
                _lastUpdatedAt == null
                    ? 'Chưa cập nhật'
                    : 'Cập nhật ${DateFormat('HH:mm dd/MM').format(_lastUpdatedAt!)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMeta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildEmptySearchResult(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: Colors.grey.shade400, size: 42),
          const SizedBox(height: 10),
          Text('Không tìm thấy hóa đơn phù hợp',
              style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _smartSearchDebounce?.cancel();
              _smartSearchCtrl.clear();
              setState(() => _smartSearchQuery = '');
            },
            child: const Text('Xóa tìm kiếm'),
          ),
        ],
      ),
    );
  }

  Future<void> _openInvoiceTemp(InvoiceTempDto invoice) async {
    final result =
        await Get.toNamed(InvoiceTempScreen.routeName, arguments: invoice);

    if (result != null && result is Map<String, dynamic>) {
      final String action = result['action'] ?? 'cancel';

      if (action == 'temp_saved') {
        await _setPersistedTempState(invoice.idInvoice, true);
        if (!mounted) return;
        setState(() {
          invoice.isExporting = true;
          invoice.isSaved = false;
        });
      } else if (action == 'completed') {
        await _setPersistedTempState(invoice.idInvoice, false);
        if (!mounted) return;
        setState(() {
          _pendingSyncInvoices.remove(invoice.idInvoice);
          invoice.isExporting = false;
          invoice.isSaved = true;
        });
      } else if (action == 'pending_sync') {
        await _setPersistedTempState(invoice.idInvoice, true);
        if (!mounted) return;
        setState(() {
          _pendingSyncInvoices.add(invoice.idInvoice);
          invoice.isExporting = true;
          invoice.isSaved = false;
        });
      }
    }
  }

  Widget _buildInvoiceCard(
      BuildContext context, MapEntry<String, InvoiceTempDto> group) {
    final invoice = group.value;
    final isGiaCong = _selectedOrderType == 'GIA_CONG';
    final isExpanded = _expandedInvoices[invoice.idInvoice] ?? true;
    final status = _statusOf(invoice);
    final priorityScore = _invoicePriorityScore(invoice);
    final accentColor =
        status == _InvoiceUiStatus.fresh ? kPrimaryColor : _statusColor(status);
    final backgroundColor = status == _InvoiceUiStatus.temp
        ? Colors.orange.shade50
        : status == _InvoiceUiStatus.done
            ? Colors.green.shade50
            : status == _InvoiceUiStatus.pendingSync
                ? Colors.deepOrange.shade50
                : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withOpacity(0.16), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: accentColor
                .withOpacity(status == _InvoiceUiStatus.fresh ? 0.07 : 0.13),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor,
                  accentColor.withOpacity(0.35),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _openInvoiceTemp(invoice),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.receipt_long_rounded,
                            color: accentColor, size: 25),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.orderVoucher ?? 'Chưa có mã đơn',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey.shade900,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              invoice.customerName ?? 'Chưa có khách hàng',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildInvoiceStatusChip(invoice),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInvoiceInfoChip(
                        icon: Icons.pending_actions,
                        label: _invoicePriorityLabel(invoice),
                        color: priorityScore >= 900
                            ? Colors.orange
                            : priorityScore >= 600
                                ? kPrimaryColor
                                : Colors.blueGrey,
                      ),
                      _buildInvoiceInfoChip(
                        icon: Icons.calendar_month_rounded,
                        label: DateFormat('dd/MM/yyyy')
                            .format(invoice.invoiceDate),
                        color: Colors.blueGrey,
                      ),
                      _buildLicensePlateChip(invoice, accentColor),
                      if (invoice.note?.isNotEmpty == true)
                        _buildInvoiceInfoChip(
                          icon: Icons.sticky_note_2_rounded,
                          label: invoice.note!,
                          color: Colors.purple,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInvoiceQuickAction(context, invoice, accentColor),
                ],
              ),
            ),
          ),
          if (isGiaCong)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final id = invoice.idInvoice;
                  final shouldExpand = !(_expandedInvoices[id] ?? false);

                  setState(() {
                    _expandedInvoices[id] = shouldExpand;
                  });

                  if (shouldExpand) {
                    await _loadDetailsExpanded(invoice);
                  }
                },
                icon: Icon(
                  isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: accentColor,
                ),
                label: Text(
                  isExpanded ? 'Thu gọn chi tiết' : 'Xem chi tiết',
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (isGiaCong && isExpanded) _buildInvoiceDetails(invoice.idInvoice),
        ],
      ),
    );
  }

  Widget _buildInvoiceQuickAction(
      BuildContext context, InvoiceTempDto invoice, Color color) {
    final status = _statusOf(invoice);
    final label = status == _InvoiceUiStatus.pendingSync
        ? 'Mở đồng bộ'
        : status == _InvoiceUiStatus.done
            ? 'Xem chi tiết'
            : 'Xử lý ngay';
    final icon = status == _InvoiceUiStatus.pendingSync
        ? Icons.cloud_upload_rounded
        : status == _InvoiceUiStatus.done
            ? Icons.visibility_rounded
            : Icons.play_arrow_rounded;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            if (status == _InvoiceUiStatus.pendingSync) {
              await Get.toNamed(PendingSyncScreen.routeName);
              _refreshInvoiceList(context);
              return;
            }
            await _openInvoiceTemp(invoice);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceStatusChip(InvoiceTempDto invoice) {
    final status = _statusOf(invoice);
    final color = _statusColor(status);
    final label = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLicensePlateChip(InvoiceTempDto invoice, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        final selected =
            await _showCarSelectionDialog(invoice.license_plate ?? '');
        if (selected != null && selected != invoice.license_plate) {
          final oldPlate = invoice.license_plate;
          setState(() {
            invoice.license_plate = selected;
          });
          try {
            final invoiceTempRepository = InvoiceTempRepository();
            final success =
                await invoiceTempRepository.updateInvoiceTemp(invoice);
            if (success) {
              Get.snackbar(
                'Thành công',
                'Đã cập nhật biển số xe: $selected cho đơn hàng',
                backgroundColor: Colors.green,
                colorText: Colors.white,
                snackPosition: SnackPosition.BOTTOM,
              );
            } else {
              throw Exception('Cập nhật thất bại');
            }
          } catch (e) {
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
      child: _buildInvoiceInfoChip(
        icon: Icons.local_shipping_rounded,
        label: invoice.license_plate?.isNotEmpty == true
            ? invoice.license_plate!
            : 'Chọn xe',
        color: color,
        trailingIcon: Icons.edit_rounded,
      ),
    );
  }

  Widget _buildInvoiceInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    IconData? trailingIcon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 5),
            Icon(trailingIcon, size: 13, color: color.withOpacity(0.8)),
          ],
        ],
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
        child: Text('Không có chi tiết sản phẩm',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final mainProducts = details.where((item) => item.spchinh == true).toList();
    final promoProducts =
        details.where((item) => item.spchinh == false).toList();

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
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'SỐ KG: ${item.quantity ?? 0} | SỐ THÙNG: ${item.boxQuantity ?? 0} | QUY CÁCH: ${item.specification ?? ''} | MÃ LH: ${item.noteBatchCode ?? ''}',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey[700]),
                    ),
                  ),
                  if (index < mainProducts.length - 1 &&
                      (showAllMain || index < 4))
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

            if (mainProducts.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllMainProducts[invoiceId] =
                            !(_showAllMainProducts[invoiceId] ?? false);
                      });
                    },
                    icon: Icon(
                      _showAllMainProducts[invoiceId] ?? false
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: kPrimaryColor,
                    ),
                    label: Text(
                      _showAllMainProducts[invoiceId] ?? false
                          ? 'Thu gọn'
                          : 'Xem thêm ${mainProducts.length - 5} sản phẩm',
                      style: TextStyle(
                          color: kPrimaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
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
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'SL: ${item.quantity ?? 0}',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey[700]),
                    ),
                  ),
                  if (index < promoProducts.length - 1 &&
                      (showAllPromo || index < 4))
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
                        _showAllPromoProducts[invoiceId] =
                            !(_showAllPromoProducts[invoiceId] ?? false);
                      });
                    },
                    icon: Icon(
                      _showAllPromoProducts[invoiceId] ?? false
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: Colors.orange,
                    ),
                    label: Text(
                      _showAllPromoProducts[invoiceId] ?? false
                          ? 'Thu gọn'
                          : 'Xem thêm ${promoProducts.length - 5} khuyến mãi',
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      kPrimaryColor,
                      kPrimaryColor.withOpacity(0.78),
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
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
