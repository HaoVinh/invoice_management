import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:invoice_management/screens/invoice_screen/repository/invoice_detail_temp_repository.dart';
import 'invoice_detail_temp_event.dart';
import 'invoice_detail_temp_state.dart';

class InvoiceDetailTempBloc extends Bloc<InvoiceDetailTempEvent, InvoiceDetailTempState> {
  final InvoiceDetailTempRepository repository;

  InvoiceDetailTempBloc(this.repository) : super(InvoiceDetailTempInitial()) {
    // Đăng ký xử lý sự kiện SearchInvoiceDetailEvent
    on<SearchInvoiceDetailEvent>(_onSearchInvoiceDetail);
    on<SaveInvoiceDetailTempEvent>(_onSaveInvoiceDetailTemp);
  }

  Future<void> _onSearchInvoiceDetail(
      SearchInvoiceDetailEvent event,
      Emitter<InvoiceDetailTempState> emit,
      ) async {
    emit(InvoiceDetailTempLoading());
    try {
      final invoiceDetails = await repository.searchInvoiceDetail(
        cm: event.cm,
        idInvoice: event.idInvoice,
      );
      emit(InvoiceDetailTempLoaded(invoiceDetails));
    } catch (e) {
      emit(InvoiceDetailTempError(e.toString()));
    }
  }

  Future<void> _onSaveInvoiceDetailTemp(
      SaveInvoiceDetailTempEvent event, Emitter<InvoiceDetailTempState> emit) async {
    emit(InvoiceDetailTempLoading());
    try {
      final result = await repository.create(event.invoiceDetailTempDtos);
      emit(InvoiceDetailTempSaved(result));
    } catch (e) {
      emit(InvoiceDetailTempError(e.toString()));
    }
  }
}