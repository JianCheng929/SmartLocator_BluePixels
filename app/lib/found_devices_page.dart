import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'connecting_device_page.dart';
import 'services/ble_service.dart';
import 'esp_status_badge.dart';

class FoundDevicesPage extends StatefulWidget {
  const FoundDevicesPage({super.key});

  @override
  State<FoundDevicesPage> createState() => _FoundDevicesPageState();
}

class _FoundDevicesPageState extends State<FoundDevicesPage> {
  final _ble = BleService();

  @override
  void initState() {
    super.initState();
    _ble.startScan(timeoutSec: 15);
  }

  @override
  void dispose() {
    _ble.stopScan();
    super.dispose();
  }

  String _friendlyName(ScanResult r) {
    final n = r.device.platformName;
    return n.isNotEmpty ? n : r.device.remoteId.toString();
  }

  String _deviceType(ScanResult r) {
    final n = r.device.platformName.toLowerCase();
    if (n.contains('smartlocator') || n.contains('smart locator')) {
      return 'Smart Locator';
    }
    if (n.contains('tag')) return 'Smart Tag';
    if (n.contains('laptop') || n.contains('pc') || n.contains('computer')) {
      return 'Computer';
    }
    return 'BLE Device';
  }

  bool _isSmartLocator(ScanResult r) {
    final n = r.device.platformName.toLowerCase();
    return n.contains('smartlocator') || n.contains('smart locator');
  }

  Future<void> _connectTo(ScanResult r) async {
    await _ble.stopScan();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConnectingDevicePage(
        device: r.device,
        deviceName: _friendlyName(r),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ble,
      builder: (_, __) {
        final results = _ble.scanResults;
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: Theme.of(context).brightness == Brightness.dark
                  ? const [
                      Color(0xFF0D1B2A),
                      Color(0xFF0F2540),
                      Color(0xFF1A3A5C),
                      Color(0xFF1E4976),
                    ]
                  : const [
                      Colors.white,
                      Color(0xFFE3F2FD),
                      Color(0xFFBBDEFB),
                      Color(0xFF90CAF9),
                    ],
                stops: [0.0, 0.3, 0.6, 1.0],
              ),
            ),
            child: SafeArea(
              child: Stack(
              children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: const Icon(Icons.arrow_back,
                                color: Color(0xFF1565C0), size: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Find devices',
                          style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white : const Color(0xFF1565C0))),
                        const Spacer(),
                        ListenableBuilder(
                          listenable: _ble,
                          builder: (_, __) => EspStatusBadge(status: bleToEspStatus(_ble)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Found count + scanning
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Text('Found devices (${results.length})',
                          style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white70 : Colors.grey[600],
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 10),
                        if (_ble.isScanning) ...[
                          SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue.shade400),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('Scanning...',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade400)),
                        ],
                      ],
                    ),
                  ),

                  if (_ble.isScanning)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 6),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.blue.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue.shade400),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Device list — Expanded handles overflow correctly
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        await _ble.stopScan();
                        await Future.delayed(
                            const Duration(milliseconds: 300));
                        await _ble.startScan(timeoutSec: 15);
                      },
                      child: results.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 60),
                              Center(
                                child: Column(children: [
                                  Icon(Icons.bluetooth_searching,
                                      size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    _ble.isScanning
                                        ? 'Scanning for devices...'
                                        : 'No devices found.\nPull down to scan again.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 14),
                                  ),
                                ]),
                              ),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24),
                              itemCount: results.length,
                              itemBuilder: (_, i) =>
                                  _buildDeviceItem(results[i]),
                            ),
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceItem(ScanResult r) {
    final name      = _friendlyName(r);
    final type      = _deviceType(r);
    final isSL      = _isSmartLocator(r);
    final itemColor = isSL ? const Color(0xFF1976D2) : const Color(0xFF5A7A9C);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? (isSL ? const Color(0xFF1A3A5C) : const Color(0xFF1A2F4A))
        : (isSL ? const Color(0xFFE3F2FD) : Colors.white);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: isSL
            ? Border.all(color: const Color(0xFF90CAF9), width: 1.5)
            : null,
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10, spreadRadius: 2, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: itemColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bluetooth, color: itemColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isSL
                          ? (isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0))
                          : (isDark ? Colors.white : const Color(0xFF334155)))),
                const SizedBox(height: 4),
                Text(type,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                if (isSL) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('✓ SmartLocator detected',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.w500)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('⚠ Make sure hardware switch is ON',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade700)),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _connectTo(r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSL
                    ? const Color(0xFF1976D2)
                    : const Color(0xFF5A9BD4),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                    color: const Color(0xFF1976D2).withOpacity(0.3),
                    blurRadius: 8, spreadRadius: 1,
                    offset: const Offset(0, 3))],
              ),
              child: const Text('Connect',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ),
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
