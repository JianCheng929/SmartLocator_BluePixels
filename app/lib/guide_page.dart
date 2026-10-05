import 'package:flutter/material.dart';
import 'app_background.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1A2A3A) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.transparent,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8, spreadRadius: 1)],
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Color(0xFF1565C0), size: 22),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'User Guide',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF424242),
                      ),
                    ),

                    const Spacer(),
                    EspStatusBadge(status: bleToEspStatus(BleService())),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              Expanded(
                child: _buildGuideContent(surface, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideContent(Color surface, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        children: [
          // ── 1. What is SmartLocator ──
          _sectionCard(
            icon: '📦',
            iconColor: const Color(0xFFE6F1FB),
            title: 'What is SmartLocator?',
            isDark: isDark,
            surface: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bodyText(
                  'A BLE indoor PERSONAL item tracker used in hostels, working with the mobile app for real-time item location and to take good care of tracked items.',
                  isDark,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip('BLE Signal', const Color(0xFFE6F1FB), const Color(0xFF185FA5)),
                    _chip('Floor Detection', const Color(0xFFE6F1FB), const Color(0xFF185FA5)),
                    _chip('Buzzer Alert', const Color(0xFFFAEEDA), const Color(0xFF854F0B)),
                    _chip('LED Indicator', const Color(0xFFFAEEDA), const Color(0xFF854F0B)),
                    _chip('Firebase Cloud', const Color(0xFFEAF3DE), const Color(0xFF3B6D11)),
                  ],
                ),
              ],
            ),
          ),

          // ── 2. ESP32 Connection Status ──
          _sectionCard(
            icon: '📡',
            iconColor: const Color(0xFFE6F1FB),
            title: 'ESP32 Connection Status',
            isDark: isDark,
            surface: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bodyText('The status indicator shows whether your SmartLocator is online and functioning. Always check this before tracking.', isDark),
                const SizedBox(height: 12),
                _statusRow(
                  color: const Color(0xFF00C897),
                  label: 'Online (Connected)',
                  desc: 'SmartLocator is online and functioning well.',
                  effect: '✅ Full tracking available — proximity, buzzer, floor detection all active.',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _statusRow(
                  color: const Color(0xFFFFB020),
                  label: 'Connecting',
                  desc: 'BLE scan in progress — SmartLocator not yet found.',
                  effect: '⏳ Wait a moment. Make sure hardware switch is ON and you are within 10m range.',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _statusRow(
                  color: const Color(0xFFFF4E6A),
                  label: 'Offline (Disconnected)',
                  desc: 'No BLE connection detected.',
                  effect: '❌ Tracking unavailable. Last-seen data only.',
                  isDark: isDark,
                  causes: [
                    'Phone Bluetooth is turned OFF',
                    'SmartLocator is out of range (>10m)',
                    'Hardware switch is OFF',
                    'ESP32 may be damaged or broken',
                  ],
                ),
              ],
            ),
          ),

          // ── 3. Two Types of Switches ──
          _sectionCard(
            icon: '⚡',
            iconColor: const Color(0xFFFAEEDA),
            title: 'Two Types of Switches',
            isDark: isDark,
            surface: surface,
            child: Row(
              children: [
                Expanded(
                  child: _switchCard(
                    title: 'Hardware Switch',
                    subtitle: 'Physically powers ESP32. OFF = zero drain.',
                    tag: 'Best for saving battery!',
                    tagBg: const Color(0xFFEAF3DE),
                    tagTxt: const Color(0xFF3B6D11),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _switchCard(
                    title: 'App Switch',
                    subtitle: 'Pauses tracking only. ESP32 still ON and draining battery.',
                    tag: 'Temporary only',
                    tagBg: const Color(0xFFFAEEDA),
                    tagTxt: const Color(0xFF854F0B),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          // ── 4. Correct Usage Guide ──
          _sectionCard(
            icon: '✅',
            iconColor: const Color(0xFFEAF3DE),
            title: 'Correct Usage Guide',
            isDark: isDark,
            surface: surface,
            child: Column(
              children: [
                _usageRow('Daily Use',
                    'Turn ON Switch → Find Device → Connect → Track', '🟢', isDark),
                const SizedBox(height: 8),
                _usageRow('Temporary Pause',
                    'App Switch OFF — ESP32 still drawing power', '🟡', isDark),
                const SizedBox(height: 8),
                _usageRow('End of Day',
                    'Hardware Switch OFF — ESP32 completely off', '🔴', isDark),
              ],
            ),
          ),

          // ── 5. Bluetooth Proximity Tracking ──
          _sectionCard(
            icon: '📶',
            iconColor: const Color(0xFFE6F1FB),
            title: 'Bluetooth Proximity Tracking',
            isDark: isDark,
            surface: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bodyText(
                  'The Device Tracking page uses BLE signal strength (RSSI) to estimate how close you are to your SmartLocator. Yellow alert waves and buzzer intensity change based on proximity.',
                  isDark,
                ),
                const SizedBox(height: 12),
                _proximityRow(
                  emoji: '🟢',
                  zone: 'CLOSED BY',
                  btTitle: 'Connected — Closed By',
                  btDesc: 'Your SmartLocator is RIGHT BESIDE you! Signal is very strong.',
                  trackingMsg: 'Your item is RIGHT BESIDE you!',
                  beep: 1, vol: 25,
                  waves: 'Minimal alert waves',
                  isDark: isDark,
                ),
                _proximityRow(
                  emoji: '🟢',
                  zone: 'NEARBY',
                  btTitle: 'Connected — Nearby',
                  btDesc: 'Your SmartLocator is nearby. Signal is strong.',
                  trackingMsg: 'Your item is nearby. You are close!',
                  beep: 1, vol: 25,
                  waves: 'Minimal alert waves',
                  isDark: isDark,
                ),
                _proximityRow(
                  emoji: '🟠',
                  zone: 'FAR',
                  btTitle: 'Connected — Far',
                  btDesc: 'Your SmartLocator signal is getting weaker. Move closer.',
                  trackingMsg: 'Moving away — your item is getting far.',
                  beep: 2, vol: 50,
                  waves: 'Moderate alert waves',
                  isDark: isDark,
                ),
                _proximityRow(
                  emoji: '🔴',
                  zone: 'TOO FAR',
                  btTitle: 'Connected — Too Far',
                  btDesc: 'Signal is very weak. Your item may be out of range soon.',
                  trackingMsg: 'Very far! Move closer to your item.',
                  beep: 3, vol: 75,
                  waves: 'Strong alert waves',
                  isDark: isDark,
                ),
                _proximityRow(
                  emoji: '⚫',
                  zone: 'SIGNAL LOST',
                  btTitle: 'Signal Lost',
                  btDesc: 'No signal detected. Move closer to your SmartLocator.',
                  trackingMsg: 'Out of detection range. Move closer.',
                  beep: 3, vol: 75,
                  waves: 'Maximum alert waves',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _infoBox(
                  '💡 Swipe left/right to switch between Device Tracking (alert waves) and BT Signal (bluetooth wave rings) pages. Both update in real-time.\n\n🎚️ You can also adjust the beep count and volume level flexibly using the sliders on the Device Tracking page to suit your preference!',
                  const Color(0xFFE6F1FB),
                  const Color(0xFF185FA5),
                  isDark,
                ),
              ],
            ),
          ),

          // ── 6. BT Signal Page ──
          _sectionCard(
            icon: '🔵',
            iconColor: const Color(0xFFE6F1FB),
            title: 'BT Signal Page — Wave Rings',
            isDark: isDark,
            surface: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bodyText('The BT Signal page shows bluetooth connection quality through animated wave rings. More filled rings = stronger signal.', isDark),
                const SizedBox(height: 10),
                // ── Connected states ──
                _btWaveDemo(filled: 4, label: 'CLOSED BY', sublabel: 'Maximum signal', color: const Color(0xFF5C6BC0), isDisc: false, isDark: isDark),
                _btWaveDemo(filled: 3, label: 'NEARBY', sublabel: 'Strong signal', color: const Color(0xFF5C6BC0), isDisc: false, isDark: isDark),
                _btWaveDemo(filled: 2, label: 'FAR', sublabel: 'Weakening signal', color: const Color(0xFF5C6BC0), isDisc: false, isDark: isDark),
                _btWaveDemo(filled: 1, label: 'TOO FAR', sublabel: 'Very weak', color: const Color(0xFF5C6BC0), isDisc: false, isDark: isDark),
                _btWaveDemo(filled: 0, label: 'SIGNAL LOST', sublabel: 'Out of range', color: const Color(0xFF5C6BC0), isDisc: false, isDark: isDark),
                _btWaveDemo(filled: 0, label: 'DISCONNECTED', sublabel: 'No BLE connection', color: const Color(0xFF888888), isDisc: true, isDark: isDark),
                const SizedBox(height: 10),
                _infoBox(
                  '📌 Status cards appear at the top of BT Signal page:\n• "Reconnection! Signal Found!" — when reconnected\n• "Disconnection!" — SmartLocator disconnected\n• Zone cards (Closed By / Nearby / Far / Too Far) appear 3s after reconnect.',
                  const Color(0xFFE6F1FB),
                  const Color(0xFF185FA5),
                  isDark,
                ),
              ],
            ),
          ),

          // ── 7. App Switch OFF behaviour ──
          _sectionCard(
            icon: '⏸️',
            iconColor: const Color(0xFFFAEEDA),
            title: 'App Switch OFF — What Happens?',
            isDark: isDark,
            surface: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bodyText('When you turn OFF the App Switch (not the hardware switch), SmartLocator enters a paused state:', isDark),
                const SizedBox(height: 10),
                _checkRow('✅', 'ESP32 remains powered ON', isDark),
                _checkRow('✅', 'BLE stays connected', isDark),
                _checkRow('✅', 'Last-seen data is saved to Firebase', isDark),
                _checkRow('⏸️', 'Real-time tracking data is frozen', isDark),
                _checkRow('⏸️', 'No proximity notifications or buzzer changes', isDark),
                _checkRow('⏸️', 'Alert waves and BT rings stop updating', isDark),
                _checkRow('❌', 'Battery still draining — use Hardware Switch to save battery', isDark),
              ],
            ),
          ),

          // ── 8. Battery Life ──
          _sectionCard(
            icon: '🔋',
            iconColor: const Color(0xFFEAF3DE),
            title: 'Battery Life Expectation',
            isDark: isDark,
            surface: surface,
            child: Column(
              children: [
                _batteryRow('New battery', 1.0, '~6-7 hours',
                    const Color(0xFF3B6D11), isDark),
                _batteryRow('After 1 year', 0.8, '~5 hours',
                    const Color(0xFF3B6D11), isDark),
                _batteryRow('After 2 years', 0.6, '~4 hours',
                    const Color(0xFFBA7517), isDark),
                _batteryRow('After 3 years', 0.4, '~2.7 hours',
                    const Color(0xFFA32D2D), isDark),
              ],
            ),
          ),

          // ── 8b. Battery Management System Explanation ──
          _sectionCard(
            icon: '🛡️',
            iconColor: const Color(0xFFFCEBEB),
            title: 'Why Does Warning Appear Before Battery Dies?',
            isDark: isDark,
            surface: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Intro ──
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A3A5C) : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡 ', style: TextStyle(fontSize: 14)),
                      Expanded(child: Text(
                        'SmartLocator uses a conservative safety timer — warnings appear before the battery physically runs out. This is intentional design, not a bug.',
                        style: TextStyle(
                          fontSize: 12, height: 1.5, fontStyle: FontStyle.italic,
                          color: isDark ? Colors.lightBlueAccent : const Color(0xFF1565C0),
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Actual vs Physical ──
                Text('⚡ Physical vs Recommended Usage',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _batteryCompareRow('Physical capacity', '~6–7 hrs', const Color(0xFF4CAF50), isDark),
                _batteryCompareRow('Recommended per charge', '~4 hrs max', const Color(0xFFFF9800), isDark),
                _batteryCompareRow('Warning trigger point', 'Before depletion', const Color(0xFFE91E63), isDark),
                const SizedBox(height: 12),

                // ── Why ──
                Text('🔋 Why SmartLocator Does This',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _protectionRow('⚠️', 'Over-discharge kills batteries permanently', isDark),
                _protectionRow('📉', 'Lithium batteries degrade faster near 0%', isDark),
                _protectionRow('🔒', 'Feature locking prevents unsafe shutdown', isDark),
                _protectionRow('🕐', 'Conservative timer = longer battery lifespan', isDark),
                const SizedBox(height: 12),

                // ── 5-layer system ──
                Text('🛡️ 5-Layer Battery Protection System',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _layerRow('1', '🟢', 'Progressive notifications', '80% → 60% → 40% → 20%', isDark),
                _layerRow('2', '🔴', 'Hardware red LED', 'Lights ON below 20%', isDark),
                _layerRow('3', '📱', 'App charge button', 'Appears at 80% as reminder', isDark),
                _layerRow('4', '⏱️', 'Countdown timer', '60s warning at <2%', isDark),
                _layerRow('5', '🔒', 'Feature lock', 'Enforces charging at depletion', isDark),
                const SizedBox(height: 12),

                // ── Conclusion box ──
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF253520) : const Color(0xFFEAF3DE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? const Color(0xFF4CAF50).withOpacity(0.4) : const Color(0xFF3B6D11).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✅ ', style: TextStyle(fontSize: 14)),
                      Expanded(child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 11, height: 1.5,
                            color: isDark ? const Color(0xFF81C784) : const Color(0xFF3B6D11),
                          ),
                          children: const [
                            TextSpan(text: 'Bottom line: ', style: TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: 'Warnings appearing '),
                            TextSpan(text: 'before', style: TextStyle(fontStyle: FontStyle.italic, decoration: TextDecoration.underline)),
                            TextSpan(text: ' battery dies = SmartLocator '),
                            TextSpan(text: 'protecting your battery', style: TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: ', not malfunctioning. Charge when prompted for best longevity! 🔋'),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 9. Full Recharging Procedure ──
          _sectionCard(
            icon: '🔌',
            iconColor: const Color(0xFFE6F1FB),
            title: 'Full Recharging Procedure',
            isDark: isDark,
            surface: surface,
            child: Column(
              children: [
                _stepRow(1, 'Turn OFF Hardware Switch', isDark),
                _stepRow(2, 'Open casing lid for ventilation', isDark),
                _stepRow(3, 'Connect USB-C to boost module charging port', isDark),
                _stepRow(4, 'Connect to power source (powerbank)', isDark),
                _stepRow(5, 'Wait for BLUE LIGHT appears = Fully charged ✅', isDark),
                _stepRow(6, 'Disconnect USB-C cable', isDark),
                _stepRow(7, 'Close casing lid', isDark),
                _stepRow(8, 'Turn ON Hardware Switch', isDark),
                _stepRow(9, 'Open app → reconnect via Find Device + Track again', isDark),
                const SizedBox(height: 10),
                _warningBox(
                  '⚠️ Must wait for Blue Light before turning ON switch. Charging with switch OFF is completely safe.',
                  isDark,
                ),
              ],
            ),
          ),

          // ── 10. Battery Warning Levels ──
          _sectionCard(
            icon: '🔋',
            iconColor: const Color(0xFFFCEBEB),
            title: 'Battery Warning Levels',
            isDark: isDark,
            surface: surface,
            child: Column(
              children: [
                _batteryLevel('GOOD 80–100%', '🟢', 'No action needed', isDark),
                _batteryLevel('GOOD 61–80%', '🟢', 'Consider charging soon or Ignore', isDark),
                _batteryLevel('NORMAL 41–60%', '🟡', 'Plan to charge', isDark),
                _batteryLevel('LOW 21–40%', '🟠', 'Charge ASAP + Red LED ON', isDark),
                _batteryLevel('CRITICAL ≤20%', '🔴', 'Charge immediately!', isDark),
                _batteryLevel('DEPLETED ≤2%', '🚨', '60s countdown + Features locked', isDark),
              ],
            ),
          ),

          // ── 11. FAQ ──
          _sectionCard(
            icon: '❓',
            iconColor: const Color(0xFFFAEEDA),
            title: 'FAQ — 10 Questions',
            isDark: isDark,
            surface: surface,
            child: Column(
              children: [
                _faqItem('Q1', 'App cannot find SmartLocator?',
                    'Check BLE ON → Switch ON (Green light) → Stay within 10m (BLE range) → Refresh device connection page → If still no: recharge battery (battery aging problem).', isDark),
                _faqItem('Q2', 'Sudden disconnection?',
                    'Make sure the Bluetooth connection, hardware switch, green LED bulb is turned ON and refresh the page again.', isDark),
                _faqItem('Q3', 'App Switch OFF but battery still draining?',
                    'App Switch only pauses tracking. ESP32 still draws ~250mA. Use Hardware Switch OFF to cut off power completely.', isDark),
                _faqItem('Q4', 'Battery dropped quickly after full charge?',
                    'Normal battery aging. After 3 years, capacity drops to ~40%. Consider buying a new 18650 battery to replace.', isDark),
                _faqItem('Q5', 'Countdown appeared but battery seems OK?',
                    'Intentional Safety Margin design. Timer is set shorter than actual battery life to guarantee early warning and protect battery.', isDark),
                _faqItem('Q6', 'Disconnects often even at GOOD battery?',
                    'Normal battery aging. Actual voltage drops before timer detects it. Recharge fully; if persists → replace battery.', isDark),
                _faqItemQ7(isDark),
                _faqItem('Q8', 'Features are locked?',
                    'Please tap "OK I\'ll charge now" → follow the recharging procedure → features unlock after full recharge.', isDark),
                _faqItem('Q9', 'Safe to charge with wires connected?',
                    'Yes! Switch OFF = no current flows to the SmartLocator. TP4056 chip provides overcharge protection (auto-stop at 4.2V). Make sure no lights are ON when recharging.', isDark),
                _faqItem('Q10', 'Red LED is ON?',
                    'Indicates battery is below 20%. Open app → tap Charge button → follow recharging procedure. Red LED turns OFF automatically after hardware switch reset post-charging.', isDark),
              ],
            ),
          ),

          // ── 12. Quick Reference ──
          _sectionCard(
            icon: '⚡',
            iconColor: const Color(0xFFEEEDFE),
            title: 'Quick Reference',
            isDark: isDark,
            surface: surface,
            child: Column(
              children: [
                _quickRef('Cannot connect', 'Check switch ON → check BLE → recharge', isDark),
                _quickRef('Sudden disconnect', 'Move closer → if still off: recharge', isDark),
                _quickRef('Battery LOW / Red LED', 'Recharge now!', isDark),
                _quickRef('Countdown appeared', 'Recharge immediately!', isDark),
                _quickRef('Features locked', 'Must recharge UNTIL FULL to unlock', isDark),
                _quickRef('Frequent drops / short runtime', 'Consider a new 18650 battery', isDark),
                _quickRef('Status shows Disconnected', 'Check BLE, switch, range, or ESP32 health', isDark),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Text(
            'BluePixels Team\nBuilt with Flutter & Firebase ❤️',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _batteryCompareRow(String label, String value, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(
            fontSize: 11, color: isDark ? Colors.white70 : Colors.black54,
          ))),
          Text(value, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color,
          )),
        ],
      ),
    );
  }

  Widget _protectionRow(String emoji, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji ', style: const TextStyle(fontSize: 12)),
          Expanded(child: Text(text, style: TextStyle(
            fontSize: 11, height: 1.4,
            color: isDark ? Colors.white60 : Colors.black54,
            fontStyle: FontStyle.italic,
          ))),
        ],
      ),
    );
  }

  Widget _layerRow(String num, String emoji, String title, String desc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A), shape: BoxShape.circle),
            child: Center(child: Text(num, style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700,
            ))),
          ),
          const SizedBox(width: 8),
          Text('$emoji ', style: const TextStyle(fontSize: 12)),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              )),
              Text(desc, style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.black45,
                fontStyle: FontStyle.italic,
              )),
            ],
          )),
        ],
      ),
    );
  }

  // ── Status row for ESP32 section ──────────────────────────────────────────
  Widget _statusRow({
    required Color color,
    required String label,
    required String desc,
    required String effect,
    required bool isDark,
    List<String>? causes,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)],
                ),
              ),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: color,
              )),
            ],
          ),
          const SizedBox(height: 6),
          Text(desc, style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black54,
            height: 1.4,
          )),
          if (causes != null) ...[
            const SizedBox(height: 6),
            Text('Possible causes:', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black45,
            )),
            const SizedBox(height: 4),
            ...causes.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(fontSize: 11, color: color)),
                  Expanded(child: Text(c, style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ))),
                ],
              ),
            )),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(effect, style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            )),
          ),
        ],
      ),
    );
  }

  // ── Proximity row ─────────────────────────────────────────────────────────
  Widget _proximityRow({
    required String emoji,
    required String zone,
    required String btTitle,
    required String btDesc,
    required String trackingMsg,
    required int beep,
    required int vol,
    required String waves,
    required bool isDark,
  }) {
    Color zoneColor;
    switch (zone) {
      case 'CLOSED BY': zoneColor = const Color(0xFF00C853); break;
      case 'NEARBY':    zoneColor = const Color(0xFF00C853); break;
      case 'FAR':       zoneColor = const Color(0xFFFF9800); break;
      case 'TOO FAR':   zoneColor = const Color(0xFFE91E63); break;
      default:          zoneColor = const Color(0xFFE53935);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF253545) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: zoneColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zone label
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(zone, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: zoneColor,
              )),
              const Spacer(),
              _miniChip('Beep $beep', const Color(0xFFE6F1FB), const Color(0xFF185FA5)),
              const SizedBox(width: 4),
              _miniChip('Vol $vol%', const Color(0xFFEAF3DE), const Color(0xFF3B6D11)),
            ],
          ),
          const SizedBox(height: 6),
          // Tracking page popup
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📍 ', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
              Expanded(child: Text(
                '"$trackingMsg"',
                style: TextStyle(
                  fontSize: 11, fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              )),
            ],
          ),
          const SizedBox(height: 4),
          // BT page card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📶 ', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
              Expanded(child: Text(
                '$btTitle — $btDesc',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              )),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('🌊 Alert: ', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black45,
              )),
              _alertWavesMini(waveCount: _zoneToWaveCount(zone), isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, Color bg, Color txt) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Text(label, style: TextStyle(fontSize: 10, color: txt, fontWeight: FontWeight.w600)),
  );

  Widget _btWaveRow(String rings, String meaning, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(rings, style: TextStyle(
              fontSize: 11, fontFamily: 'monospace',
              color: isDark ? Colors.white70 : Colors.black87,
            )),
          ),
          Expanded(child: Text(meaning, style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black45,
          ))),
        ],
      ),
    );
  }

  Widget _btWaveDemo({
  required int filled,
  required String label,
  required String sublabel,
  required Color color,
  required bool isDisc,
  required bool isDark,
}) {
  final radii = [52.0, 40.0, 28.0, 18.0]; // outermost to innermost

  Color dotColor(int ringIndex) {
    if (isDisc) return Colors.grey.shade500;
    return ringIndex < filled ? color : (isDark ? const Color(0xFF3A4A5C) : const Color(0xFFD0D8E8));
  }

  double dotOpacity(int ringIndex) {
    if (isDisc) return 0.3;
    if (ringIndex < filled) return 0.15 + (ringIndex * 0.05);
    return 0.08;
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        // ── Mini wave rings visual ──
        SizedBox(
          width: 120, height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 4 rings from outer to inner
              for (int i = 0; i < 4; i++)
                Container(
                  width: radii[i] * 2,
                  height: radii[i] * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDisc
                        ? Colors.transparent  // ✅ DISCONNECTED = no fill, just outline
                        : dotColor(3 - i).withOpacity(dotOpacity(3 - i)),
                    border: Border.all(
                      color: isDisc
                          ? (isDark ? Colors.white12 : Colors.black12) // ✅ 细灰线
                          : dotColor(3 - i).withOpacity(3 - i < filled ? 0.5 : 0.2),
                      width: isDisc ? 1.0 : 1.5,
                    ),
                  ),
                ),
              // Center BT icon
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDisc
                      ? Colors.grey.shade600
                      : (isDark ? const Color(0xFF5B8DD9) : const Color(0xFF3F51B5)),
                  boxShadow: [
                    BoxShadow(
                      color: (isDisc ? Colors.grey : const Color(0xFF3F51B5)).withOpacity(0.3),
                      blurRadius: 6, spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  isDisc ? Icons.bluetooth_disabled : Icons.bluetooth,
                  color: Colors.white, size: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ── Label ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: isDisc
                    ? Colors.grey
                    : (isDark ? Colors.white : const Color(0xFF3F51B5)),
              )),
              const SizedBox(height: 2),
              Text(sublabel, style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              )),
            ],
          ),
        ),
      ],
    ),
  );
}


    int _zoneToWaveCount(String zone) {
  switch (zone) {
    case 'CLOSED BY': return 0;
    case 'NEARBY':    return 1;
    case 'FAR':       return 2;
    case 'TOO FAR':   return 3;
    default:          return 4; // SIGNAL LOST
  }
}

