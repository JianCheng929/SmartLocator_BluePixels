import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../theme_provider.dart';
import 'edit_profile_page.dart';
import 'auth_intro_page.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  // ── Shared dialog style (matches image 4) ────────────
  void _showConfirmDialog({
    required BuildContext context,
    required String message,
    required VoidCallback onYes,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message,
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // YES button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onYes();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2C2C2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Yes',
                      style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  // NO button
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
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
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final user = FirebaseAuth.instance.currentUser;

    // ── Colors based on theme ─────────────────────────
    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0xFFE3F2FD),
              Color(0xFFBBDEFB),
              Color(0xFF90CAF9),
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          );

    final cardColor = isDark ? const Color(0xFF16213E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final iconBg = isDark ? const Color(0xFF0F3460) : const Color(0xFFE8EAF6);
    final iconColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF5C6BC0);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Stack(
            children: [
            SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
            children: [
              // ── Back button row ───────────────────────
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
                child: Row(
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
                    ListenableBuilder(
                      listenable: BleService(),
                      builder: (_, __) => EspStatusBadge(
                        status: bleToEspStatus(BleService()),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Title ──────────────────────────────────
              Text('Account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                )),

              const SizedBox(height: 24),

              // ── Avatar ────────────────────────────────
              Stack(
                children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconBg,
                      border: Border.all(
                        color: iconColor.withOpacity(0.4), width: 2),
                    ),
                    child: Icon(Icons.person,
                      size: 55, color: iconColor),
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
              const SizedBox(height: 12),

              // ── Username & email ──────────────────────
              Text(
                user?.displayName ?? 'Username',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'email@example.com',
                style: TextStyle(fontSize: 14, color: subTextColor),
              ),

              const SizedBox(height: 20),

              // ── Edit Profile button ───────────────────
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const EditProfilePage()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 10),
                ),
                child: const Text('Edit Profile',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 28),

              // ── Settings list ─────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [

                    // THEME row (pill style like image 6)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8, offset: const Offset(0,3))],
                      ),
                      child: Row(
                        children: [
                          Text('Theme',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            )),
                          const Spacer(),
                          // Sun button
                          GestureDetector(
                            onTap: isDark ? themeProvider.toggleTheme : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: !isDark
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: !isDark
                                    ? [BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 6)]
                                    : [],
                              ),
                              child: Icon(Icons.wb_sunny,
                                color: !isDark
                                    ? Colors.orange
                                    : Colors.grey[400],
                                size: 20),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Moon button
                          GestureDetector(
                            onTap: !isDark ? themeProvider.toggleTheme : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF5C6BC0)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: isDark
                                    ? [BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 6)]
                                    : [],
                              ),
                              child: Icon(Icons.nightlight_round,
                                color: isDark
                                    ? Colors.white
                                    : Colors.grey[400],
                                size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // LOG OUT row (pill style, red icon)
                    Material(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(50),
                      child: InkWell(
                        onTap: () => _showConfirmDialog(
                          context: context,
                          message: 'Do you sure to log out\nthe account?',
                          onYes: () async {
                            await AuthService().signOut();
                            if (!context.mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const AuthIntroPage()),
                              (route) => false,
                            );
                          },
                        ),
                        borderRadius: BorderRadius.circular(50),
                        splashColor: Colors.red.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.redAccent, width: 1.5),
                                ),
                                child: const Icon(Icons.logout_outlined,
                                  color: Colors.redAccent, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Text('Log out',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                )),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // DELETE ACCOUNT row (pill style, orange icon)
                    Material(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(50),
                      child: InkWell(
                        onTap: () => _showConfirmDialog(
                          context: context,
                          message: 'Do you sure to delete\nthe account?',
                          onYes: () async {
                            try {
                              await FirebaseAuth.instance.currentUser?.delete();
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const AuthIntroPage()),
                                (route) => false,
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please log out and log in again before deleting.')),
                              );
                            }
                          },
                        ),
                        borderRadius: BorderRadius.circular(50),
                        splashColor: Colors.orange.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange, width: 1.5),
                                ),
                                child: Icon(Icons.delete_outline,
                                  color: Colors.orange[700], size: 20),
                              ),
                              const SizedBox(width: 14),
                              Text('Delete account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                )),
                            ],          // closes Row children
                          ),            // closes Row
                        ),              // closes Padding
                      ),               // closes InkWell
                    ),                 // closes Material (delete account)
                    const SizedBox(height: 24),
                  ],                   // closes inner Column children
                ),                  // closes inner Column
              ),                     // closes Padding
            ],                        // closes outer Column children
            ),                         // closes outer Column
          ),    
          ),
         ],                       // closes SingleChildScrollView
        ),                             // closes SafeArea
      ), 
      ),                              // closes Container
    );                                 // closes Scaffold
  }          
}                          // closes build method

// ── Helper: compute EspStatus from BleService ─────────────────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}