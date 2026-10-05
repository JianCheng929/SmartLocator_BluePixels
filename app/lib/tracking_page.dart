import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
// ── ADD: import BleService ──────────────────────────────────
import 'services/ble_service.dart';
import 'item_information_page.dart';
import 'main_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_background.dart';
import 'notification_service.dart';
import 'main.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'esp_status_badge.dart';

class DeviceTrackingPage extends StatefulWidget {
  final String deviceName;
  final String photoUrl;
  const DeviceTrackingPage({
  super.key,
  this.deviceName  = '',
  this.photoUrl    = '',
  this.initialPage = 0,
});
final int initialPage;

  @override
  State<DeviceTrackingPage> createState() => _DeviceTrackingPageState();
}

class _DeviceTrackingPageState extends State<DeviceTrackingPage>
    with TickerProviderStateMixin {
      
    Future<void> _resetSlidersForZone(String proximity) async {
    int zoneBeep;
    int zoneVol;
    switch (proximity) {
      case 'CLOSED BY': zoneBeep = 1; zoneVol = 25;  break;
      case 'NEARBY':    zoneBeep = 1; zoneVol = 25;  break;
      case 'FAR':       zoneBeep = 2; zoneVol = 50;  break;
      case 'TOO FAR':   zoneBeep = 3; zoneVol = 75;  break;
      default:          zoneBeep = 3; zoneVol = 100; break; // SIGNAL LOST
    }
    setState(() {
      _buzzerMode  = zoneBeep;
      _volumeLevel = zoneVol / 100.0;
      _zoneResetTime = DateTime.now(); 
    });
    // Send to ESP32 so hardware matches UI
    // Send beep first, wait longer to ensure ESP32 processes it
    await _ble.setBeep(zoneBeep);
    await Future.delayed(const Duration(milliseconds: 300));
    await _ble.setVolume(zoneVol);
    await Future.delayed(const Duration(milliseconds: 300));
    // Send beep again to confirm — ESP32 may miss first command during scan
    await _ble.setBeep(zoneBeep);
  }
  // ── BleService ──────────────────────────────────────────────────────────
  final _ble = BleService();
  StreamSubscription? _statusSub;
  StreamSubscription? _connSub;

  // ── Live status from ESP32 ───────────────────────────────────────────────
  TrackerStatus _s = const TrackerStatus();

  
  // ── Local UI state (sliders) ────────────────────────────────────────────
  double _volumeLevel = 0.25;  // 0.0 – 1.0, maps to 0–100
  int    _buzzerMode  = 1;    // 1, 2, or 3 beeps
  bool _localBuzzerOn = true; // optimistic local state
  // ── Last proximity — used to detect changes for notification popup ───────
  String? _lastProximity;
  Timer?  _proximityDebounceTimer;
  String? _pendingProximity;
  DateTime? _zoneResetTime;
  // ── Battery notification state ──────────────────────────
  bool _chargeButtonEnabled = false;
  bool _showCountdown       = false;
  int  _countdownSeconds    = 60;
  Timer? _countdownTimer;
  bool _featuresLocked      = false;
  final Set<int> _notifiedBatteryLevels = {};
  bool _isFirstStatusAfterConnect = true;
  bool _appSwitchOff = false;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  late final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;
  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _waveAnimationController;
  late Animation<double>   _waveAnimation;

  bool _showBtStatusCard    = true;
  bool _showZoneCard        = false;
  bool _showReconnectCard   = false;  // ← ADD
  String? _pendingZoneMsg;          // zone message to show after reconnect delay

  // ── Number of wave rings matches buzzer mode ────────────────────────────
  int get _numberOfWaves => _buzzerMode * 2;

  @override
  void initState() {
    super.initState();

    // 检查是否battery locked
  SharedPreferences.getInstance().then((prefs) {
    final locked = prefs.getBool('batteryLocked') ?? false;
    if (locked && mounted) {
      setState(() {
        _featuresLocked = true;
        _showCountdown  = false;
        _countdownSeconds = 0;
        _chargeButtonEnabled = true;
      });
      // 显示0秒的countdown dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _showLockedDialog();
        });
      });
    }
  });
    _localBuzzerOn = _s.buzzerOn;

    // ── Jump to correct initial page after build ──────────────
    if (widget.initialPage != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pageController.jumpToPage(widget.initialPage);
      });
    }

    // Seed from last known BLE status
    _s = _ble.status;

    // Play start sound if connected
    if (_ble.isConnected) {
      Future.delayed(const Duration(milliseconds: 500), () {
        NotificationService.showTrackingStart();
      });
      _syncSlidersFromStatus();
    } else {
      // Disconnected/Signal Lost → force max alert settings
      _volumeLevel = 1.0;   // 100%
      _buzzerMode  = 3;     // 3 beeps
    }

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_featuresLocked) setState(() { _now = DateTime.now(); });
    });

    // Subscribe to real-time status updates
    _statusSub = _ble.statusStream.listen((s) {
  if (!mounted) return;
  if (_featuresLocked) return;
  final newProximity = s.proximity;
  final appPowerOn = s.power;

  // ── App switch tracking ──────────────────────────────
  if (!appPowerOn && !_appSwitchOff) {
    setState(() {
      _appSwitchOff = true;
      // 不更新_s，保持last-seen状态
      if (_s.battery <= 80) _chargeButtonEnabled = true;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) _ble.saveLastSeen(user.uid);
    _pageController.animateToPage(1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut);
    return; // ← 直接return，不更新UI
  }

  if (appPowerOn && _appSwitchOff) {
    setState(() {
      _appSwitchOff = false;
      _isFirstStatusAfterConnect = true;
      _notifiedBatteryLevels.clear();
      _chargeButtonEnabled = false;
    });
  }

  // App switch OFF时不更新任何状态
  if (_appSwitchOff) return;

  setState(() {
    _s = s;
  });

  // ── 防止重连后重复触发通知 ────────────────────────────
  if (_isFirstStatusAfterConnect) {
    _isFirstStatusAfterConnect = false;
    final pct = s.battery;
    if (pct <= 80) _notifiedBatteryLevels.add(80);
    if (pct <= 60) _notifiedBatteryLevels.add(60);
    if (pct <= 40) _notifiedBatteryLevels.add(40);
    if (pct <= 20) _notifiedBatteryLevels.add(20);

    if (pct <= 80 && !_chargeButtonEnabled) {
      setState(() => _chargeButtonEnabled = true);
    }

    _checkBatteryNotifications(pct);
    return;
  }

  // ── Battery notifications ────────────────────────────
  _checkBatteryNotifications(s.battery);

  // 当app switch off时不显示proximity通知
  if (_appSwitchOff) return;

  // Notification + slider reset...
      // Notification + slider reset only when proximity truly changes (debounced)
      if (s.rssi > -100 || s.proximity == 'SIGNAL LOST') {
        if (_lastProximity == null) {
          _lastProximity = newProximity;
          _resetSlidersForZone(newProximity);

        } else if (_lastProximity != newProximity) {
          if (_pendingProximity != newProximity) {
            _pendingProximity = newProximity;
            _proximityDebounceTimer?.cancel();
            if (newProximity == 'SIGNAL LOST') {
              _showNotificationPopup(context, newProximity);
              _resetSlidersForZone(newProximity);
              // Also update BT page card
              setState(() {
                _lastProximity    = newProximity;
                _showBtStatusCard = true;
                _showZoneCard     = false;
              });
              return;
            }
            _proximityDebounceTimer = Timer(const Duration(seconds: 2), () {
              if (!mounted) return;
              if (_pendingProximity != null &&
                  _pendingProximity != _lastProximity) {
                _showNotificationPopup(context, _pendingProximity!);
                _resetSlidersForZone(_pendingProximity!);
                // ── Play phone notification sound for zone ────────────
                final zone = _pendingProximity!;
                if (zone == 'CLOSED BY' || zone == 'NEARBY') {
                  NotificationService.showPositive(zone);
                } else if (zone == 'FAR' || zone == 'TOO FAR') {
                  NotificationService.showBellAlert(zone);
                }
                setState(() { _lastProximity = _pendingProximity; });
              }
            });
          }
        }
      }
    });

    // Watch for BLE disconnection
    _connSub = _ble.connStream.listen((connected) {
      if (!mounted) return;
      if (!connected) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) _ble.saveLastSeen(user.uid);
        NotificationService.showDisconnection();
        setState(() {
          _showBtStatusCard = true;
          _showZoneCard     = false;
        });
        _pageController.animateToPage(1,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut);
      } else {
        if (_featuresLocked) return;

        _proximityDebounceTimer?.cancel();
        setState(() {
          _lastProximity      = null;
          _pendingProximity   = null;
          _showBtStatusCard   = false;  // hide normal status card
          _showReconnectCard  = true;   // show dedicated reconnect card
          _showZoneCard       = false;
          _isFirstStatusAfterConnect = true;
          _appSwitchOff = false;
        });
        NotificationService.showReconnection();
        // After 3s → hide reconnect card, show zone card
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() {
            _showReconnectCard = false;
            _showZoneCard      = true;
          });
        });
      }
    });

    // Wave animation
    _waveAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _waveAnimationController, curve: Curves.easeInOut),
    );
  }

  void _syncSlidersFromStatus() {
    if (_s.volume >= 0) _volumeLevel = _s.volume / 100.0;
    if (_s.beep   >= 1) _buzzerMode  = _s.beep.clamp(1, 3);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _connSub?.cancel();
    _waveAnimationController.dispose();
    _clockTimer?.cancel();
    _proximityDebounceTimer?.cancel();
    _countdownTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ── Proximity helpers ────────────────────────────────────────────────────
  bool get _isNearDevice =>
      _s.proximity == 'CLOSED BY' || _s.proximity == 'NEARBY';

  Color _proxColor(String p) {
    switch (p) {
      case 'CLOSED BY': return Colors.green;
      case 'NEARBY':    return Colors.lightGreen;
      case 'FAR':       return Colors.orange;
      case 'TOO FAR':   return Colors.deepOrange;
      default:          return Colors.red;
    }
  }

  Color _bellColor(String p) {
  switch (p) {
    case 'CLOSED BY': return const Color(0xFF4CAF50);
    case 'NEARBY':    return const Color(0xFF8BC34A);
    case 'FAR':       return const Color(0xFFFF9800);
    case 'TOO FAR':   return const Color(0xFFE91E63);
    default:          return const Color(0xFFFBC02D);
  }
}

  // ── Notification popup ───────────────────────────────────────────────────
  void _showNotificationPopup(BuildContext context, String proximity) {
    Color   bgColor;
    Color   borderColor;
    Color   btnColor;
    String  message;

    switch (proximity) {
      case 'CLOSED BY':
        bgColor     = const Color(0xFFD6F5E3);
        borderColor = const Color(0xFF4CAF50);
        btnColor    = const Color(0xFF4CAF50);
        message     = 'Nice! Your item is RIGHT BESIDE you!';
        break;
      case 'NEARBY':
        bgColor     = const Color(0xFFD6F5E3);
        borderColor = const Color(0xFF4CAF50);
        btnColor    = const Color(0xFF4CAF50);
        message     = 'Good news! Your item is NEARBY! You are close to your tracked item!';
        break;
      case 'FAR':
        bgColor     = const Color(0xFFFFD6E0);
        borderColor = const Color(0xFFE91E63);
        btnColor    = const Color(0xFFE91E63);
        message     = 'Moving away! Your tracked item is GETTING FAR.';
        break;
      case 'TOO FAR':
        bgColor     = const Color(0xFFFFD6E0);
        borderColor = const Color(0xFFE91E63);
        btnColor    = const Color(0xFFE91E63);
        message     = 'Attention! You are TOO FAR AWAY from your tracked items!';
        break;
      default: // SIGNAL LOST
        bgColor     = const Color(0xFFFFF9C4);
        borderColor = const Color(0xFFFBC02D);
        btnColor    = const Color(0xFFFBC02D);
        message =
            'SIGNAL LOST! Your item is out of detection range. Move closer to reconnect.';
    }

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            top: 80,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 8,
                        spreadRadius: 2),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: btnColor, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Notification!',
                          style: TextStyle(
                            color: btnColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: Icon(Icons.close, color: btnColor, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(message,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: btnColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(70, 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child:
                          const Text('Close', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brokenImageBox() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.grey, size: 32),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
Widget build(BuildContext context) {
  return Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Stack(
          children: [
        PageView(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (page) {
            setState(() {
              _currentPage = page;
              if (page == 1 && !_showReconnectCard) {
                _showBtStatusCard = true;
              }
            });
          },

          children: [
            // ── Page 0: Existing tracking page ──────────────────
            SingleChildScrollView(
              child: 
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const MainPage()),
                            (route) => false,
                          ),
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
                        const SizedBox(width: 16),
                        Expanded(
                          child: Builder(builder: (context) {
                            final isDark = Theme.of(context).brightness == Brightness.dark;
                            return Text('Device Tracking',
                              style: TextStyle(
                                fontSize: 20,  // ← 24 改 20
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1565C0)));
                          }),
                        ),
                        ListenableBuilder(
                          listenable: _ble,
                          builder: (_, __) => EspStatusBadge(status: bleToEspStatus(_ble)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showNotificationPopup(context, _s.proximity),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: Icon(Icons.notifications_outlined,
                              color: _bellColor(_s.proximity), size: 26),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Swipe hint
                  // Swipe hint + animated tab indicator
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildSwipeTabBar(
                      leftLabel: '← Tracking',
                      rightLabel: 'BT Signal →',
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),

                  const SizedBox(height: 20),
                  _buildAlertIconWithWaves(),
                  const SizedBox(height: 30),
                  _buildDeviceInfoBox(),
                  const SizedBox(height: 20),
                  _buildVolumeSlider(),
                  const SizedBox(height: 20),
                  _buildBatteryStatus(),
                  const SizedBox(height: 35),
                ],
              ),
            ),

            // ── Page 1: Bluetooth waves page ─────────────────────
            _buildBluetoothWavesPage(),
          ],
        ),
          ]
        )
      ),
    ),
  );
}
    // ── BT waves color helpers ────────────────────────────────────────────────
