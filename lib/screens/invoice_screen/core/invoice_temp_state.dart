part of 'invoice_temp_bloc.dart';

abstract class InvoiceTempState extends Equatable {
  const InvoiceTempState();

  @override
  List<Object?> get props => [];
}

class InvoiceTempInitial extends InvoiceTempState {}

class InvoiceTempLoading extends InvoiceTempState {}

class InvoiceTempLoaded extends InvoiceTempState {
  final List<InvoiceTempDto> invoiceTemps;

  const InvoiceTempLoaded(this.invoiceTemps);

  @override
  List<Object?> get props => [invoiceTemps];
}

class InvoiceTempError extends InvoiceTempState {
  final String message;

  const InvoiceTempError(this.message);

  @override
  List<Object?> get props => [message];
}
class InvoiceTempSaved extends InvoiceTempState {
  final InvoiceTempDto? savedInvoice;

  const InvoiceTempSaved(this.savedInvoice);

  @override
  List<Object?> get props => [savedInvoice];
}