Widget _alertWavesMini({required int waveCount, required bool isDark}) {
  // Mini inline version of the amber alert waves
  const double baseSize = 16.0;
  const double step = 8.0;
  final totalSize = baseSize + (waveCount * step);

  return SizedBox(
    width: 80, height: 40,
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (int i = waveCount - 1; i >= 0; i--)
          Container(
            width: baseSize + ((waveCount - i) * step),
            height: baseSize + ((waveCount - i) * step),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFA000).withOpacity(
                (0.35 - (i * 0.07)).clamp(0.05, 0.35),
              ),
            ),
          ),
        Container(
          width: baseSize, height: baseSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFFA000),
          ),
          child: const Icon(Icons.alarm, color: Colors.white, size: 10),
        ),
      ],
    ),
  );
}

  Widget _checkRow(String icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$icon ', style: const TextStyle(fontSize: 13)),
          Expanded(child: Text(text, style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black54,
            height: 1.4,
          ))),
        ],
      ),
    );
  }

  Widget _infoBox(String text, Color bg, Color txt, bool isDark) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1E3A5F) : bg.withOpacity(0.5), // ✅ dark mode 用明亮蓝
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isDark ? const Color(0xFF4A90D9).withOpacity(0.5) : txt.withOpacity(0.2),
      ),
    ),
    child: Text(text, style: TextStyle(
      fontSize: 11,
      color: isDark ? const Color(0xFF90CAF9) : txt, // ✅ dark mode 用浅蓝色文字
      height: 1.5,
    )),
  );
}

  // ── Existing helpers (unchanged) ──────────────────────────────────────────
  Widget _sectionCard({
    required String icon,
    required Color iconColor,
    required String title,
    required Widget child,
    required bool isDark,
    required Color surface,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2A3A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              Expanded(                          // ✅ 加这行
                child: Text(title, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                )),
              ),                                 // ✅ 加这行
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _bodyText(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: isDark ? Colors.white60 : Colors.black54,
      height: 1.6,
    ),
  );

  Widget _chip(String label, Color bg, Color txt) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 11, color: txt)),
  );

  Widget _switchCard({
    required String title,
    required String subtitle,
    required String tag,
    required Color tagBg,
    required Color tagTxt,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF253545) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          )),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black45,
            height: 1.5,
          )),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(20)),
            child: Text(tag, style: TextStyle(fontSize: 10, color: tagTxt)),
          ),
        ],
      ),
    );
  }

  Widget _usageRow(String label, String desc, String emoji, bool isDark) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              )),
              Text(desc, style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _batteryRow(String label, double pct, String value, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            )),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(value, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500,
              color: color,
            )),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(int num, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text('$num', style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
            ))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black.withOpacity(0.7),
            height: 1.5,
          ))),
        ],
      ),
    );
  }

  Widget _warningBox(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAEEDA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(
        fontSize: 11, color: Color(0xFF854F0B), height: 1.5,
      )),
    );
  }

  Widget _batteryLevel(String level, String emoji, String desc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                )),
                Text(desc, style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faqItem(String qNum, String question, String answer, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF253545) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(qNum, style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600,
                )),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(question, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ))),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A3A5C).withOpacity(0.5)
                  : const Color(0xFFE3F2FD).withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(
                color: isDark
                    ? Colors.lightBlueAccent.withOpacity(0.4)
                    : const Color(0xFF1565C0).withOpacity(0.4),
                width: 3,
              )),
            ),
            child: Text(answer, style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black54,
              fontStyle: FontStyle.italic,
              decoration: TextDecoration.underline,
              decorationColor: isDark ? Colors.white30 : Colors.black26,
              height: 1.5,
            )),
          ),
        ],
      ),
    );
  }

  Widget _faqItemQ7(bool isDark) {
    final points = [
      'Green light flickering and dimming',
      'Buzzer did not produce sound and beep',
      'Pressure calibration always fails (stuck at 0 level)',
      'Reset the app and hardware switch did not work',
      'Cannot connect with Bluetooth',
      'Device tracking page shows Signal Lost',
      'Bluetooth tracking page shows Disconnection',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF253545) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Q7', style: TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600,
                )),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('When to replace the battery?', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Even after fully recharging, replace the battery if you notice:',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          ...points.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${e.key + 1}. ', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white60 : const Color(0xFF1565C0),
                )),
                Expanded(child: Text(e.value, style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.underline,
                  decorationColor: isDark ? Colors.white38 : Colors.black26,
                  height: 1.4,
                ))),
              ],
            ),
          )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A3A5C) : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text('💡 ', style: TextStyle(fontSize: 12)),
                Expanded(child: Text(
                  'Buy a new 18650 2000mAh 3.7V battery to replace.',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.lightBlueAccent : const Color(0xFF1565C0),
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickRef(String situation, String action, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('→ ', style: TextStyle(
            color: Color(0xFF5C6BC0), fontWeight: FontWeight.w600,
          )),
          Expanded(child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$situation  ',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                TextSpan(
                  text: action,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          )),
        ],
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