int get _filledWaves {
  switch (_s.proximity) {
    case 'CLOSED BY': return 4;
    case 'NEARBY':    return 3;
    case 'FAR':       return 2;
    case 'TOO FAR':   return 1;
    default:          return 0; // SIGNAL LOST
  }
}

bool get _isDisconnected => !_ble.isConnected;

// Colors from image 9
static const Color _waveInner    = Color(0xFF3F51B5); // inner circle blue
static const Color _waveFilled   = Color(0xFF5C6BC0); // filled ring
static const Color _waveUnfilled = Color(0xFFB3B3D9); // unfilled ring
static const Color _waveBlack    = Color(0xFF2C2C2C); // disconnected

Widget _buildBluetoothWavesPage() {
  final filled  = _filledWaves;
  final isDisc  = _isDisconnected;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark
    ? const Color(0xFF0D1B2A)
    : (isDisc ? const Color(0xFFF5F5F5) : const Color(0xFFF0F2FF));

  // Status text
  String statusTitle;
  Color  statusColor;
  String statusDesc;
  IconData statusIcon;

  if (isDisc) {
  statusTitle = 'Disconnection!';
  statusColor = const Color(0xFFE53935);
  statusDesc  = 'SmartLocator is disconnected and does not operate. '
                'Track your items using last-seen data.';
  statusIcon  = Icons.bluetooth_disabled;
} else {
  switch (_s.proximity) {
    case 'CLOSED BY':
      statusTitle = 'Connected — Closed By';
      statusColor = const Color(0xFF00C853);
      statusDesc  = 'Your SmartLocator is RIGHT BESIDE you! Signal is very strong.';
      statusIcon  = Icons.bluetooth_connected;
      break;
    case 'NEARBY':
      statusTitle = 'Connected — Nearby';
      statusColor = const Color(0xFF00C853);
      statusDesc  = 'Your SmartLocator is nearby. Signal is strong.';
      statusIcon  = Icons.bluetooth_connected;
      break;
    case 'FAR':
      statusTitle = 'Connected — Far';
      statusColor = const Color(0xFFFF9800);
      statusDesc  = 'Your SmartLocator signal is getting weaker. Move closer.';
      statusIcon  = Icons.bluetooth;
      break;
    case 'TOO FAR':
      statusTitle = 'Connected — Too Far';
      statusColor = const Color(0xFFE91E63);
      statusDesc  = 'Signal is very weak. Your item may be out of range soon.';
      statusIcon  = Icons.bluetooth;
      break;
    default:
      statusTitle = 'Signal Lost';
      statusColor = const Color(0xFFE53935);
      statusDesc  = 'No signal detected. Move closer to your SmartLocator.';
      statusIcon  = Icons.bluetooth_disabled;
  }
}

  return Container(
    color: bgColor,
    child: SafeArea(
      child: Column(
        children: [
          // ── Top bar ─────────────────────────────────────────
          // ── Top bar ─────────────────────────────────────────
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text('BT Signal',
                    style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1565C0))),
                  const Spacer(),
                  EspStatusBadge(status: bleToEspStatus(_ble)),
                ],
              ),
            ),

          // Swipe hint
          // Swipe hint + animated tab indicator
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildSwipeTabBar(
              leftLabel: '← Tracking',
              rightLabel: 'BT Signal →',
              isDark: isDark,
            ),
          ),

          // ── Status notification cards (dismissible) ──────────
          // ── Reconnection card (dedicated, separate from status card) ─────
          if (_showReconnectCard)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildBtCard(
                icon:    Icons.bluetooth_connected,
                title:   'Reconnection! Signal Found!',
                desc:    'SmartLocator is successfully reconnected and operates. Enjoy to use!',
                color:   const Color(0xFF00C853),
                onClose: () => setState(() => _showReconnectCard = false),
              ),
            ),

          // ── Status notification card (disconnection/signal lost) ──────────
          if (_showBtStatusCard && !_showReconnectCard)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildBtCard(
                icon:    statusIcon,
                title:   statusTitle,
                desc:    statusDesc,
                color:   statusColor,
                onClose: () => setState(() => _showBtStatusCard = false),
              ),
            ),

          // Zone card shown 2s after reconnect
          // Zone card shown 3s after reconnect — replaces reconnection card
          if (_showZoneCard && _ble.isConnected && _s.proximity != 'SIGNAL LOST') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildBtCard(
                icon:    Icons.bluetooth_connected,
                title:   statusTitle,   // uses the Connected — X title
                desc:    statusDesc,
                color:   statusColor,
                onClose: () => setState(() => _showZoneCard = false),
              ),
            ),
          ],

          const Spacer(),

          // ── Bluetooth waves ──────────────────────────────────
          AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              return SizedBox(
                width: 300, height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Wave ring 4 (outermost)
                    _buildWaveRing(130, filled >= 4, isDisc),
                    // Wave ring 3
                    _buildWaveRing(105, filled >= 3, isDisc),
                    // Wave ring 2
                    _buildWaveRing(80,  filled >= 2, isDisc),
                    // Wave ring 1
                    _buildWaveRing(56,  filled >= 1, isDisc),

                    // Animated outer pulse (only when connected)
                    if (!isDisc && filled > 0)
                      Container(
                        width: 130 + (_waveAnimation.value * 18),
                        height: 130 + (_waveAnimation.value * 18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _waveInner.withOpacity(
                            0.08 - (_waveAnimation.value * 0.07)),
                        ),
                      ),

                    // ── Center blue circle + BT icon ─────────────
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDisc
                            ? const Color(0xFF555555)
                            : (isDark ? const Color(0xFF5B8DD9) : _waveInner),
                        boxShadow: [
                          BoxShadow(
                            color: (isDisc
                                ? Colors.grey
                                : _waveInner).withOpacity(0.4),
                            blurRadius: 16, spreadRadius: 4),
                        ],
                      ),
                      child: Icon(
                        isDisc
                            ? Icons.bluetooth_disabled
                            : Icons.bluetooth,
                        color: Colors.white, size: 36),
                    ),
                  ],
                ),
              );
            },
          ),

          const Spacer(),

          // ── Reminder text ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1A2F4A)
                      : const Color(0xFFEEEEFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _waveInner.withOpacity(0.3)),
                ),
              child: Row(
                children: [
                  Icon(Icons.bluetooth,
                    color: _waveInner, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reminder...',
                          style: TextStyle(
                            color: _waveInner,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          'The circles indicate how close you are to the '
                          'SmartLocator. Enjoy the tracking process!',
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white70 : Colors.grey[700],
                            fontSize: 11, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Reusable dismissible BT status card ──────────────────────────────────
Widget _buildBtCard({
  required IconData icon,
  required String   title,
  required String   desc,
  required Color    color,
  required VoidCallback onClose,
}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A2F4A) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      boxShadow: [BoxShadow(
        color: color.withOpacity(0.1), blurRadius: 8, spreadRadius: 2)],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
              const SizedBox(height: 4),
              Text(desc,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70 : Colors.grey[700],
                  fontSize: 12, height: 1.4)),
            ],
          ),
        ),
        // ── X dismiss button ────────────────────────
        GestureDetector(
          onTap: onClose,
          child: Icon(Icons.close, color: color, size: 18),
        ),
      ],
    ),
  );
}

