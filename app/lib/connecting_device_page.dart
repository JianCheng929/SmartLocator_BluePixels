import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:smartlocator_bluepixels/app_background.dart';
import 'services/ble_service.dart';
import 'item_information_page.dart';
import 'esp_status_badge.dart';

class ConnectingDevicePage extends StatefulWidget {
  final BluetoothDevice device;
  final String          deviceName;

  const ConnectingDevicePage({
    super.key,
    required this.device,
    required this.deviceName,
  });

  @override
  State<ConnectingDevicePage> createState() => _ConnectingDevicePageState();
}

class _ConnectingDevicePageState extends State<ConnectingDevicePage>
    with TickerProviderStateMixin {
  bool _isConnected = false;
  bool _hasFailed   = false;

  late AnimationController _waveAnimationController;
  late Animation<double>   _waveAnimation;
  late AnimationController _loadingAnimationController;

  final _ble = BleService();

  @override
  void initState() {
    super.initState();
    _waveAnimationController = AnimationController(
      duration: const Duration(seconds: 2), vsync: this,
    )..repeat();
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _waveAnimationController, curve: Curves.easeInOut),
    );
    _loadingAnimationController = AnimationController(
      duration: const Duration(seconds: 1), vsync: this,
    )..repeat();
    _doConnect();
  }

  Future<void> _doConnect() async {
    final bool ok = await _ble.connect(widget.device);
    if (!mounted) return;
    if (ok) {
      setState(() => _isConnected = true);
      _waveAnimationController.stop();
      _loadingAnimationController.stop();
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ItemInformationPage()),
        );
      }
    } else {
      setState(() => _hasFailed = true);
      _waveAnimationController.stop();
      _loadingAnimationController.stop();
    }
  }

  @override
  void dispose() {
    _waveAnimationController.dispose();
    _loadingAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          // ── Overflow fix ────────────────────────────────────────────────
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
                            listenable: _ble,
                            builder: (_, __) => EspStatusBadge(status: bleToEspStatus(_ble)),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),
                    _buildAnimatedConnectionIcon(),
                    const SizedBox(height: 60),

                    _hasFailed
                        ? _buildFailedIndicator()
                        : _isConnected
                            ? _buildConnectedText()
                            : _buildConnectingIndicator(),

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
                  color: _hasFailed
                      ? Colors.red.shade400
                      : _isConnected
                          ? const Color(0xFF1976D2)
                          : const Color(0xFF42A5F5),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF1976D2).withOpacity(0.5),
                      blurRadius: 20, spreadRadius: 5)],
                ),
                child: Icon(
                  _hasFailed ? Icons.link_off : Icons.link,
                  size: 50, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectingIndicator() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _loadingAnimationController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _loadingAnimationController.value * 2 * 3.14159,
              child: SizedBox(
                width: 40, height: 40,
                child: CustomPaint(painter: _LoadingPainter()),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Connecting to ${widget.deviceName}...',
          style: const TextStyle(
              color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildConnectedText() {
    return const Column(
      children: [
        Icon(Icons.check_circle, color: Color(0xFF1976D2), size: 40),
        SizedBox(height: 16),
        Text('Connected successfully!',
            style: TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFailedIndicator() {
    return Column(
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 40),
        const SizedBox(height: 16),
        const Text('Connection failed.\nPlease try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.red, fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1976D2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('Go Back',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _LoadingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius,
        Paint()
          ..color = const Color(0xFFBBDEFB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, 3.14159 * 1.5, false,
      Paint()
        ..color = const Color(0xFF1976D2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── Helper: compute EspStatus from BleService ─────────────────────────────
EspStatus bleToEspStatus(BleService ble) {
  if (ble.isConnected) return EspStatus.connected;
  if (ble.isScanning) return EspStatus.connecting;
  return EspStatus.disconnected;
}