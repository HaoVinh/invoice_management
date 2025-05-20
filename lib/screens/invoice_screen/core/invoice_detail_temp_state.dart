import '../model/invoice_detail_temp_dto.dart';

abstract class InvoiceDetailTempState {}

class InvoiceDetailTempInitial extends InvoiceDetailTempState {}

class InvoiceDetailTempLoading extends InvoiceDetailTempState {}

class InvoiceDetailTempLoaded extends InvoiceDetailTempState {
  final List<InvoiceDetailTempDto> invoiceDetails;

  InvoiceDetailTempLoaded(this.invoiceDetails);
}

class InvoiceDetailTempError extends InvoiceDetailTempState {
  final String message;

  InvoiceDetailTempError(this.message);
}
class InvoiceDetailTempSaved extends InvoiceDetailTempState {
  final List<InvoiceDetailTempDto> savedInvoiceDetailTemp;

   InvoiceDetailTempSaved(this.savedInvoiceDetailTemp);

  @override
  List<Object?> get props => [savedInvoiceDetailTemp];
}