// ── Zone title/desc helpers ───────────────────────────────────────────────
String _zoneTitle(String proximity) {
  switch (proximity) {
    case 'CLOSED BY': return 'Closed By!';
    case 'NEARBY':    return 'Nearby!';
    case 'FAR':       return 'Getting Far';
    case 'TOO FAR':   return 'Too Far Away!';
    default:          return 'Signal Lost';
  }
}

String _zoneDesc(String proximity) {
  switch (proximity) {
    case 'CLOSED BY': return 'Your item is RIGHT BESIDE you!';
    case 'NEARBY':    return 'Your item is nearby. You are close!';
    case 'FAR':       return 'Moving away — your item is getting far.';
    case 'TOO FAR':   return 'Very far! Move closer to your item.';
    default:          return 'Out of detection range. Move closer.';
  }
}

// ── Single wave ring widget ───────────────────────────────────────────────
Widget _buildWaveRing(double radius, bool filled, bool isDisc) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final Color filledColor = isDark
      ? const Color(0xFF90CAF9)   // light blue for dark mode
      : const Color(0xFF5C6BC0);  // original indigo for light mode
  final Color unfilledColor = isDark
      ? const Color(0xFF546E8A)   // muted blue-grey for dark mode
      : const Color(0xFFB3B3D9);  // original for light mode

  Color color;
  if (isDisc) {
    color = (isDark ? Colors.grey.shade600 : _waveBlack).withOpacity(0.5);
  } else if (filled) {
    color = filledColor;
  } else {
    color = unfilledColor;
  }
  return Container(
    width: radius * 2,
    height: radius * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled && !isDisc
          ? color.withOpacity(0.25)
          : Colors.transparent,
      border: Border.all(
        color: color,
        width: filled && !isDisc ? 3.5 : 2.0,
      ),
    ),
  );
}

    Widget _buildAlertIconWithWaves() {
    int waveCount;
    switch (_s.proximity) {
      case 'CLOSED BY':   waveCount = 0; break;
      case 'NEARBY':      waveCount = 1; break;
      case 'FAR':         waveCount = 2; break;
      case 'TOO FAR':     waveCount = 3; break;
      default:            waveCount = 4; break; // SIGNAL LOST
    }

    if (_s.proximity == 'NEARBY') {
      final vol = _s.volume >= 0 ? _s.volume : (_volumeLevel * 100).toInt();
      if      (vol >= 80) {
        waveCount = 4;
      } else if (vol >= 60) waveCount = 3;
      else if (vol >= 40) waveCount = 2;
      else if (vol >= 20) waveCount = 1;
      else                waveCount = 0;
    }

    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (int i = waveCount - 1; i >= 0; i--)
                Container(
                  width:  120 + ((waveCount - i) * 36.0) +
                          (_waveAnimation.value * 10),
                  height: 120 + ((waveCount - i) * 36.0) +
                          (_waveAnimation.value * 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFC107).withOpacity(
                      math.max(0.0,
                        0.30 - (i * 0.06) - (_waveAnimation.value * 0.06)),
                    ),
                  ),
                ),

              // Center circle
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFA000),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFFA000),
                      blurRadius: 20,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.alarm,
                  size: 52,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Device info box ──────────────────────────────────────────────────────
  Widget _buildDeviceInfoBox() {
    final h24  = _now.hour;
    final isAm = h24 < 12;
    int displayH = h24 % 12;
    if (displayH == 0) displayH = 12;
    final hour   = displayH.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');

    String day, month, year;
    if (_s.date.isNotEmpty && !_s.date.startsWith('1 Jan')) {
      final dateParts = _s.date.trim().split(' ');
      if (dateParts.length >= 3) {
        day = dateParts[0];
        const months = {
          'Jan':'01','Feb':'02','Mar':'03','Apr':'04',
          'May':'05','Jun':'06','Jul':'07','Aug':'08',
          'Sep':'09','Oct':'10','Nov':'11','Dec':'12',
        };
        month = months[dateParts[1]] ?? dateParts[1];
        year  = dateParts[2];
      } else { day='--'; month='--'; year='----'; }
    } else {
      day   = _now.day.toString();
      month = _now.month.toString().padLeft(2, '0');
      year  = _now.year.toString();
    }

    // Resolve the photo URL: prefer live BLE status photo, fall back to widget param
    final resolvedPhotoUrl = widget.photoUrl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0F2540)           // darkest navy — matches your bg
        : const Color(0xFFE8E8E8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── ADDED: Item photo display ────────────────────────────────
          if (resolvedPhotoUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: resolvedPhotoUrl.startsWith('http')
                  // Network URL (if upgraded to Blaze later)
                  ? Image.network(
                      resolvedPhotoUrl,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _brokenImageBox(),
                    )
                  // Local Android file path (free plan)
                  : Image.file(
                      File(resolvedPhotoUrl),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _brokenImageBox(),
                    ),
            ),
            const SizedBox(height: 14),
          ],
          // ────────────────────────────────────────────────────────────

          // Item name
          _buildInfoRow(Icons.shopping_bag, 'Item',
              _s.item.isEmpty ? (widget.deviceName.isEmpty ? '—' : widget.deviceName) : _s.item),

          const SizedBox(height: 12),

          // Time row
          _buildTimeRow(hour, minute, isAm),

          const SizedBox(height: 12),

          // Date row
          _buildDateRow(day, month, year),

          const SizedBox(height: 12),

          // Floor
          _buildInfoRow(Icons.layers, 'Floor', 
          _s.calDone ? _s.floorName : (_s.floorName.isEmpty ? '—' : _s.floorName)),

          const SizedBox(height: 12),

          // Status
          _buildStatusRow(_s.proximity),

          const SizedBox(height: 12),

          // Buzzer ON/OFF toggle
          _buildBuzzerToggleRow(),

          const SizedBox(height: 16),

          // Track New Item button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ItemInformationPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1976D2).withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline, 
                        color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Track New Item',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A2F4A)           // mid-navy card colour
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRow(String hour, String minute, bool isAm) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text('Time:',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        Container(
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8D5F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF9C7AC7), width: 2),
          ),
          child: Text(
            hour,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF6B4E9C),
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(':',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70 : Colors.black87,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
          ),
        Container(
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            minute,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white : Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isAm
                    ? const Color(0xFFB8A0D9)
                    : Colors.grey[300],
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Text(
                'AM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isAm ? Colors.white : Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: !isAm
                    ? const Color(0xFFB8A0D9)
                    : Colors.grey[300],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Text(
                'PM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: !isAm ? Colors.white : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateRow(String day, String month, String year) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text('Date:',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A2F4A)           // mid-navy card colour
                  : Colors.white,
                borderRadius: BorderRadius.circular(8)),
            child: Text(day,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A2F4A)           // mid-navy card colour
                  : Colors.white,
                borderRadius: BorderRadius.circular(8)),
            child: Text(month,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A2F4A) : Colors.white,
                borderRadius: BorderRadius.circular(8)),
            child: Text(year,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(String proximity) {
    final color = _proxColor(proximity);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text('Status:',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1A2F4A)           // mid-navy card colour
                : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  proximity,
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Icon(Icons.check_circle_outline, color: color, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBuzzerToggleRow() {
  return Row(
    children: [
      SizedBox(
        width: 80,
        child: Text('Buzzer:',
            style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70 : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ),
      Expanded(
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              // ON
              Expanded(
                child: GestureDetector(
                  onTap: _featuresLocked ? null : () {
                    setState(() => _localBuzzerOn = true);
                    _ble.setBuzzer(true);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _localBuzzerOn
                          ? const Color(0xFFE8D5F7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'ON',
                        style: TextStyle(
                          color: _localBuzzerOn
                              ? Colors.black87
                              : Colors.black38,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // OFF
              Expanded(
                child: GestureDetector(
                  onTap: _featuresLocked ? null : () {
                    setState(() => _localBuzzerOn = false);
                    _ble.setBuzzer(false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: !_localBuzzerOn
                          ? const Color(0xFFE8D5F7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'OFF',
                        style: TextStyle(
                          color: !_localBuzzerOn
                              ? Colors.black87
                              : Colors.black38,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

  Widget _buildVolumeSlider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A2F4A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              spreadRadius: 2)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Buzzer Sound Control',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B4E9C),
            ),
          ),
          const SizedBox(height: 20),

          // Volume slider
          _buildSliderRow(
            label: 'Volume',
            value: _volumeLevel,
            onChanged: _featuresLocked ? null : (v) => setState(() => _volumeLevel = v),
            onChangeEnd: _featuresLocked ? null : (v) { _ble.setVolume((v * 100).toInt()); },
            displayValue: '${(_volumeLevel * 100).round()}%',
          ),

          const SizedBox(height: 24),

          // Beep slider
          _buildSliderRow(
            label: 'Beep',
            value: (_buzzerMode - 1) / 2.0,
            onChanged: _featuresLocked ? null : (v) { setState(() { _buzzerMode = (v * 2).round() + 1; }); },
            onChangeEnd: _featuresLocked ? null : (v) { _ble.setBeep((v * 2).round() + 1); },
            displayValue: '$_buzzerMode',
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required Function(double)? onChanged,
    required Function(double)? onChangeEnd,
    required String displayValue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white : Colors.black87)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF9C7AC7),
              inactiveTrackColor: const Color(0xFFE8D5F7),
              thumbColor: const Color(0xFF6B4E9C),
              trackHeight: 14,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged != null ? (v) => onChanged(v) : null, // ✅ null = disabled
              onChangeEnd: onChangeEnd != null ? (v) => onChangeEnd(v) : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(displayValue,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white : Colors.black87)),
        ),
      ],
    );
  }

  Widget _buildBatteryStatus() {
  final int pct = _s.battery;

  int filledSegments = pct >= 80 ? 5
    : pct > 60 ? 4
    : pct > 40 ? 3
    : pct > 20 ? 2
    : 1;

  const colorScheme = [
    Color(0xFFE91E63),
    Color(0xFFF8BBD9),
    Color(0xFFFFF176),
    Color(0xFFC5E1A5),
    Color(0xFF81C784),
  ];

  final segmentColors = List.generate(
    5, (i) => i < filledSegments ? colorScheme[i] : Colors.transparent,
  );

  // ── 根据百分比决定标签文字和颜色 ──
  String batteryLabel;
  Color batteryLabelColor;
  if (pct >= 80) {
    batteryLabel = 'BATTERY\nGOOD';
    batteryLabelColor = const Color(0xFF81C784);
  } else if (pct > 60) {
    batteryLabel = 'BATTERY\nGOOD';
    batteryLabelColor = const Color(0xFF4CAF50);
  } else if (pct > 40) {
    batteryLabel = 'BATTERY\nNORMAL';
    batteryLabelColor = const Color(0xFFFBC02D);
  } else if (pct > 20) {
    batteryLabel = 'BATTERY\nLOW';
    batteryLabelColor = const Color(0xFFF8BBD9);
  } else {
    batteryLabel = 'BATTERY\nLOW';
    batteryLabelColor = const Color(0xFFE91E63);
  }

  bool showBolt = pct < 100;

  return Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160, height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade600, width: 5),
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A2F4A) : Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: List.generate(5, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: segmentColors[index],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: index == 2 && showBolt
                          ? const Center(child: Icon(
                              Icons.bolt, color: Colors.black54, size: 32))
                          : null,
                    ),
                  );
                }),
              ),
            ),
          ),
          Container(
            width: 10, height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 20),
          Text(
            batteryLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: batteryLabelColor,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _buildChargeButtons(),
      // ← 红色box完全删掉，不再显示
    ],
  );
}

Widget _buildChargeButtons() {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 75),
    height: 44,
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A2F4A) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: GestureDetector(
      onTap: _chargeButtonEnabled
          ? () => _showChargeInstructions()
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: _chargeButtonEnabled
              ? const Color(0xFFB8A0D9)
              : const Color(0xFFB8A0D9).withOpacity(0.45),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.battery_charging_full,
              color: _chargeButtonEnabled
                  ? const Color(0xFF4D2A8D)
                  : const Color(0xFF4D2A8D).withOpacity(0.45),
              size: 20),
            const SizedBox(width: 8),
            Text('Charge',
              style: TextStyle(
                color: _chargeButtonEnabled
                    ? Colors.white
                    : Colors.white.withOpacity(0.55),
                fontWeight: FontWeight.w600,
                fontSize: 15)),
          ],
        ),
      ),
    ),
  );
}

