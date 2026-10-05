import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

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
        title: Text('Privacy Policy',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          )),
        centerTitle: true,
         actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: EspStatusBadge(status: bleToEspStatus(BleService())),
          ),
        ],
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
                  colors: [Color(0xFF0277BD), Color(0xFF0288D1)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 32),
                  const SizedBox(height: 12),
                  const Text('Privacy Policy',
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
              title: '1. Information We Collect',
              content:
                'We collect the following information when you use SmartLocator BluPixels:\n\n'
                '• Account information: username and email address\n'
                '• Device data: Bluetooth device names and signal strength (RSSI)\n'
                '• Sensor data: atmospheric pressure readings for floor detection\n'
                '• Usage data: item names, tracking history stored locally on your device',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.storage_outlined,
              title: '2. How We Store Your Data',
              content:
                'Your account data is securely stored in Firebase — a Google Cloud platform '
                'with industry-standard encryption. Real-time tracking data is stored in '
                'Firebase Realtime Database. History and last-seen data is stored locally '
                'on your device using Hive database and is never uploaded to the cloud.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.share_outlined,
              title: '3. Data Sharing',
              content:
                'We do NOT sell, trade, or share your personal data with third parties. '
                'Your data is used solely to provide the SmartLocator BluPixels service. '
                'We may use anonymized, aggregated feedback data to improve the app.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.location_off_outlined,
              title: '4. Location & Bluetooth Data',
              content:
                'Location permission is required by Android to scan for Bluetooth devices. '
                'We do NOT track or store your GPS location. Bluetooth scanning is used '
                'only to detect your SmartLocator device. No location data is transmitted '
                'to our servers.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.lock_outline,
              title: '5. Data Security',
              content:
                'We implement appropriate security measures to protect your personal '
                'information. Your password is never stored — Firebase Auth handles '
                'authentication with industry-standard hashing. We recommend using '
                'a strong, unique password for your account.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.person_outline,
              title: '6. Your Rights',
              content:
                'You have the right to:\n\n'
                '• Access your personal data stored in the app\n'
                '• Edit your profile information at any time\n'
                '• Delete your account and all associated data\n'
                '• Export your tracking history from the History page',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.child_care_outlined,
              title: '7. Children\'s Privacy',
              content:
                'SmartLocator BluPixels is not intended for children under 13 years of age. '
                'We do not knowingly collect personal information from children under 13. '
                'If you believe a child has provided us with personal information, '
                'please contact us immediately.',
            ),

            _buildSection(
              cardColor: cardColor,
              textColor: textColor,
              subColor: subColor,
              icon: Icons.mail_outline,
              title: '8. Contact Us',
              content:
                'For any privacy-related questions or to request data deletion, '
                'please contact us at: smartlocator.bluepixels@gmail.com\n\n'
                'We will respond within 48 hours.',
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
                Icon(icon, color: const Color(0xFF0277BD), size: 20),
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

// ── Helper: compute EspStatus from BleService ─────────────────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}