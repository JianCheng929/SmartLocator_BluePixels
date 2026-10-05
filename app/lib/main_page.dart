import 'dart:async';  
import 'package:flutter/material.dart';
import 'device_connection_page.dart';
import 'item_information_page.dart';
import 'history_page.dart';
import 'dashboard_page.dart';
import 'auth_intro_page.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'coach_mark_service.dart';
import 'account_page.dart';
import 'rating_page.dart';
import 'services/ble_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'tracking_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'app_background.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'guide_page.dart';
import 'esp_status_badge.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  bool _isMenuOpen = false;
  bool _bluetoothEnabled = false;
  bool _smartLocatorEnabled = false;
  bool _featuresLocked = false;
  final _ble = BleService();
  StreamSubscription? _btStateSub;

  final GlobalKey _menuKey            = GlobalKey();
  final GlobalKey _bluetoothIconKey   = GlobalKey();
  final GlobalKey _findDeviceKey      = GlobalKey();
  final GlobalKey _itemInfoKey        = GlobalKey();
  final GlobalKey _bluetoothToggleKey = GlobalKey();
  final GlobalKey _smartLocatorKey    = GlobalKey();
  final GlobalKey _backButtonKey      = GlobalKey();
  late TutorialCoachMark _tutorialCoachMark;

  late AnimationController _waveAnimationController;
  late Animation<double> _waveAnimation;
  late AnimationController _menuAnimationController;
  late Animation<double> _menuAnimation;
  late ScrollController _scrollController;
  late AnimationController _scrollHintAnimationController;

  List<TargetFocus> _buildTargets() {
    return [
      TargetFocus(
        identify: 'menu',
        keyTarget: _menuKey,
        shape: ShapeLightFocus.RRect,
        radius: 20,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Navigation bar',
              description: 'Click the menu button and slowly scroll down to discover hidden functions!',
              onSkip: controller.skip,
              onNext: controller.next,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'bluetooth_icon',
        keyTarget: _bluetoothIconKey,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Bluetooth Icon',
              description: "Enable the bluetooth connection to 'light on' the bluetooth!",
              onSkip: controller.skip,
              onNext: controller.next,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'find_device',
        keyTarget: _findDeviceKey,
        shape: ShapeLightFocus.RRect,
        radius: 20,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Find Device',
              description: 'After enabling bluetooth connection, click this square box to connect bluetooth tracker.',
              onSkip: controller.skip,
              onNext: controller.next,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'item_info',
        keyTarget: _itemInfoKey,
        shape: ShapeLightFocus.RRect,
        radius: 20,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Item Information',
              description: 'Enter the name of your tracked items and which floor levels you are staying at ACCURATELY!',
              onSkip: controller.skip,
              onNext: controller.next,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'bluetooth_toggle',
        keyTarget: _bluetoothToggleKey,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Bluetooth enabled',
              description: 'Turn on bluetooth to connect with and find the smartlocator device!',
              onSkip: controller.skip,
              onNext: controller.next,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'smartlocator',
        keyTarget: _smartLocatorKey,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Smartlocator On/Off Status',
              description: "Instead of turning on/off the switch in the casing, you can control the status of the whole smartlocator here!",
              onSkip: controller.skip,
              onNext: controller.next,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'back_btn',
        keyTarget: _backButtonKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => CoachMarkService.buildCoachContent(
              title: 'Rewind button ←',
              description: 'Rewind to the home page',
              onSkip: controller.skip,
              onNext: controller.next,
              isLast: true,
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _checkAndShowCoachMark() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenCoach = prefs.getBool('hasSeenCoachMark') ?? false;
    if (!hasSeenCoach) {
        await prefs.setBool('hasSeenCoachMark', true);
      _showCoachMark();
    }
  }

  // ✅ 新 — 延长到 1500ms，加 mounted 检查
  void _showCoachMark() {
    _tutorialCoachMark = CoachMarkService.createTutorial(
      context: context,
      targets: _buildTargets(),
      onFinish: () => debugPrint('Coach mark finished'),
      onSkip: () => debugPrint('Coach mark skipped'),
    );
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      _tutorialCoachMark.show(context: context);
    });
  }

  Future<void> _checkFeaturesLocked() async {
      final prefs = await SharedPreferences.getInstance();
      final locked = prefs.getBool('batteryLocked') ?? false;
      final pending = prefs.getBool('chargingPending')  ?? false;
      
      if (locked && !pending && mounted) {
        setState(() => _featuresLocked = true);
        _showLockedDialog();
      }
  }

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
              Text('SmartLocator Features Locked!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold,
                  color: Colors.red.shade600)),
              const SizedBox(height: 8),
              const Text(
                'Please recharge your SmartLocator to unlock all features.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                   _ble.sendCommand('MARK:RESET'); 
                  _showImage5DialogMain(); // ✅ 跳转充电流程
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 10),
                ),
                child: const Text('OK, I\'ll charge!',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _checkChargingPending() async {
  final prefs = await SharedPreferences.getInstance();
  final pending = prefs.getBool('chargingPending') ?? false;
  if (pending && mounted) {
    // ✅ MainPage 显示断开锁定状态
    setState(() {
      _featuresLocked = true;        // ✅ 只保留这行
    });

    // ✅ 自动弹 Blue light seen?
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _showImage5DialogMain();
    });
  }
}

