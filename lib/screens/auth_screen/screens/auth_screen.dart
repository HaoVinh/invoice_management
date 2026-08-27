import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:invoice_management/screens/home_screen/screen/home_screen.dart';

import '../../../constants/contains.dart';
import '../../../constants/env.dart';
import '../../../network/app_update_manager.dart';
import '../core/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  static const String routeName = '/login';

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Branch? _selectedBranch;
  bool _obscurePassword = true;

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
    return !connectivityResult.contains(ConnectivityResult.none);
  }

  void _applySavedLogin(LoginInitial state, List<Branch> branches) {
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
    if (_selectedBranch == null || !branches.contains(_selectedBranch)) {
      _selectedBranch = null;
    }
  }

  List<Branch> _branchesFromState(LoginState state) {
    if (state is LoginInitial) return state.branches.toSet().toList();
    if (state is LoginLoading) return state.branches;
    if (state is LoginSuccess) return state.branches;
    if (state is LoginFailure) return state.branches;
    return [];
  }

  Future<void> _submitLogin(List<Branch> branches) async {
    if (!_formKey.currentState!.validate()) return;

    if (!await _checkNetwork()) {
      if (!mounted) return;
      _showNetworkDialog();
      return;
    }

    if (_selectedBranch == null || !branches.contains(_selectedBranch)) {
      _showSnackBar('Vui lòng chọn chi nhánh', isError: true);
      return;
    }

    if (!mounted) return;
    context.read<LoginBloc>().add(
          LoginSubmitted(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            branch: _selectedBranch!,
          ),
        );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : kPrimaryColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showNetworkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'THÔNG BÁO',
          style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w800),
        ),
        content: const Text('Chưa bật kết nối mạng.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ĐÓNG',
              style:
                  TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: BlocListener<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is LoginSuccess) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (context) => const HomeInvoiceScreen()),
              (Route<dynamic> route) => false,
            );
          } else if (state is LoginFailure) {
            _showSnackBar(state.error, isError: true);
          }
        },
        child: BlocBuilder<LoginBloc, LoginState>(
          builder: (context, state) {
            final branches = _branchesFromState(state);
            if (state is LoginInitial) {
              _applySavedLogin(state, branches);
            }

            final isLoading = state is LoginLoading;

            return Stack(
              children: [
                _buildBackground(),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          children: [
                            _buildBrandHeader(),
                            const SizedBox(height: 22),
                            _buildLoginCard(branches, isLoading),
                            const SizedBox(height: 18),
                            _buildFooter(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8FFF5),
            Color(0xFFF6FBFF),
            Color(0xFFFFFFFF),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -80,
            child: _buildGlowCircle(230, kPrimaryColor.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: -90,
            bottom: -110,
            child: _buildGlowCircle(
                260, const Color(0xFF2D9CDB).withValues(alpha: 0.13)),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: const AssetImage('assets/images/login3.jpg'),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.white.withValues(alpha: 0.82),
                    BlendMode.lighten,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          width: 112,
          height: 112,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.14),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Image.asset('assets/logos/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(height: 18),
        Text(
          'Ứng dụng xuất kho',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: kTextColor,
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Đăng nhập để tiếp tục lên hàng xuất kho',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(List<Branch> branches, bool isLoading) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Đăng nhập',
              style: GoogleFonts.poppins(
                color: kTextColor,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Đăng nhập để tiếp tục lên hàng xuất kho',
              style: GoogleFonts.poppins(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            _buildBranchDropdown(branches, isLoading),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _emailController,
              label: 'Tên đăng nhập',
              hintText: 'Nhập tên đăng nhập',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Tên đăng nhập không được để trống';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Mật khẩu',
              hintText: 'Nhập mật khẩu',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              suffix: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.grey.shade600,
                ),
              ),
              onFieldSubmitted: (_) => _submitLogin(branches),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Mật khẩu không được để trống';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            _buildLoginButton(branches, isLoading),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchDropdown(List<Branch> branches, bool isLoading) {
    final hasSelectedBranch = branches.contains(_selectedBranch);

    return DropdownButtonFormField<Branch>(
      initialValue: hasSelectedBranch ? _selectedBranch : null,
      isExpanded: true,
      dropdownColor: Colors.white,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      style: GoogleFonts.poppins(
        color: kTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: _inputDecoration(
        label: 'Chi nhánh',
        hintText: isLoading ? 'Đang tải chi nhánh...' : 'Chọn chi nhánh',
        icon: Icons.business_outlined,
      ),
      items: branches.isNotEmpty
          ? branches.map((branch) {
              return DropdownMenuItem<Branch>(
                value: branch,
                child: Text(Environment.getNameBranch(branch).toUpperCase()),
              );
            }).toList()
          : [
              const DropdownMenuItem<Branch>(
                value: null,
                enabled: false,
                child: Text('Không có chi nhánh'),
              ),
            ],
      onChanged: isLoading
          ? null
          : (value) {
              setState(() => _selectedBranch = value);
              if (value != null) Environment.switchBranch(value);
            },
      validator: (value) => value == null ? 'Vui lòng chọn chi nhánh' : null,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffix,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: GoogleFonts.poppins(
        color: kTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: _inputDecoration(
        label: label,
        hintText: hintText,
        icon: icon,
        suffix: suffix,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hintText,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: GoogleFonts.poppins(
        color: Colors.grey.shade700,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: GoogleFonts.poppins(
        color: Colors.grey.shade400,
        fontSize: 13,
      ),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, color: kPrimaryColor, size: 22),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF7FAF9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.4),
      ),
    );
  }

  Widget _buildLoginButton(List<Branch> branches, bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: kPrimaryColor.withValues(alpha: 0.62),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: isLoading ? null : () => _submitLogin(branches),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Đăng nhập',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'LIXCO • App xuất kho',
        style: GoogleFonts.poppins(
          color: Colors.grey.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
