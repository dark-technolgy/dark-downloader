import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum AuthFormState { signIn, signUp, verifySignUpOtp, forgotPassword, resetPasswordOtp }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  
  AuthFormState _formState = AuthFormState.signIn;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final otp = _otpController.text.trim();
    
    if (email.isEmpty) {
      _showError('الرجاء إدخال البريد الإلكتروني');
      return;
    }

    if (_formState == AuthFormState.signUp && (password.isEmpty || name.isEmpty)) {
      _showError('الرجاء تعبئة جميع الحقول');
      return;
    }
    
    if (_formState == AuthFormState.signIn && password.isEmpty) {
      _showError('الرجاء إدخال كلمة المرور');
      return;
    }
    
    if ((_formState == AuthFormState.verifySignUpOtp || _formState == AuthFormState.resetPasswordOtp) && otp.isEmpty) {
      _showError('الرجاء إدخال رمز التحقق');
      return;
    }

    if (_formState == AuthFormState.resetPasswordOtp && password.isEmpty) {
      _showError('الرجاء إدخال كلمة المرور الجديدة');
      return;
    }

    setState(() => _isLoading = true);
    final auth = ref.read(authProvider.notifier);
    
    try {
      switch (_formState) {
        case AuthFormState.signIn:
          await auth.smartSignIn(email: email, password: password);
          break;
        case AuthFormState.signUp:
          final requiresOtp = await auth.smartSignUp(email: email, password: password, name: name);
          if (requiresOtp) {
            setState(() {
              _formState = AuthFormState.verifySignUpOtp;
              _otpController.clear();
            });
            _showSuccess('تم إرسال رمز التحقق إلى بريدك الإلكتروني');
          }
          break;
        case AuthFormState.verifySignUpOtp:
          await auth.verifyOTP(email: email, token: otp);
          break;
        case AuthFormState.forgotPassword:
          await auth.sendPasswordReset(email);
          setState(() {
            _formState = AuthFormState.resetPasswordOtp;
            _otpController.clear();
            _passwordController.clear();
          });
          _showSuccess('تم إرسال رمز الاستعادة إلى بريدك الإلكتروني');
          break;
        case AuthFormState.resetPasswordOtp:
          await auth.verifyOTP(email: email, token: otp, isRecovery: true);
          await auth.updatePassword(password);
          _showSuccess('تم تغيير كلمة المرور بنجاح! جاري تسجيل الدخول...');
          break;
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';

    String title = '';
    String btnText = '';

    switch (_formState) {
      case AuthFormState.signIn:
        title = isAr ? 'تسجيل الدخول' : 'Welcome Back';
        btnText = isAr ? 'دخول' : 'Sign In';
        break;
      case AuthFormState.signUp:
        title = isAr ? 'إنشاء حساب جديد' : 'Create Account';
        btnText = isAr ? 'تسجيل' : 'Sign Up';
        break;
      case AuthFormState.verifySignUpOtp:
        title = isAr ? 'تأكيد البريد' : 'Verify Email';
        btnText = isAr ? 'تأكيد' : 'Verify';
        break;
      case AuthFormState.forgotPassword:
        title = isAr ? 'نسيت كلمة المرور' : 'Forgot Password';
        btnText = isAr ? 'إرسال الرمز' : 'Send Code';
        break;
      case AuthFormState.resetPasswordOtp:
        title = isAr ? 'تعيين كلمة مرور جديدة' : 'Reset Password';
        btnText = isAr ? 'تحديث الدخول' : 'Update & Login';
        break;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFF003050), Colors.black],
                  center: Alignment.center,
                  radius: 1.5,
                ),
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.15),
                boxShadow: [
                  BoxShadow(color: Colors.blue.withValues(alpha: 0.2), blurRadius: 100),
                ],
              ),
            ),
          ),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          size: 64,
                          color: Color(0xFF00A3FF),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        
                        if (_formState == AuthFormState.signUp) ...[
                          _buildTextField(
                            controller: _nameController,
                            icon: Icons.person_rounded,
                            hint: isAr ? 'الاسم' : 'Name',
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        if (_formState != AuthFormState.verifySignUpOtp && _formState != AuthFormState.resetPasswordOtp) ...[
                          _buildTextField(
                            controller: _emailController,
                            icon: Icons.email_rounded,
                            hint: isAr ? 'البريد الإلكتروني' : 'Email Address',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (_formState == AuthFormState.verifySignUpOtp || _formState == AuthFormState.resetPasswordOtp) ...[
                          _buildTextField(
                            controller: _otpController,
                            icon: Icons.pin_rounded,
                            hint: isAr ? 'رمز التحقق (6 أرقام)' : 'Verification Code (6 digits)',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        if (_formState == AuthFormState.signIn || _formState == AuthFormState.signUp) ...[
                          _buildTextField(
                            controller: _passwordController,
                            icon: Icons.lock_rounded,
                            hint: isAr ? 'كلمة المرور' : 'Password',
                            obscureText: true,
                          ),
                          const SizedBox(height: 8),
                          if (_formState == AuthFormState.signIn)
                            Align(
                              alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => setState(() => _formState = AuthFormState.forgotPassword),
                                child: Text(
                                  isAr ? 'نسيت كلمة المرور؟' : 'Forgot Password?',
                                  style: const TextStyle(color: Colors.blue),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],

                        if (_formState == AuthFormState.resetPasswordOtp) ...[
                          _buildTextField(
                            controller: _passwordController,
                            icon: Icons.lock_rounded,
                            hint: isAr ? 'كلمة المرور الجديدة' : 'New Password',
                            obscureText: true,
                          ),
                          const SizedBox(height: 32),
                        ],
                        
                        if (_formState == AuthFormState.forgotPassword)
                          const SizedBox(height: 16),
                        
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00A3FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(
                                    btnText,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        if (_formState == AuthFormState.signIn || _formState == AuthFormState.signUp)
                          TextButton(
                            onPressed: () => setState(() {
                              _formState = _formState == AuthFormState.signIn ? AuthFormState.signUp : AuthFormState.signIn;
                            }),
                            child: Text(
                              _formState == AuthFormState.signUp 
                                ? (isAr ? 'لديك حساب؟ سجل دخولك' : 'Already have an account? Sign in')
                                : (isAr ? 'ليس لديك حساب؟ سجل الآن' : 'Need an account? Sign up'),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                            ),
                          ),

                        if (_formState == AuthFormState.verifySignUpOtp || _formState == AuthFormState.forgotPassword || _formState == AuthFormState.resetPasswordOtp)
                          TextButton(
                            onPressed: () => setState(() => _formState = AuthFormState.signIn),
                            child: Text(
                              isAr ? 'العودة لتسجيل الدخول' : 'Back to Sign In',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF00A3FF)),
        ),
      ),
    );
  }
}

