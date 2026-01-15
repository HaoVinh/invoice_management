import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../constants/env.dart';

import '../repository/auth_repostory.dart';
import '../model/Brand.dart';
import '../model/LoginDTO.dart';
part 'auth_event.dart';
part 'auth_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final AuthRepository authRepository;

  LoginBloc(this.authRepository) : super(const LoginInitial(branches: [])) {
    on<LoadInitialData>(_onLoadInitialData);
    on<LoginSubmitted>(_onLoginSubmitted);
  }

  Future<void> _onLoadInitialData(
      LoadInitialData event, Emitter<LoginState> emit) async {
    emit(const LoginLoading(branches: []));
    try {
      await Environment.initBranch();
      final branches = await authRepository.getBranches();
      final savedMember = await authRepository.getSavedLoginDTO();
      final savedBrand = await authRepository.getSavedBrand();
      final savedCredentials = await authRepository.getSavedCredentials();
      
      emit(LoginInitial(
        branches: branches,
        savedMember: savedMember,
        savedBranch: savedCredentials?['branch'] ?? savedBrand?.toBranch(),
        savedUsername: savedCredentials?['username'],
        savedPassword: savedCredentials?['password'],
      ));
    } catch (e) {
      emit(LoginFailure('Lỗi tải dữ liệu: $e', branches: []));
    }
  }

  Future<void> _onLoginSubmitted(
      LoginSubmitted event,
      Emitter<LoginState> emit,
      ) async {
    final currentState = state;
    List<Branch> branches = [];
    if (currentState is LoginInitial) {
      branches = currentState.branches;
    } else if (currentState is LoginLoading) {
      branches = currentState.branches;
    } else if (currentState is LoginSuccess) {
      branches = currentState.branches;
    } else if (currentState is LoginFailure) {
      branches = currentState.branches;
    }
    emit(LoginLoading(branches: branches));
    try {
      final result = await authRepository.login(
        event.email,
        event.password,
        event.branch,
      );
      print('Login result: $result');
      if (result['success'] == true) {
        final token = await authRepository.getToken();
        print('Login successful, token: $token');
        
        // Lưu credentials để tự động điền lần sau
        await authRepository.saveCredentials(
          username: event.email,
          password: event.password,
          branch: event.branch,
        );
        
        emit(LoginSuccess(branches: branches));
      } else {
        emit(LoginFailure(
          result['error']?.toString() ?? 'Đăng nhập thất bại',
          branches: branches,
        ));
      }
    } catch (e) {
      print('Login bloc error: $e');
      emit(LoginFailure('Đăng nhập thất bại: $e', branches: branches));
    }
  }


}