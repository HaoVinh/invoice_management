part of 'auth_bloc.dart';

@immutable
abstract class LoginState {
  final List<Branch> branches;

  const LoginState({required this.branches});
}

class LoginInitial extends LoginState {
  final LoginDTO? savedMember;
  final Branch? savedBranch;
  final String? savedUsername;
  final String? savedPassword;

  const LoginInitial({
    required List<Branch> branches,
    this.savedMember,
    this.savedBranch,
    this.savedUsername,
    this.savedPassword,
  }) : super(branches: branches);
}

class LoginLoading extends LoginState {
  const LoginLoading({required List<Branch> branches}) : super(branches: branches);
}

class LoginSuccess extends LoginState {
  const LoginSuccess({required List<Branch> branches}) : super(branches: branches);
}

class LoginFailure extends LoginState {
  final String error;

  const LoginFailure(this.error, {required List<Branch> branches}) : super(branches: branches);
}