void _showChargeInstructions() {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              const Icon(Icons.circle, color: Colors.red, size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Remember recharging procedure below!',
                  style: TextStyle(
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Please recharge immediately:',
              style: TextStyle(fontSize: 12, color: Colors.black87)),
            const SizedBox(height: 8),
            _buildStep('1', 'Click "OK, I\'ll charge!" button', bold: true),
            _buildStep('2', 'Turn OFF the switch', bold: true),
            _buildStep('3', 'Open the casing lid', bold: true,
              suffix: ' for ventilation'),
            _buildStep('4', 'Connect USB-C cable to powerbank'),
            // Step 4 with blue "Blue light" text
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('5. ',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Expanded(child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                      children: [
                        TextSpan(text: 'Wait until '),
                        TextSpan(
                          text: 'a Blue light',
                          style: TextStyle(
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.bold)),
                        TextSpan(text: ' appears at the charging port'),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            _buildStep('6', 'Close the casing lid'),
            _buildStep('7', 'Turn ON the switch again.', bold: true),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber, size: 14, color: Colors.black87),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Note: Must wait for BLUE light before turning switch ON.',
                  style: TextStyle(fontSize: 11, color: Colors.black87))),
              ]),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // 锁定features
                    setState(() => _featuresLocked = true);
                    SharedPreferences.getInstance().then((p) {
                      p.setBool('chargingPending', true);
                    });
                    _ble.sendCommand('MARK:RESET');
                    _showImage5Dialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C6BC0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  ),
                  child: const Text('OK, I\'ll charge!',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Not yet!',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void _checkBatteryNotifications(int pct) {
  if (_featuresLocked) return;
  if (_appSwitchOff) return;
  if (pct <= 80 && !_chargeButtonEnabled) {
    setState(() => _chargeButtonEnabled = true);
  }
  if (pct <= 80 && pct > 60 && !_notifiedBatteryLevels.contains(80)) {
    _notifiedBatteryLevels.add(80);
    NotificationService.showBatteryDecreasing(80, 'Still GOOD ✅');
  }
  if (pct <= 60 && pct > 40 && !_notifiedBatteryLevels.contains(60)) {
    _notifiedBatteryLevels.add(60);
    NotificationService.showBatteryDecreasing(60, 'NORMAL ⚠️');
  }
  if (pct <= 40 && pct > 20 && !_notifiedBatteryLevels.contains(40)) {
    _notifiedBatteryLevels.add(40);
    NotificationService.showBatteryDecreasing(40, 'Slightly LOW ⚠️');
  }
  if (pct <= 20 && !_notifiedBatteryLevels.contains(20)) {
    _notifiedBatteryLevels.add(20);
    NotificationService.showBatteryDecreasing(20, 'Exactly LOW ⚠️');
  }
  if (pct <= 2 && !_showCountdown && !_featuresLocked) {
    _startCountdown();
  }
}

