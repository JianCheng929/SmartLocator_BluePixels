import 'package:flutter/material.dart';
import 'login_page.dart';
import '../services/auth_service.dart';  // ← ADD THIS
import 'package:flutter/gestures.dart';    // ← ADD
import 'terms_page.dart';                   // ← ADD
import 'privacy_page.dart';                 // ← ADD
import 'app_background.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  bool _isLoading = false;              // ← ADD THIS
  final AuthService _authService = AuthService();  // ← ADD THIS

  bool get _passwordsMatch =>
      _passwordController.text == _confirmPasswordController.text &&
      _passwordController.text.isNotEmpty;

  bool get _hasPasswordInput =>
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
    // ADD THESE - Dispose focus nodes
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
  }

  // ── SIGN UP HANDLER ───────────────────────────────────
  Future<void> _handleSignUp() async {
    if (_usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    if (!_passwordsMatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to Terms & Conditions.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final error = await _authService.signUp(
      username: _usernameController.text,
      email: _emailController.text,
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    // ✅ 新 — 跳转到 LoginPage
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully! 🎉')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;      // ← ADD
    final cardColor = isDark ? const Color(0xFF1A2F4A) : Colors.white;   // ← ADD
    return Scaffold(
      body: AppBackground(
        child: Stack(
          children: [
            // ── decorative circles (keep your existing ones) ──
            Positioned(
              top: -80, right: -80,
              child: Container(width: 220, height: 220,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 255, 250, 250),
                  shape: BoxShape.circle)),
            ),
            Positioned(
              top: -60, right: -40,
              child: Container(width: 180, height: 180,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 96, 142, 188),
                  shape: BoxShape.circle)),
            ),
            Positioned(
              bottom: -80, left: -80,
              child: Container(width: 220, height: 220,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 96, 142, 188),
                  shape: BoxShape.circle)),
            ),
            Positioned(
              bottom: -60, left: -40,
              child: Container(width: 180, height: 180,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 255, 250, 250),
                  shape: BoxShape.circle)),
            ),

            // ── MAIN CONTENT ──
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1A2F4A)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'SIGN UP',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 30),

                        _buildTextField(
                          controller: _usernameController,
                          hintText: 'Username',
                          icon: Icons.person_outline,
                          isPassword: false,
                          focusNode: _usernameFocus,  // ADD THIS
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _emailController,
                          hintText: 'Email',
                          icon: Icons.email_outlined,
                          isPassword: false,
                          keyboardType: TextInputType.emailAddress,
                          focusNode: _emailFocus,  // ADD THIS
                        ),
                        const SizedBox(height: 16),
                        _buildPasswordField(
                          controller: _passwordController,
                          hintText: 'Password',
                          obscureText: _obscurePassword,
                          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                          focusNode: _passwordFocus,  // ADD THIS
                        ),
                        const SizedBox(height: 16),
                        _buildConfirmPasswordField(),
                        if (_hasPasswordInput)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 8),
                            child: Row(
                              children: [
                                Icon(
                                  _passwordsMatch ? Icons.check_circle : Icons.error,
                                  color: _passwordsMatch ? Colors.green : Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _passwordsMatch
                                      ? 'Passwords match'
                                      : 'Passwords do not match',
                                  style: TextStyle(
                                    color: _passwordsMatch ? Colors.green : Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 16),

                        // TERMS & CONDITIONS CHECKBOX (keep your existing widget)
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: _agreedToTerms
                                      ? const Color(0xFF1565C0)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _agreedToTerms
                                        ? const Color(0xFF1565C0)
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                ),
                                child: _agreedToTerms
                                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                  children: [
                                    const TextSpan(text: 'I agree to the '),
                                    TextSpan(
                                      text: 'Terms & Conditions',
                                      style: const TextStyle(
                                        color: Color(0xFF1565C0),
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => const TermsPage()),
                                        ),
                                    ),
                                    const TextSpan(text: ' and '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: const TextStyle(
                                        color: Color(0xFF1565C0),
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => const PrivacyPage()),
                                        ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ── SIGN UP BUTTON (updated) ──
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: (_passwordsMatch && _hasPasswordInput && _agreedToTerms && !_isLoading)
                                ? _handleSignUp
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 80, 152, 224),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[300],
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Sign Up',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ALREADY HAVE ACCOUNT
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Already have an account? ',
                                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => const LoginPage()),
                                ),
                                child: const Text('Log in',
                                  style: TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  )),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── keep all your existing _build methods unchanged ──
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool isPassword,
    required FocusNode focusNode,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return AnimatedBuilder(
    animation: focusNode,
    builder: (context, child) {
      bool isFocused = focusNode.hasFocus;
      bool hasText = controller.text.isNotEmpty;
      
        return Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: isFocused ? const Color(0xFF7C4DFF) : Colors.grey[200]!,
      width: isFocused ? 2 : 1,
    ),
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      color: isFocused
          ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF243D56) : Colors.white)
          : (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E3348) : Colors.grey[50]!),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(icon,
            color: isFocused ? const Color(0xFF7C4DFF) : Colors.grey[400]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
        ),
      ),
    ),
  ),
);
    },
  );  
  }

  Widget _buildPasswordField({
  required TextEditingController controller,
  required String hintText,
  required bool obscureText,
  required VoidCallback onToggle,
  required FocusNode focusNode,  // ADD THIS PARAMETER
}) {
  return AnimatedBuilder(
    animation: Listenable.merge([controller, focusNode]),
    builder: (context, child) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      bool isFocused = focusNode.hasFocus;
      bool hasText = controller.text.isNotEmpty;
      bool isValid = hasText && controller.text.length >= 6;  // Basic validation
      
      // Determine colors based on state
      Color bgColor;
      Color borderColor;
      Color iconColor;
      
      if (isValid && !isFocused) {
        bgColor = isDark ? const Color(0xFF1B3D2A) : const Color(0xFFE8F5E9);
        borderColor = Colors.green;
        iconColor = Colors.green;
      } else if (isFocused) {
        bgColor = isDark ? const Color(0xFF243D56) : Colors.white;
        borderColor = const Color(0xFF7C4DFF);
        iconColor = const Color(0xFF7C4DFF);
      } else {
        bgColor = isDark ? const Color(0xFF1E3348) : Colors.grey[50]!;
        borderColor = Colors.grey[200]!;
        iconColor = Colors.grey[400]!;
      }
      
      
        return Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: borderColor,
      width: isFocused || isValid ? 2 : 1,
    ),
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      color: bgColor,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(Icons.lock_outline, color: iconColor),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isValid && !isFocused) ...[
                const Icon(Icons.check, color: Colors.green, size: 20),
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: Icon(obscureText
                    ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[400]),
                onPressed: onToggle,
              ),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
        ),
      ),
    ),
  ),
);
    },
  );
}

  Widget _buildConfirmPasswordField() {
  return AnimatedBuilder(
    animation: Listenable.merge([
      _passwordController, 
      _confirmPasswordController,
      _confirmPasswordFocus
    ]),
    builder: (context, child) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      bool isFocused = _confirmPasswordFocus.hasFocus;
      bool hasInput = _confirmPasswordController.text.isNotEmpty;
      bool isMatch = _passwordsMatch && hasInput;
      bool isDifferent = !isMatch && hasInput && _passwordController.text.isNotEmpty;
      
      // Determine colors based on state
      Color bgColor;
      Color borderColor;
      Color iconColor;
      Widget? statusIcon;

      if (isMatch && !isFocused) {
        bgColor = isDark ? const Color(0xFF1B3D2A) : const Color(0xFFE8F5E9);
        borderColor = Colors.green;
        iconColor = Colors.green;
        statusIcon = const Icon(Icons.check, color: Colors.green, size: 20);
      } else if (isDifferent && !isFocused) {
        bgColor = isDark ? const Color(0xFF3D1A1A) : const Color(0xFFFFEBEE);
        borderColor = Colors.red;
        iconColor = Colors.red;
        statusIcon = const Icon(Icons.error_outline, color: Colors.red, size: 20);
      } else if (isFocused) {
        bgColor = isDark ? const Color(0xFF243D56) : Colors.white;
        borderColor = const Color(0xFF7C4DFF);
        iconColor = const Color(0xFF7C4DFF);
      } else {
        bgColor = isDark ? const Color(0xFF1E3348) : Colors.grey[50]!;
        borderColor = Colors.grey[200]!;
        iconColor = Colors.grey[400]!;
      }
      
        return Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: borderColor,
      width: (isFocused || isMatch || isDifferent) ? 2 : 1,
    ),
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Container(
      color: bgColor,
      child: TextField(
        controller: _confirmPasswordController,
        focusNode: _confirmPasswordFocus,
        obscureText: _obscureConfirmPassword,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Confirm Password',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(Icons.lock_outline, color: iconColor),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((isMatch || isDifferent) && !isFocused && hasInput) ...[
                statusIcon!,
                const SizedBox(width: 8),
              ],
              IconButton(
                icon: Icon(_obscureConfirmPassword
                    ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[400]),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
        ),
      ),
    ),
  ),
);
    }
  );
  } 
}