import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_background.dart';
import 'login_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  int    _step = 0;  // 0 = enter email, 1 = check email
  final  _emailController = TextEditingController();
  bool   _isLoading = false;
  String _sentEmail = '';

  @override
  void dispose() { _emailController.dispose(); super.dispose(); }

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() { _sentEmail = email; _step = 1; });
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':    msg = 'No account found with this email.'; break;
        case 'invalid-email':     msg = 'Invalid email address.'; break;
        case 'too-many-requests': msg = 'Too many attempts. Try again later.'; break;
        default: msg = e.message ?? 'Something went wrong.';
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _maskedEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    return name.length > 3
        ? '${name.substring(0, 3)}...@${parts[1]}'
        : '$name...@${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subColor   = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      body: AppBackground(   // ← uses your existing gradient (dark or light)
        child: SafeArea(
          child: Column(
            children: [
              // ── Back button ─────────────────────────────────────────────
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GestureDetector(
                    onTap: () {
                      if (_step == 0) {
                        Navigator.pop(context);
                      } else {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                        );
                      }
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.12)
                            : Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isDark ? [] : [
                          BoxShadow(color: Colors.black.withOpacity(0.1),
                              blurRadius: 8, spreadRadius: 1),
                        ],
                      ),
                      child: Icon(Icons.chevron_left,
                          color: isDark ? Colors.white70 : const Color(0xFF1565C0),
                          size: 26),
                    ),
                  ),
                ),
              ),

              // ── Content ─────────────────────────────────────────────────
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: _step == 0
                        ? _buildStep0(isDark, titleColor, subColor)
                        : _buildStep1(isDark, titleColor, subColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 0: enter email ───────────────────────────────────────────────────
  Widget _buildStep0(bool isDark, Color titleColor, Color subColor) {
    final inputBg    = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.85);
    final inputBorder= isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade300;
    final btnColor   = isDark ? const Color(0xFF5B6FA6) : const Color(0xFF1565C0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Forgot password',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                color: titleColor)),
        const SizedBox(height: 10),
        Text('Please enter your email to reset the password',
            style: TextStyle(fontSize: 15, color: subColor, height: 1.4)),
        const SizedBox(height: 40),

        // Email input
        Container(
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: inputBorder),
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Enter your email',
              hintStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Reset button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendResetEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: btnColor.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Reset Password',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── Step 1: check your email ──────────────────────────────────────────────
  Widget _buildStep1(bool isDark, Color titleColor, Color subColor) {
    final iconBg   = isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE3F2FD);
    final iconColor= isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
    final btnColor = isDark ? const Color(0xFF5B6FA6) : const Color(0xFF1565C0);
    final linkColor= isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(Icons.mark_email_read_outlined,
              color: iconColor, size: 42),
        ),
        const SizedBox(height: 24),
        Text('Check your email',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                color: titleColor)),
        const SizedBox(height: 12),
        Text(
          'We sent a password reset link to\n${_maskedEmail(_sentEmail)}.\n\n'
          'Open the link in your email to reset your password.\n'
          'Check your spam folder if you don\'t see it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: subColor, height: 1.5),
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Back to Login',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _sendResetEmail,
          child: RichText(
            text: TextSpan(
              text: "Didn't receive it? ",
              style: TextStyle(color: subColor, fontSize: 13),
              children: [
                TextSpan(
                  text: 'Resend email',
                  style: TextStyle(color: linkColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}