void _startCountdown() {
  setState(() {
    _showCountdown    = true;
    _countdownSeconds = 60;
  });
  // 保存locked标记到SharedPreferences
  SharedPreferences.getInstance().then((prefs) {
    prefs.setBool('batteryLocked', true);
  });
  NotificationService.showBatteryLockWarning();
  _showCountdownDialog();
}

void _showCountdownDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        _countdownTimer?.cancel();
        _countdownTimer = Timer.periodic(
          const Duration(seconds: 1), (t) {
          if (!mounted) { t.cancel(); return; }
          if (_countdownSeconds > 0) {
            setDlg(() => _countdownSeconds--);
            } else {
              t.cancel();
              if (mounted) {
                Navigator.of(ctx).pop(); // countdown dialog
                setState(() {
                  _featuresLocked = true;
                  _showCountdown  = false;
                });
                _ble.setBuzzer(false);
                _showLockedDialog();
              }
            }
        });
        return WillPopScope(
  onWillPop: () async => false,
  child: Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Countdown ring
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.shade400, width: 3),
            ),
            child: Center(
              child: Text('$_countdownSeconds',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600)),
            ),
          ),
          const SizedBox(height: 6),
          Text('Features locking in',
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade400,
              fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('seconds.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),

          // Header
          Row(children: [
            const Icon(Icons.circle, color: Colors.red, size: 10),
            const SizedBox(width: 6),
            Expanded(
              child: Text('SmartLocator Battery LOW! (<2%)',
                style: TextStyle(
                  color: Colors.red.shade600,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Please recharge immediately:',
              style: TextStyle(fontSize: 12, color: Colors.black87))),
          const SizedBox(height: 6),
          _buildStep('1', 'Click "OK, I\'ll charge!" button', bold: true),
          _buildStep('2', 'Turn OFF the switch', bold: true),
          _buildStep('3', 'Open the casing lid', bold: true,
            suffix: ' for ventilation'),
          _buildStep('4', 'Connect USB-C cable to powerbank'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('5. ',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
                Expanded(child: RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                    children: [
                      TextSpan(text: 'Wait until '),
                      TextSpan(text: 'a Blue light',
                        style: TextStyle(
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.bold)),
                      TextSpan(text: ' appears at the charging port'),
                    ],
                  ),
                )),
              ],
            ),
          ),
          _buildStep('6', 'Close the casing lid'),
          _buildStep('7', 'Turn ON the switch again.', bold: true),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber, size: 14, color: Colors.black87),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Note: Must wait for BLUE light before turning switch ON.',
                style: TextStyle(fontSize: 11, color: Colors.black87))),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  _countdownTimer?.cancel();
                  _countdownTimer?.cancel(); 
                  Navigator.of(ctx).pop();
                  SharedPreferences.getInstance().then((p) =>
                    p.setBool('chargingPending', true));
                  _ble.sendCommand('MARK:RESET'); // ← tells ESP32 to expect a reset
                  _showImage5Dialog(); // ← asks user: "Blue light seen?"
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('OK, I\'ll charge!',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  // 什么都不做，frozen at 0
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Not yet!',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ]),
        ],
      ),
    ),
  ),
);
      },
    ),
  );
}

