part of 'auth_bloc.dart';

abstract class LoginEvent {}

class LoginSubmitted extends LoginEvent {
  final String email;
  final String password;
  final Branch branch;

  LoginSubmitted({
    required this.email,
    required this.password,
    required this.branch,
  });
}

class LoadInitialData extends LoginEvent {}