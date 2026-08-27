import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../constants/contains.dart';
import 'model/invoice_detail_temp_dto.dart';
import 'repository/invoice_detail_temp_repository.dart';

class PendingSyncScreen extends StatefulWidget {
  static const String routeName = '/pending-sync';

  const PendingSyncScreen({super.key});

  @override
  State<PendingSyncScreen> createState() => _PendingSyncScreenState();
}

class _PendingSyncItem {
  final int idInvoice;
  final String reason;
  final DateTime savedAt;
  final List<InvoiceDetailTempDto> items;

  const _PendingSyncItem({
    required this.idInvoice,
    required this.reason,
    required this.savedAt,
    required this.items,
  });
}

class _PendingSyncScreenState extends State<PendingSyncScreen> {
  final _storage = const FlutterSecureStorage();
  final _repository = InvoiceDetailTempRepository();
  final Set<int> _syncing = {};
  bool _loading = true;
  List<_PendingSyncItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadPendingItems();
  }

  Future<void> _loadPendingItems() async {
    setState(() => _loading = true);
    final idsJson = await _storage.read(key: 'pending_completed_invoices');
    final ids = <String>[];
    if (idsJson != null && idsJson.isNotEmpty) {
      try {
        ids.addAll(List<String>.from(jsonDecode(idsJson)));
      } catch (_) {}
    }

    final loaded = <_PendingSyncItem>[];
    for (final idText in ids) {
      final id = int.tryParse(idText);
      if (id == null) continue;
      final payloadJson =
          await _storage.read(key: 'invoice_pending_complete_$id');
      if (payloadJson == null || payloadJson.isEmpty) continue;
      try {
        final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
        final rawItems = payload['items'];
        final details = rawItems is List
            ? rawItems
                .map((e) => InvoiceDetailTempDto.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList()
            : <InvoiceDetailTempDto>[];
        loaded.add(_PendingSyncItem(
          idInvoice: id,
          reason: payload['reason']?.toString() ?? 'Không rõ lỗi',
          savedAt: DateTime.tryParse(payload['savedAt']?.toString() ?? '') ??
              DateTime.now(),
          items: details,
        ));
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _items = loaded..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      _loading = false;
    });
  }

  Future<void> _removePending(int idInvoice) async {
    final idsJson = await _storage.read(key: 'pending_completed_invoices');
    final ids = <String>{};
    if (idsJson != null && idsJson.isNotEmpty) {
      try {
        ids.addAll(List<String>.from(jsonDecode(idsJson)));
      } catch (_) {}
    }
    ids.remove(idInvoice.toString());
    await Future.wait([
      _storage.write(
        key: 'pending_completed_invoices',
        value: jsonEncode(ids.toList()),
      ),
      _storage.delete(key: 'invoice_pending_complete_$idInvoice'),
      _storage.delete(key: 'invoice_temp_$idInvoice'),
    ]);
  }

  Future<void> _retrySync(_PendingSyncItem item) async {
    if (item.items.isEmpty) {
      Get.snackbar('Không thể đồng bộ', 'Không có dữ liệu chi tiết hóa đơn',
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    setState(() => _syncing.add(item.idInvoice));
    try {
      await _repository.create(item.items);
      await _removePending(item.idInvoice);
      Get.snackbar('Thành công', 'Đã đồng bộ đơn #${item.idInvoice}',
          backgroundColor: Colors.green, colorText: Colors.white);
      await _loadPendingItems();
    } catch (e) {
      Get.snackbar('Đồng bộ thất bại', e.toString(),
          backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _syncing.remove(item.idInvoice));
    }
  }

  Future<void> _retryAll() async {
    for (final item in List<_PendingSyncItem>.from(_items)) {
      if (!mounted) return;
      await _retrySync(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Đơn chờ đồng bộ'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPendingItems,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_done_rounded,
                          size: 56, color: Colors.green.shade400),
                      const SizedBox(height: 12),
                      const Text('Không có đơn chờ đồng bộ',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPendingItems,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) =>
                        _buildPendingCard(_items[index]),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: _items.length,
                  ),
                ),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              onPressed: _syncing.isEmpty ? _retryAll : null,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Đồng bộ tất cả'),
            ),
    );
  }

  Widget _buildPendingCard(_PendingSyncItem item) {
    final syncing = _syncing.contains(item.idInvoice);
    final completed = item.items
        .where((e) => (e.realQuantityDVT ?? 0) >= (e.quantity ?? 0))
        .length;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Hóa đơn #${item.idInvoice}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Chip(
                  label: Text('$completed/${item.items.length} dòng'),
                  backgroundColor: Colors.orange.shade50,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Lưu lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(item.savedAt)}'),
            const SizedBox(height: 6),
            Text('Lỗi trước đó: ${item.reason}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: syncing ? null : () => _retrySync(item),
                icon: syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(syncing ? 'Đang đồng bộ...' : 'Đồng bộ lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