void _showLockWarning() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 20),
          child: Builder(builder: (ctx2) {
            final isDark = Theme.of(ctx2).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : Colors.black87;
            final subColor  = isDark ? Colors.white.withOpacity(0.6) : Colors.black54;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SmartLocator will not function well unless you fully recharge it!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor)),          // ✅ dark mode: white
                const SizedBox(height: 16),
                Text(
                  'Be patient and click Yes when seeing blue flashes!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: subColor,             // ✅ dark mode: white60
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showImage5Dialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C6BC0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 10),
                  ),
                  child: const Text('I get it!',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            );
          }),
        ),
      ),
    ),
  );
}

// ── Locked dialog — shown after countdown reaches 0 or app reopen ────────
void _showLockedDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: Colors.red.shade600, size: 48),
              const SizedBox(height: 12),
              Text(
                'SmartLocator Features Locked!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please recharge your SmartLocator to unlock all features.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showImage5Dialog();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 10),
                ),
                child: const Text('OK, I\'ll charge now!',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


void _showImage5Dialog({bool showImage7 = false}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Builder(builder: (ctx2) {
            final isDark = Theme.of(ctx2).brightness == Brightness.dark;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Did you fully recharge your SmartLocator?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 4),
                const Text('(Blue light seen?)',
                  style: TextStyle(
                    color: Color(0xFF5C6BC0),
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _onFullyRecharged();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5C6BC0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      ),
                      child: const Text('Yes !',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showLockWarning();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      ),
                      child: const Text('No !',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                  ],
                ),
                if (showImage7) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Be patient and click yes when seeing blue flashes!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13, color: Colors.black54)),
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    ),
  );
}

