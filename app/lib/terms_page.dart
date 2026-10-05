import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;
    final cardColor = isDark ? const Color(0xFF16213E) : const Color(0xFFF5F7FA);
    final accentColor = const Color(0xFF1565C0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: accentColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Terms & Conditions',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          )),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.gavel, color: Colors.white, size: 32),
                  const SizedBox(height: 12),
                  const Text('Terms & Conditions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    )),
                  const SizedBox(height: 6),
                  Text('Last updated: March 2026',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    )),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.info_outline,
              title: '1. Acceptance of Terms',
              content:
                'By downloading, installing, or using the SmartLocator BluPixels app, '
                'you agree to be bound by these Terms and Conditions. If you do not agree '
                'to these terms, please do not use this application.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.devices,
              title: '2. Use of the Application',
              content:
                'SmartLocator BluPixels is designed for personal item tracking using '
                'Bluetooth Low Energy (BLE) technology. You agree to use this app only '
                'for lawful purposes and in accordance with these terms. You must not '
                'use this app to track individuals without their consent.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.bluetooth,
              title: '3. Bluetooth & Location Permissions',
              content:
                'This app requires Bluetooth and location permissions to function properly. '
                'These permissions are used solely for detecting and connecting to your '
                'SmartLocator device. We do not collect or share your location data with '
                'third parties.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.account_circle_outlined,
              title: '4. User Account',
              content:
                'You are responsible for maintaining the confidentiality of your account '
                'credentials. You agree to notify us immediately of any unauthorized use '
                'of your account. We reserve the right to terminate accounts that violate '
                'these terms.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.warning_amber_outlined,
              title: '5. Limitations of Liability',
              content:
                'SmartLocator BluPixels is provided as a tracking aid tool. We are not '
                'liable for any loss, theft, or damage to your personal items. The app '
                'accuracy depends on Bluetooth signal strength and environmental factors '
                'which may affect performance.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.update,
              title: '6. Changes to Terms',
              content:
                'We reserve the right to modify these terms at any time. Continued use '
                'of the application after changes constitutes acceptance of the new terms. '
                'We will notify users of significant changes via the app.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.mail_outline,
              title: '7. Contact Us',
              content:
                'If you have any questions about these Terms and Conditions, '
                'please contact us at: smartlocator.bluepixels@gmail.com',
            ),

            const SizedBox(height: 24),

            // Accept button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('I Understand',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required Color cardColor,
    required Color textColor,
    required Color subColor,
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF1565C0), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    )),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(content,
              style: TextStyle(
                fontSize: 14,
                color: subColor,
                height: 1.6,
              )),
          ],
        ),
      ),
    );
  }
}