Future<void> _checkSmartLocatorOff() async {
  final prefs = await SharedPreferences.getInstance();
  final needsOff = prefs.getBool('smartLocatorOff') ?? false;
  if (needsOff && mounted) {
    await prefs.setBool('smartLocatorOff', false); // ✅ 清flag
    setState(() => _smartLocatorEnabled = false);  // ✅ 强制OFF
  }
}

void _showImage5DialogMain() {
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
                    fontSize: 14, fontWeight: FontWeight.w500,
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
                        _onFullyRechargedMain();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5C6BC0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      ),
                      child: const Text('Yes !',
                        style: TextStyle(color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showLockWarningMain();
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
              ],
            );
          }),
        ),
      ),
    ),
  );
}

void _showLockWarningMain() {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(builder: (bCtx) {
                final isDark = Theme.of(bCtx).brightness == Brightness.dark;
                return Column(
                  children: [
                    Text(
                      'SmartLocator will not function well unless you fully recharge it!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87)),
                    const SizedBox(height: 16),
                    Text(
                      'Be patient and click Yes when seeing blue flashes!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white.withOpacity(0.6) : Colors.black54,
                        fontStyle: FontStyle.italic)),
                  ],
                );
              }),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showImage5DialogMain();
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
          ),
        ),
      ),
    ),
  );
}