void _onFullyRecharged() async {
  _countdownTimer?.cancel();
  _proximityDebounceTimer?.cancel();

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('batteryLocked', false);
  await prefs.setBool('chargingPending', false); 
  await prefs.setBool('needsBattReset', true);
  await prefs.setBool('smartLocatorOff', true);
  await prefs.remove('forceResetUI'); //  
  
  await _ble.disconnect();

  if (!mounted) return;

  setState(() {
    _featuresLocked      = false;
    _chargeButtonEnabled = false;
    _showCountdown       = false;
    _notifiedBatteryLevels.clear();
  });

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const MainPage()),
    (route) => false,
  );

  Future.delayed(const Duration(milliseconds: 500), () {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dlgCtx) {
        Future.delayed(const Duration(seconds: 5), () {
          if (dlgCtx.mounted) Navigator.of(dlgCtx).pop();
        });
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 12),
                const Text('Great! SmartLocator can work again!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  'Enjoy your tracking! Remember to turn ON the hardware switch, then use Find Device to reconnect.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  });
}

Widget _buildSwipeTabBar({
  required String leftLabel,
  required String rightLabel,
  required bool isDark,
}) {
  return AnimatedBuilder(
    animation: _pageController,
    builder: (context, child) {
      double page = 0.0;
      if (_pageController.hasClients && _pageController.page != null) {
        page = _pageController.page!;
      }
      final totalWidth = MediaQuery.of(context).size.width - 120;
      final tabWidth = totalWidth / 2;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60),
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.07)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            children: [
              // ── Sliding pill — moves smoothly with finger ────
              Positioned(
                left: page * tabWidth + 3,
                top: 3,
                bottom: 3,
                width: tabWidth - 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.16)
                        : const Color(0xFF1565C0).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              // ── Labels ───────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        leftLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: page < 0.5
                              ? FontWeight.w600 : FontWeight.w400,
                          color: isDark
                              ? Colors.white.withOpacity(
                                  page < 0.5 ? 0.95 : 0.4)
                              : const Color(0xFF1565C0).withOpacity(
                                  page < 0.5 ? 0.95 : 0.4),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        rightLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: page >= 0.5
                              ? FontWeight.w600 : FontWeight.w400,
                          color: isDark
                              ? Colors.white.withOpacity(
                                  page >= 0.5 ? 0.95 : 0.4)
                              : const Color(0xFF1565C0).withOpacity(
                                  page >= 0.5 ? 0.95 : 0.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildStep(String num, String text,
    {bool bold = false, String? suffix}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$num. ',
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Expanded(child: suffix != null
          ? RichText(text: TextSpan(
              style: const TextStyle(fontSize: 12),
              children: [
                TextSpan(text: text,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    color: bold ? Colors.red.shade700 : Colors.black54)),
                TextSpan(text: suffix,
                  style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.normal)),
              ]))
          : Text(text, style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? Colors.red.shade700 : Colors.black54))),
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