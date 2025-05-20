part of 'invoice_temp_bloc.dart';


abstract class InvoiceTempEvent extends Equatable {
  const InvoiceTempEvent();

  @override
  List<Object?> get props => [];
}

class FetchInvoiceTempsEvent extends InvoiceTempEvent {
  final String cm;
  final String? sDate;
  final String? eDate;
  final String? query;

  const FetchInvoiceTempsEvent({
    required this.cm,
    this.sDate,
    this.eDate,
    this.query,
  });

  @override
  List<Object?> get props => [cm, sDate, eDate, query];
}
class SaveInvoiceTempEvent extends InvoiceTempEvent {
  final InvoiceTempDto invoiceTempDto;

  const SaveInvoiceTempEvent(this.invoiceTempDto);

  @override
  List<Object?> get props => [invoiceTempDto];
}