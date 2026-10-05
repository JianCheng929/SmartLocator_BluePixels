import 'package:flutter/material.dart';
import 'found_devices_page.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_background.dart';
import 'esp_status_badge.dart';
import 'services/ble_service.dart';

class DeviceConnectionPage extends StatefulWidget {
  const DeviceConnectionPage({super.key});

  @override
  State<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends State<DeviceConnectionPage>
    with TickerProviderStateMixin {
  bool _isConnecting = false;
  bool _isConnected  = false;

  late AnimationController _waveAnimationController;
  late Animation<double>   _waveAnimation;

  @override
  void initState() {
    super.initState();
    _waveAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _waveAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _waveAnimationController.dispose();
    super.dispose();
  }

  Future<void> _startConnection() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (await FlutterBluePlus.adapterState.first !=
        BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw Exception('Bluetooth did not turn on');
      });
    }

    setState(() => _isConnecting = true);
    _waveAnimationController.repeat();

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isConnected  = true;
        _isConnecting = false;
      });
      _waveAnimationController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          // ── SingleChildScrollView prevents overflow in landscape ──────────
          child: Stack(
          children: [
            SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height
                    - MediaQuery.of(context).padding.top
                    - MediaQuery.of(context).padding.bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
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
                          const Spacer(),
                          ListenableBuilder(
                            listenable: BleService(),
                            builder: (_, __) => EspStatusBadge(status: bleToEspStatus(BleService())),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Connection icon
                    _isConnecting || _isConnected
                        ? _buildAnimatedConnectionIcon()
                        : _buildInactiveConnectionIcon(),

                    const SizedBox(height: 60),

                    // Button
                    _isConnected
                        ? _buildConnectedButton()
                        : _isConnecting
                            ? _buildConnectingButton()
                            : const SizedBox(height: 56),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildInactiveConnectionIcon() {
    return GestureDetector(
      onTap: _startConnection,
      child: SizedBox(
        width: 200, height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.grey[200]),
            ),
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.grey.withOpacity(0.3),
                      blurRadius: 10, spreadRadius: 2)
                ],
              ),
              child: Icon(Icons.link, size: 50, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedConnectionIcon() {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 200, height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 180 + (_waveAnimation.value * 20),
                height: 180 + (_waveAnimation.value * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF90CAF9).withOpacity(
                      _isConnected
                          ? 0.3
                          : (0.3 - _waveAnimation.value * 0.1)),
                ),
              ),
              Container(
                width: 140 + (_waveAnimation.value * 15),
                height: 140 + (_waveAnimation.value * 15),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF42A5F5).withOpacity(
                      _isConnected
                          ? 0.5
                          : (0.5 - _waveAnimation.value * 0.1)),
                ),
              ),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected
                      ? const Color(0xFF1976D2)
                      : const Color(0xFF42A5F5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1976D2).withOpacity(0.5),
                      blurRadius: 20, spreadRadius: 5,
                    )
                  ],
                ),
                child: const Icon(Icons.link, size: 50, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectingButton() {
    return Container(
      width: 280, height: 56,
      decoration: BoxDecoration(
          color: Colors.grey[300], borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
              ),
            ),
            const SizedBox(width: 12),
            Text('Finding device...',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const FoundDevicesPage()),
      ),
      child: Container(
        width: 280, height: 56,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 80, 152, 224),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(255, 80, 152, 224).withOpacity(0.3),
              blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 8),
            )
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Device Found',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: Colors.white, size: 20),
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