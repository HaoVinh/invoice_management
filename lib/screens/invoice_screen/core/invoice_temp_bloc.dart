import 'package:bloc/bloc.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_temp_repository.dart';
import 'package:invoice_management/screens/invoice_screen/model/invoice_temp_dto.dart';
import 'package:equatable/equatable.dart';

part 'invoice_temp_event.dart';
part 'invoice_temp_state.dart';

class InvoiceTempBloc extends Bloc<InvoiceTempEvent, InvoiceTempState> {
  final InvoiceTempRepository invoiceTempRepository;

  InvoiceTempBloc(this.invoiceTempRepository) : super(InvoiceTempInitial()) {
    on<FetchInvoiceTempsEvent>(_onFetchInvoiceTemps);
    on<SaveInvoiceTempEvent>(_onSaveInvoiceTemp);
  }

  Future<void> _onFetchInvoiceTemps(
      FetchInvoiceTempsEvent event, Emitter<InvoiceTempState> emit) async {
    emit(InvoiceTempLoading());
    try {
      final invoiceTemps = await invoiceTempRepository.search(
        event.query ?? '',
        cm: event.cm,
        sDate: event.sDate,
        eDate: event.eDate,
      );
      emit(InvoiceTempLoaded(invoiceTemps));
    } catch (e) {
      emit(InvoiceTempError(e.toString()));
    }
  }
  Future<void> _onSaveInvoiceTemp(SaveInvoiceTempEvent event, Emitter<InvoiceTempState> emit) async {
    emit(InvoiceTempLoading());
    try {
      final savedInvoice = await invoiceTempRepository.create(event.invoiceTempDto);
      emit(InvoiceTempSaved(savedInvoice));
    } catch (e) {
      emit(InvoiceTempError(e.toString()));
    }
  }
}