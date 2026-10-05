import 'package:flutter/material.dart';
import 'signup_page.dart';
import 'main_page.dart';
import 'forgot_password_page.dart';
import '../services/auth_service.dart';
import 'app_background.dart';
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus         = FocusNode();
  final _passwordFocus      = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading       = false;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

    Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    final error = await _authService.signInWithGoogle();
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const _LoginSuccessScreen()),
      );
    }
  }
  // ── LOGIN ─────────────────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final error = await _authService.login(
      email:    _emailController.text,
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      // ── Show success screen, then auto-navigate to MainPage ──────────
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const _LoginSuccessScreen()),
      );
    }
  }

  // ── FORGOT PASSWORD ───────────────────────────────────────────────────────
  void _handleForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: AppBackground(
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              top: -80, right: -80,
              child: Container(width: 220, height: 220,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 255, 250, 250),
                  shape: BoxShape.circle))),
            Positioned(
              top: -60, right: -40,
              child: Container(width: 180, height: 180,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 96, 142, 188),
                  shape: BoxShape.circle))),
            Positioned(
              bottom: -80, left: -80,
              child: Container(width: 220, height: 220,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 96, 142, 188),
                  shape: BoxShape.circle))),
            Positioned(
              bottom: -60, left: -40,
              child: Container(width: 180, height: 180,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 255, 250, 250),
                  shape: BoxShape.circle))),

            // Back button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 24, top: 16),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10, spreadRadius: 2)],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios,
                            size: 16, color: Color(0xFF1565C0)),
                        SizedBox(width: 4),
                        Text('Sign Up', style: TextStyle(
                            color: Color(0xFF1565C0),
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A2F4A) : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20, spreadRadius: 5,
                        offset: const Offset(0, 10))],
                    ),
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('LOG IN',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0))),
                        const SizedBox(height: 30),

                        _buildTextField(
                          controller: _emailController,
                          hintText:  'Email',
                          icon:      Icons.email_outlined,
                          focusNode: _emailFocus,
                        ),
                        const SizedBox(height: 16),

                        _buildPasswordField(
                          controller:  _passwordController,
                          hintText:    'Password',
                          obscureText: _obscurePassword,
                          onToggle: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          focusNode: _passwordFocus,
                        ),
                        const SizedBox(height: 24),

                        // Log In button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color.fromARGB(255, 80, 152, 224),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[300],
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5))
                                : const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text('Log In',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold)),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Divider ──
                        Row(children: [
                          Expanded(child: Divider(color: Colors.grey[300])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                          ),
                          Expanded(child: Divider(color: Colors.grey[300])),
                        ]),

                        const SizedBox(height: 16),

                        // ── Google Sign In ──
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : _handleGoogleLogin,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              backgroundColor: isDark
                                  ? const Color(0xFF1E3348) : Colors.white,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/google_logo.png',
                                  width: 24, height: 24,
                                ),
                                const SizedBox(width: 12),
                                Text('Sign in with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87)),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Forgot password
                        Center(
                          child: GestureDetector(
                            onTap: _handleForgotPassword,
                            child: const Text('Forgot Password?',
                              style: TextStyle(
                                color: Color(0xFF1565C0),
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
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

  // ── Text field ────────────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required FocusNode focusNode,
  }) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final isFocused = focusNode.hasFocus;
        return Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: isFocused ? const Color(0xFF7C4DFF) : Colors.grey[300]!,
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
              ? const Color(0xFF1E3348) : const Color(0xFFF5F5F5)),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.emailAddress,
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
);      },
    );
  }

  // ── Password field ────────────────────────────────────────────────────────
  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggle,
    required FocusNode focusNode,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isFocused = focusNode.hasFocus;
        final hasText   = controller.text.isNotEmpty;

        Color bgColor;
        Color borderColor;
        Color iconColor;

        if (isFocused) {
          bgColor     = isDark ? const Color(0xFF243D56) : Colors.white;
          borderColor = const Color(0xFF7C4DFF);
          iconColor   = const Color(0xFF7C4DFF);
        } else if (hasText) {
          bgColor     = isDark ? const Color(0xFF1E3348) : const Color(0xFFF5F5F5);
          borderColor = Colors.grey[300]!;
          iconColor   = Colors.grey[400]!;
        } else {
          bgColor     = isDark ? const Color(0xFF1E3348) : const Color(0xFFF5F5F5);
          borderColor = Colors.grey[300]!;
          iconColor   = Colors.grey[400]!;
        }

          return Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: borderColor, width: isFocused ? 2 : 1),
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
          suffixIcon: IconButton(
            icon: Icon(obscureText
                ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[400]),
            onPressed: onToggle,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
        ),
      ),
    ),
  ),
);      },
    );
  }
}

// ── Only the _LoginSuccessScreen class needs updating ─────────────────────
// Replace the existing _LoginSuccessScreen and _LoginSuccessScreenState
// at the BOTTOM of your login_page.dart with this:

// ── Login Success Screen — dark/light mode aware ───────────────────────────
class _LoginSuccessScreen extends StatefulWidget {
  const _LoginSuccessScreen();
  @override
  State<_LoginSuccessScreen> createState() => _LoginSuccessScreenState();
}

class _LoginSuccessScreenState extends State<_LoginSuccessScreen>
    with TickerProviderStateMixin {

  late AnimationController _ringController;
  late Animation<double>   _ringScale;
  late Animation<double>   _ringOpacity;
  late AnimationController _checkController;
  late Animation<double>   _checkScale;
  late Animation<double>   _checkOpacity;

  @override
  void initState() {
    super.initState();

    _ringController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _ringScale = Tween<double>(begin: 0.1, end: 1.0).animate(
        CurvedAnimation(parent: _ringController, curve: Curves.easeOutCubic));
    _ringOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ringController,
            curve: const Interval(0.0, 0.5, curve: Curves.easeIn)));

    _checkController = AnimationController(
        duration: const Duration(milliseconds: 400), vsync: this);
    _checkScale = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _checkController, curve: Curves.elasticOut));
    _checkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _checkController, curve: Curves.easeIn));

    _ringController.forward().then((_) {
      if (mounted) _checkController.forward();
    });

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final ringColor  = isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
  final textColor  = isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
  // ✅ 新增 inner fill
  final fillColor  = isDark
      ? const Color(0xFF1565C0).withOpacity(0.25)
      : const Color(0xFF90CAF9).withOpacity(0.20);

  return Scaffold(
    body: AppBackground(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140, height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ✅ Expanding ring with fill
                  AnimatedBuilder(
                    animation: _ringController,
                    builder: (_, __) => Opacity(
                      opacity: _ringOpacity.value,
                      child: Transform.scale(
                        scale: _ringScale.value,
                        child: Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: fillColor, // ✅ soft fill
                            border: Border.all(color: ringColor, width: 2.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Check icon
                  AnimatedBuilder(
                    animation: _checkController,
                    builder: (_, __) => Opacity(
                      opacity: _checkOpacity.value,
                      child: Transform.scale(
                        scale: _checkScale.value,
                        child: Icon(Icons.check, color: ringColor, size: 48),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _checkController,
              builder: (_, __) => Opacity(
                opacity: _checkOpacity.value,
                child: Text('Successful',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

