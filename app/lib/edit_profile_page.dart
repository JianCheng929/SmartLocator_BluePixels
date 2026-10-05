import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _usernameController = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _isLoading = false;
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus  = FocusNode();
  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _usernameController.text = user?.displayName ?? '';
    _emailController.text    = user?.email ?? '';


    _usernameFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
    _confirmFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }
  Future<String?> _askCurrentPassword() async {
  String? entered;
  bool obscure = true;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: const Text('Verify Identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your current password to continue.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: obscure,
              onChanged: (v) => entered = v,
              decoration: InputDecoration(
                hintText: 'Current password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure
                      ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setDlg(() => obscure = !obscure),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              entered = null;
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C6BC0)),
            child: const Text('Confirm',
              style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
  return (entered == null || entered!.isEmpty) ? null : entered;
}

  Future<void> _saveProfile() async {
    final newPwd     = _passwordController.text.trim();
    final confirmPwd = _confirmController.text.trim();
    final newName    = _usernameController.text.trim();

    // ── Password validation — only check if user typed anything ──────
    if (newPwd.isNotEmpty || confirmPwd.isNotEmpty) {
      if (newPwd.isEmpty || confirmPwd.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please fill both password fields.')));
        return;
      }
      if (newPwd != confirmPwd) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Passwords do not match.')));
        return;
      }
      if (newPwd.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Password must be at least 6 characters.')));
        return;
      }
    }

    // ── Nothing changed check ─────────────────────────────────────────
    final user = FirebaseAuth.instance.currentUser!;
    final nameUnchanged = newName == (user.displayName ?? '');
    final noPassword    = newPwd.isEmpty;
    if (nameUnchanged && noPassword) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No changes to save.')));
      return;
    }

    setState(() => _isLoading = true);
      try {
        // ✅ 如果要改密码，先重新验证身份
        if (!noPassword) {
          // 弹出对话框要求输入当前密码
          final currentPwd = await _askCurrentPassword();
          if (currentPwd == null) {
            setState(() => _isLoading = false);
            return; // 用户取消
          }
          // Re-authenticate
          final credential = EmailAuthProvider.credential(
            email: user.email!,
            password: currentPwd,
          );
          await user.reauthenticateWithCredential(credential);
          await user.updatePassword(newPwd);
        }
        if (!nameUnchanged && newName.isNotEmpty) {
          await user.updateDisplayName(newName);
        }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated! ✅')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFE3F2FD),
                     Color(0xFFBBDEFB), Color(0xFF90CAF9)],
            stops: [0.0, 0.3, 0.6, 1.0],
          );

    final fieldBg    = isDark ? const Color(0xFF16213E) : Colors.grey[50]!;
    final fieldBorder= isDark ? const Color(0xFF0F3460) : Colors.grey[200]!;
    final textColor  = isDark ? Colors.white : Colors.black87;
    final hintColor  = isDark ? Colors.grey[500]! : Colors.grey[400]!;
    final iconColor  = isDark ? const Color(0xFF90CAF9) : const Color(0xFF5C6BC0);
    final joinDate   = FirebaseAuth.instance.currentUser?.metadata.creationTime;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
              children: [
                const SizedBox(height: 20),

                // ✅ Back button + Status badge 同一行
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10, spreadRadius: 2)],
                        ),
                        child: const Icon(Icons.arrow_back,
                          color: Color(0xFF1565C0), size: 24),
                      ),
                    ),
                    const Spacer(),
                    EspStatusBadge(status: bleToEspStatus(BleService())),
                  ],
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),

                // Avatar
                Stack(
                  children: [
                    Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF0F3460)
                            : const Color(0xFFE8EAF6),
                        border: Border.all(
                          color: iconColor.withOpacity(0.4), width: 2),
                      ),
                      child: Icon(Icons.person, size: 55, color: iconColor),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.edit,
                          size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Username field
                _buildField(
                  controller: _usernameController,
                  focusNode: _usernameFocus,
                  hint: 'Username',
                  icon: Icons.person_outline,
                  fieldBg: fieldBg,
                  fieldBorder: fieldBorder,
                  hintColor: hintColor,
                  iconColor: iconColor,
                  textColor: textColor,
                ),
                const SizedBox(height: 16),

                // Email field (read only)
                _buildField(
                  controller: _emailController,
                  hint: 'Email',
                  icon: Icons.email_outlined,
                  fieldBg: fieldBg,
                  fieldBorder: fieldBorder,
                  hintColor: hintColor,
                  iconColor: iconColor,
                  textColor: textColor,
                  readOnly: true,
                ),
                const SizedBox(height: 16),

                // Password field
                _buildPasswordField(
                  controller: _passwordController,
                  focusNode: _passwordFocus, 
                  hint: 'New Password',
                  obscure: _obscurePassword,
                  onToggle: () => setState(
                    () => _obscurePassword = !_obscurePassword),
                  fieldBg: fieldBg,
                  fieldBorder: fieldBorder,
                  hintColor: hintColor,
                  iconColor: iconColor,
                  textColor: textColor,
                ),
                const SizedBox(height: 16),

                // Confirm password
                _buildPasswordField(
                  controller: _confirmController,
                  focusNode: _confirmFocus,
                  isConfirm: true,
                  hint: 'Confirm Password',
                  obscure: _obscureConfirm,
                  onToggle: () => setState(
                    () => _obscureConfirm = !_obscureConfirm),
                  fieldBg: fieldBg,
                  fieldBorder: fieldBorder,
                  hintColor: hintColor,
                  iconColor: iconColor,
                  textColor: textColor,
                ),

                const SizedBox(height: 28),

                // Edit Profile button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                        : const Text('Edit Profile',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),

                const SizedBox(height: 16),

                // Joined date + delete icon
                if (joinDate != null)
                  Row(
                    children: [
                      Text(
                        'Joined ${joinDate.day}/${joinDate.month}/${joinDate.year}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,   // ← was hintColor (too faint)
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(             // ← WRAP with GestureDetector
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Do you sure to delete\nthe account?',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        ElevatedButton(
                                          onPressed: () async {
                                            Navigator.pop(ctx);
                                            try {
                                              await FirebaseAuth.instance
                                                  .currentUser?.delete();
                                              if (!mounted) return;
                                              Navigator.of(context)
                                                  .pushNamedAndRemoveUntil(
                                                '/', (route) => false);
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                content: Text('Error: $e')));
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF2C2C2E),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          ),
                                          child: const Text('Yes',
                                            style: TextStyle(
                                              color: Colors.white)),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          style: OutlinedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          ),
                                          child: const Text('No'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.orange, width: 1.5),
                          ),
                          child: Icon(Icons.delete_outline,
                            color: Colors.orange[700], size: 20),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildField({
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  required Color fieldBg,
  required Color fieldBorder,
  required Color hintColor,
  required Color iconColor,
  required Color textColor,
  bool readOnly = false,
  FocusNode? focusNode,
}) {
  final isFocused = focusNode?.hasFocus ?? false;
  final borderColor = isFocused ? const Color(0xFF7C4DFF) : fieldBorder;
  final bgColor = isFocused ? fieldBg.withOpacity(0.9) : fieldBg;

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
          readOnly: readOnly,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: hintColor),
            prefixIcon: Icon(icon, color: isFocused ? const Color(0xFF7C4DFF) : iconColor),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildPasswordField({
  required TextEditingController controller,
  required String hint,
  required bool obscure,
  required VoidCallback onToggle,
  required Color fieldBg,
  required Color fieldBorder,
  required Color hintColor,
  required Color iconColor,
  required Color textColor,
  FocusNode? focusNode,
  bool isConfirm = false,
}) {
  final isFocused = focusNode?.hasFocus ?? false;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  // Password match logic for confirm field
  bool isMatch = false;
  bool isMismatch = false;
  if (isConfirm && controller.text.isNotEmpty) {
    isMatch = _passwordController.text == controller.text;
    isMismatch = !isMatch;
  }

  Color borderColor;
  Color bgColor;
  Color prefixColor;
  if (isMatch) {
    borderColor = Colors.green;
    bgColor = isDark ? const Color(0xFF1B3D2A) : const Color(0xFFE8F5E9);
    prefixColor = Colors.green;
  } else if (isMismatch) {
    borderColor = Colors.red;
    bgColor = isDark ? const Color(0xFF3D1A1A) : const Color(0xFFFFEBEE);
    prefixColor = Colors.red;
  } else if (isFocused) {
    borderColor = const Color(0xFF7C4DFF);
    bgColor = fieldBg;
    prefixColor = const Color(0xFF7C4DFF);
  } else {
    borderColor = fieldBorder;
    bgColor = fieldBg;
    prefixColor = iconColor;
  }

  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: borderColor,
        width: (isFocused || isMatch || isMismatch) ? 2 : 1,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: bgColor,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: hintColor),
            prefixIcon: Icon(Icons.lock_outline, color: prefixColor),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMatch) ...[
                  const Icon(Icons.check, color: Colors.green, size: 20),
                  const SizedBox(width: 4),
                ] else if (isMismatch) ...[
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: Icon(obscure
                      ? Icons.visibility_off : Icons.visibility,
                      color: hintColor),
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
}
}
// ── Helper: compute EspStatus from BleService ─────────────────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}