import 'package:invoice_management/screens/invoice_screen/model/invoice_detail_temp_dto.dart';

abstract class InvoiceDetailTempEvent {}

class SearchInvoiceDetailEvent extends InvoiceDetailTempEvent {
  final String cm;
  final int idInvoice;

  SearchInvoiceDetailEvent({required this.cm, required this.idInvoice});
}
class SaveInvoiceDetailTempEvent extends InvoiceDetailTempEvent {
  final List<InvoiceDetailTempDto> invoiceDetailTempDtos;

  SaveInvoiceDetailTempEvent(this.invoiceDetailTempDtos);

  @override
  List<Object?> get props => [invoiceDetailTempDtos];
}