void _onFullyRechargedMain() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('batteryLocked', false);
  await prefs.setBool('chargingPending', false);
  await prefs.setBool('needsBattReset', true);
  await prefs.setBool('needsEspReset', true);

  // ✅ 真正断开 BLE
  await _ble.disconnect();

  if (!mounted) return;
  setState(() {
    _featuresLocked      = false;
    _bluetoothEnabled    = true;
    _smartLocatorEnabled = false;
  });
  _waveAnimationController.repeat();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dlgCtx) {
      Future.delayed(const Duration(seconds: 5), () {
        if (dlgCtx.mounted) Navigator.of(dlgCtx).pop();
      });
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
}

  @override
  void initState() {
    super.initState();

    _waveAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _waveAnimationController, curve: Curves.easeInOut),
    );
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _menuAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _menuAnimationController, curve: Curves.easeOut),
    );
    _scrollController = ScrollController();
    _scrollHintAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _menuAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _scrollHintAnimationController.repeat(reverse: true);
      } else if (status == AnimationStatus.dismissed) {
        _scrollHintAnimationController.stop();
      }
    });

    _smartLocatorEnabled = _ble.status.power;
    _ble.connStream.listen((connected) {
      debugPrint('[MAIN] connStream triggered: $connected');
  });
    _ble.addListener(_onBleChanged);
    _btStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      final isOn = state == BluetoothAdapterState.on;
      if (_bluetoothEnabled != isOn) {
        setState(() { _bluetoothEnabled = isOn; });
        if (isOn) {
          _waveAnimationController.repeat();
        } else {
          _waveAnimationController.stop();
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
    // ✅ 先等BT状态读完，再弹任何dialog
      final currentBtState = await FlutterBluePlus.adapterState.first;
      if (!mounted) return;
      setState(() {
        _bluetoothEnabled = currentBtState == BluetoothAdapterState.on;
      });
      if (_bluetoothEnabled) _waveAnimationController.repeat();

      // ✅ BT状态已正确后，才执行其他检查
      _checkAndShowCoachMark();
      _checkFeaturesLocked();
      _checkChargingPending();
      _checkSmartLocatorOff();
    });
  }

  void _onBleChanged() {
    if (!mounted) return;
    setState(() {
      if (_ble.isConnected) {
        _smartLocatorEnabled = _ble.status.power; // ✅ 只有连接时才读power状态
      } else {
        _smartLocatorEnabled = false; // ✅ 断开时永远OFF
      }
    });
  }

  @override
  void dispose() {
    _ble.removeListener(_onBleChanged);
    _waveAnimationController.dispose();
    _menuAnimationController.dispose();
    _scrollController.dispose();
    _scrollHintAnimationController.dispose();
    _btStateSub?.cancel();
    super.dispose();
  }

  void _shareApp() async {
  // Load QR code from assets
  final byteData = await rootBundle.load('assets/images/smartlocator_qr.png');
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/smartlocator_qr.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());

  await Share.shareXFiles(
    [XFile(file.path)],
    text:
      '📍 BluePixels SmartLocator\n'
      '━━━━━━━━━━━━━━━━━━━━━\n\n'
      '🔍 Never lose your personal belongings again!\n'
      'A BLE indoor tracker for real-time item tracking.\n\n'
      '📲 Scan the QR Code to download!\n'
      'Or download directly:\n'
      'https://drive.google.com/file/d/1aZWheEg3VfZPQH4zcqRHvuOyj0YG6Rgi/view\n\n'
      '⚙️ Allow "Install unknown apps" when prompted\n\n'
      'Built by BLUEPIXELS🚀',
    subject: 'Bluepixels Smartlocator — Download Now!',
  );
}

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _menuAnimationController.forward();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
          }
        });
      } else {
        _menuAnimationController.reverse();
      }
    });
  }

  void _showBluetoothPermissionDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Allow SmartLocator to enable Bluetooth?',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: Text('Deny',
                        style: TextStyle(color: Color(0xFF0A84FF), fontSize: 17, fontWeight: FontWeight.w500))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () { Navigator.pop(context); _enableBluetooth(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: Text('Allow',
                        style: TextStyle(color: Color(0xFF0A84FF), fontSize: 17, fontWeight: FontWeight.w500))),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _enableBluetooth() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    await FlutterBluePlus.turnOn();
    setState(() { _bluetoothEnabled = true; });
    _waveAnimationController.repeat();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bluetooth enabled! Ready to find SmartLocator.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleBluetooth(bool value) async {
  if (_featuresLocked) { _showLockedDialog(); return; } // ✅ 加这行
  if (value && !_bluetoothEnabled) {
    _showBluetoothPermissionDialog();
    } else if (!value && _bluetoothEnabled) {
      setState(() { _bluetoothEnabled = false; });
      _waveAnimationController.stop();
      AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turn off Bluetooth there, then press ← to return.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _toggleSmartLocator(bool value) async {
    if (_featuresLocked) { _showLockedDialog(); return; }
    if (!_ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SmartLocator not connected — connect first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _smartLocatorEnabled = value);
    await _ble.setPower(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _ble,
            builder: (_, __) => Stack(
            children: [
              SingleChildScrollView(           // ← ADD THIS
                child: ConstrainedBox(         // ← ADD THIS
                  constraints: BoxConstraints( // ← ADD THIS
                    minHeight: MediaQuery.of(context).size.height
                        - MediaQuery.of(context).padding.top
                        - MediaQuery.of(context).padding.bottom,
                  ),                           // ← ADD THIS
                  child: IntrinsicHeight(      // ← ADD THIS
                    child: Column(             // ← ORIGINAL Column, now wrapped
                      children: [
                        const SizedBox(height: 20),
                        KeyedSubtree(
                      key: _bluetoothIconKey,
                      child: _bluetoothEnabled
                          ? _buildAnimatedBluetoothIcon()
                          : _buildDisabledBluetoothIcon(),
                    ),
                    const SizedBox(height: 40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSquareButton(
                              key: _findDeviceKey,
                              icon: Icons.bluetooth_searching,
                              label: 'Find\ndevice',
                              color: const Color.fromARGB(255, 61, 118, 174),
                              onTap: () {
                                if (_featuresLocked) { _showLockedDialog(); return; }
                                if (_bluetoothEnabled) {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => const DeviceConnectionPage()));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enable Bluetooth first')));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildSquareButton(
                              key: _itemInfoKey,
                              icon: Icons.inventory_2_outlined,
                              label: 'Item\ninformation',
                              color: const Color(0xFF1976D2),
                              onTap: () {
                                if (_featuresLocked) { _showLockedDialog(); return; }
                                if (!_bluetoothEnabled || !_ble.isConnected) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enable Bluetooth and find device first'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => const ItemInformationPage()));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Column(
                        children: [
                          _buildToggleButton(
                            key: _bluetoothToggleKey,
                            icon: Icons.bluetooth,
                            label: _bluetoothEnabled ? 'Bluetooth enabled' : 'Bluetooth disabled',
                            value: _bluetoothEnabled,
                            onChanged: _toggleBluetooth,
                            lockWhenFeaturesLocked: false, 
                          ),
                          const SizedBox(height: 12),
                          _buildToggleButton(
                            key: _smartLocatorKey,
                            icon: Icons.location_on,
                            label: 'Smart Locator',
                            value: _smartLocatorEnabled,
                            onChanged: _toggleSmartLocator,
                            lockWhenFeaturesLocked: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),                         // ← ADD THIS
              ),                           // ← ADD THIS
            ),

            Positioned(
              top: 10, left: 10,
              child: GestureDetector(
                key: _backButtonKey,
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthIntroPage())),
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
            ),
                Positioned(
                  top: 14, right: 70,
                  child: ListenableBuilder(
                    listenable: _ble,
                    builder: (_, __) => EspStatusBadge(status: bleToEspStatus(_ble)),
                  ),
                ),
                // Menu button
                Positioned(
                  top: 10, right: 10,
                  child: GestureDetector(
                    key: _menuKey,
                    onTap: _toggleMenu,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: AnimatedIcon(
                        icon: AnimatedIcons.menu_close,
                        progress: _menuAnimation,
                        color: const Color(0xFF1565C0),
                        size: 24,
                      ),
                    ),
                  ),
                ),

                // Expandable sidebar menu
                AnimatedBuilder(
                  animation: _menuAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: 70, right: 10,
                      child: Transform.scale(
                        alignment: Alignment.topRight,
                        scale: _menuAnimation.value,
                        child: Opacity(
                          opacity: _menuAnimation.value,
                          child: Container(
                            width: 100, height: 380,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, 10))],
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Scrollbar(
                                      thumbVisibility: true,
                                      thickness: 3,
                                      radius: const Radius.circular(10),
                                      child: SingleChildScrollView(
                                        controller: _scrollController,
                                        scrollDirection: Axis.vertical,
                                        physics: const BouncingScrollPhysics(),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildMenuItem(Icons.dashboard_outlined, 'Dashboard'),
                                            const SizedBox(height: 8),
                                            _buildMenuItem(Icons.history, 'History'),
                                            const SizedBox(height: 8),
                                            _buildMenuItem(Icons.person_outline, 'Account'),
                                            const SizedBox(height: 8),
                                            _buildMenuItem(Icons.share_outlined, 'Share'),
                                            const SizedBox(height: 8),
                                            _buildMenuItem(Icons.star_outline, 'Rating us'),
                                            const SizedBox(height: 8),
                                            _buildMenuItem(Icons.menu_book_outlined, 'Guide'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 0, right: 0, bottom: 0, height: 50,
                                  child: AnimatedBuilder(
                                    animation: _scrollHintAnimationController,
                                    builder: (context, child) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.white.withOpacity(0),
                                              Colors.white.withOpacity(0.9 + (_scrollHintAnimationController.value * 0.1)),
                                            ],
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(20),
                                            bottomRight: Radius.circular(20),
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(Icons.keyboard_arrow_down, size: 24,
                                            color: const Color(0xFF1976D2).withOpacity(0.7 + (_scrollHintAnimationController.value * 0.3))),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Go to Tracking button
                Positioned(
                  bottom: 20, right: 20,
                  child: GestureDetector(
                  onTap: () {
                      if (!_ble.isConnected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Not connected to SmartLocator yet'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DeviceTrackingPage(
                          deviceName: _ble.cachedItemName,
                          photoUrl:   _ble.cachedPhotoUrl,
                        ),
                      ));
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: _ble.isConnected
                            ? Colors.white.withOpacity(0.9)
                            : Colors.grey.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: Icon(Icons.arrow_forward,
                        color: _ble.isConnected
                            ? const Color(0xFF1565C0)
                            : Colors.grey,
                        size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisabledBluetoothIcon() {
    return SizedBox(
      width: 200, height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 180, height: 180,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[200])),
          Container(width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)]),
            child: Icon(Icons.bluetooth, size: 50, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildAnimatedBluetoothIcon() {
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
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: const Color(0xFF90CAF9).withOpacity(0.3 - (_waveAnimation.value * 0.1)))),
              Container(
                width: 140 + (_waveAnimation.value * 15),
                height: 140 + (_waveAnimation.value * 15),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: const Color(0xFF42A5F5).withOpacity(0.5 - (_waveAnimation.value * 0.1)))),
              Container(
                width: 100, height: 100,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF1976D2),
                  boxShadow: [BoxShadow(color: Color(0xFF1976D2), blurRadius: 20, spreadRadius: 5)]),
                child: const Icon(Icons.bluetooth, size: 50, color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSquareButton({
    Key? key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key, onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    Key? key,
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool lockWhenFeaturesLocked = false,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, spreadRadius: 2, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? const Color(0xFF1976D2) : Colors.grey, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
              style: TextStyle(
                color: value ? Colors.grey[800] : Colors.grey[500],
                fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          Switch(
            value: (lockWhenFeaturesLocked && _featuresLocked) ? false : value,  // ✅ 锁定时强制显示 OFF
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF1976D2),
            activeTrackColor: const Color(0xFF90CAF9),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, {bool isLogout = false}) {
    return GestureDetector(
      onTap: () {
        _toggleMenu();
        if (label == 'History') {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const HistoryPage()));
        } else if (label == 'Dashboard') {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const DashboardPage()));
        } else if (label == 'Account') {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AccountPage()));
        } else if (label == 'Rating us') {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RatingPage()));
        } else if (label == 'Share') {
          _shareApp();
        } else if (label == 'Guide') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GuidePage()),
          );
        }
      },
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLogout ? Colors.red[50] : const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: isLogout ? Colors.red.withOpacity(0.2) : const Color(0xFF1976D2).withOpacity(0.2),
                  blurRadius: 8, spreadRadius: 1)],
              ),
              child: Icon(icon, color: isLogout ? Colors.red : const Color(0xFF1976D2), size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center,
              style: TextStyle(
                color: isLogout ? Colors.red : const Color(0xFF1976D2),
                fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 2, overflow: TextOverflow.ellipsis),
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