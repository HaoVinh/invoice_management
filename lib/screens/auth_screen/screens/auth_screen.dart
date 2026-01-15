import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:invoice_management/screens/home_screen/screen/home_screen.dart';

import '../../../constants/contains.dart';
import '../../../constants/env.dart';

import '../../../network/app_update_manager.dart';
import '../core/auth_bloc.dart';
import '../model/LoginDTO.dart';

class LoginScreen extends StatefulWidget {
  static const String routeName = '/login';

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  Branch? _selectedBranch;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    context.read<LoginBloc>().add(LoadInitialData());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateManager.checkForUpdate(context);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _checkNetwork() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/login3.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: BlocListener<LoginBloc, LoginState>(
                listener: (context, state) {
                  if (state is LoginSuccess) {
                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const HomeInvoiceScreen()),
                      (Route<dynamic> route) => false,
                    );
                  } else if (state is LoginFailure) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.error),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    );
                  }
                },
                child: BlocBuilder<LoginBloc, LoginState>(
                  builder: (context, state) {
                    List<Branch> branches = [];
                    if (state is LoginInitial) {
                      branches = state.branches.toSet().toList();
                      
                      // Tự động điền thông tin đã lưu
                      if (state.savedUsername != null && _emailController.text.isEmpty) {
                        _emailController.text = state.savedUsername!;
                      }
                      if (state.savedPassword != null && _passwordController.text.isEmpty) {
                        _passwordController.text = state.savedPassword!;
                      }
                      if (state.savedBranch != null && _selectedBranch == null) {
                        _selectedBranch = state.savedBranch;
                        if (_selectedBranch != null) {
                          Environment.switchBranch(_selectedBranch!);
                        }
                      }
                      
                      if (_selectedBranch == null ||
                          !branches.contains(_selectedBranch)) {
                        _selectedBranch = null;
                      }
                    } else if (state is LoginLoading) {
                      branches = state.branches;
                    } else if (state is LoginSuccess) {
                      branches = state.branches;
                    } else if (state is LoginFailure) {
                      branches = state.branches;
                    }

                    if (state is LoginLoading) {
                      return Center(
                          child:
                              CircularProgressIndicator(color: kPrimaryColor));
                    }

                    return Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Image.asset(
                              'assets/logos/logo.png',
                              height: 100,
                            ),
                          ),
                          // Tiêu đề
                          Text(
                            'Ứng dụng xuất kho',
                            style: GoogleFonts.poppins(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: kPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 35),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Dropdown chi nhánh
                                DropdownButtonFormField<Branch>(
                                  value: branches.contains(_selectedBranch)
                                      ? _selectedBranch
                                      : null,
                                  style: GoogleFonts.poppins(
                                    color: kTextColor,
                                    fontSize: 16,
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon:
                                        Icon(Icons.business_outlined, color: kPrimaryColor),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    contentPadding: const EdgeInsets.all(15),
                                    labelText: 'Chọn chi nhánh',
                                    labelStyle:
                                        TextStyle(color: Colors.black54),
                                  ),
                                  dropdownColor: Colors.white,
                                  items: branches.isNotEmpty
                                      ? branches.map((branch) {
                                          return DropdownMenuItem<Branch>(
                                            value: branch,
                                            child: Text(
                                                Environment.getNameBranch(
                                                        branch)
                                                    .toUpperCase()),
                                          );
                                        }).toList()
                                      : [
                                          const DropdownMenuItem<Branch>(
                                            value: null,
                                            enabled: false,
                                            child: Text('Không có chi nhánh'),
                                          ),
                                        ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedBranch = value;
                                    });
                                    if (value != null) {
                                      Environment.switchBranch(value);
                                    }
                                  },
                                  validator: (value) => value == null
                                      ? 'Vui lòng chọn chi nhánh'
                                      : null,
                                ),
                                const SizedBox(height: 20),
                                // Tên đăng nhập
                                TextFormField(
                                  controller: _emailController,
                                  style:
                                      GoogleFonts.poppins(color: Colors.black),
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(Icons.person,
                                        color: kPrimaryColor),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    contentPadding: const EdgeInsets.all(15),
                                    labelText: 'Tên đăng nhập',
                                    labelStyle:
                                        TextStyle(color: Colors.black54),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Tên đăng nhập không được để trống';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),
                                // Mật khẩu
                                TextFormField(
                                  controller: _passwordController,
                                  style:
                                      GoogleFonts.poppins(color: Colors.black),
                                  decoration: InputDecoration(
                                    prefixIcon:
                                        Icon(Icons.lock, color: kPrimaryColor),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    contentPadding: const EdgeInsets.all(15),
                                    labelText: 'Mật khẩu',
                                    labelStyle:
                                        TextStyle(color: Colors.black54),
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Mật khẩu không được để trống';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 30),
                                // Nút Đăng nhập
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 60, vertical: 15),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    elevation: 5,
                                  ),
                                  onPressed: () async {
                                    if (_formKey.currentState!.validate()) {
                                      if (await _checkNetwork()) {
                                        if (_selectedBranch != null) {
                                          print(
                                              'Submitting login with email: ${_emailController.text}, password: ${_passwordController.text}, branch: $_selectedBranch');
                                          if (!mounted) return;
                                          context.read<LoginBloc>().add(
                                                LoginSubmitted(
                                                  email: _emailController.text,
                                                  password:
                                                      _passwordController.text,
                                                  branch: _selectedBranch!,
                                                ),
                                              );
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                  'Vui lòng chọn chi nhánh'),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                            ),
                                          );
                                        }
                                      } else {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('THÔNG BÁO',
                                                style: TextStyle(
                                                    color: kPrimaryColor)),
                                            content: const Text(
                                                'Chưa bật kết nối mạng.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('ĐÓNG',
                                                    style: TextStyle(
                                                        color: kPrimaryColor)),
                                              ),
                                            ],
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(
                                    'Đăng nhập',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
