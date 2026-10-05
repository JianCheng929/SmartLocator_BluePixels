import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'onboarding_page.dart'; // your onboarding page
import 'package:firebase_core/firebase_core.dart';
// ← ADD
import 'package:hive_flutter/hive_flutter.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'main_page.dart';
import 'app_background.dart';
import 'notification_service.dart';
import 'tracking_page.dart';
import 'services/ble_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 并行执行，更快！
  await Future.wait([
    Firebase.initializeApp(),
    Hive.initFlutter(),
  ]);

  // Hive box 必须在 initFlutter 之后
  await Hive.openBox('lastSeen');

  // Notification 单独初始化
  await NotificationService.init(
    onNotificationTap: (payload) {
      if (payload == 'bt_page') {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => DeviceTrackingPage(
            deviceName: BleService().cachedItemName,
            photoUrl:   BleService().cachedPhotoUrl,
            initialPage: 1,
          ),
        ));
      } else if (payload == 'tracking_page') {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => DeviceTrackingPage(
            deviceName: BleService().cachedItemName,
            photoUrl:   BleService().cachedPhotoUrl,
            initialPage: 0,
          ),
        ));
      }
    },
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SmartLocatorApp(),
    ),
  );
}
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
class SmartLocatorApp extends StatelessWidget {
  const SmartLocatorApp({super.key});

  @override
Widget build(BuildContext context) {
  final themeProvider = Provider.of<ThemeProvider>(context);

  return MaterialApp(
    title: 'SmartLocator',
    debugShowCheckedModeBanner: false,
    theme: ThemeProvider.lightTheme,
    darkTheme: ThemeProvider.darkTheme,
    // ✅ 新
    themeMode: themeProvider.themeMode,
    home: const AuthGate(),
    navigatorKey: navigatorKey,
  );
}
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    // Small delay to let Firebase initialize
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Already logged in → go straight to MainPage
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainPage()),
      );
    } else {
      // Not logged in → show normal get started flow
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FrontPage()),
      );
    }
  }

@override
Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDark ? const Color(0xFF0D1B2A) : Colors.white;
  final textColor = isDark
      ? Colors.white.withOpacity(0.65)
      : Colors.grey.withOpacity(0.75);
  final smartColor = isDark
      ? const Color(0xFF4FC3F7)
      : const Color(0xFF0084FF);
  final locatorColor = isDark
      ? const Color(0xFFB0BEC5)
      : const Color(0xFF1A237E);

  return Scaffold(
    backgroundColor: bgColor,
    body: AnimatedContainer(  // ✅ 平滑过渡，不会闪
      duration: const Duration(milliseconds: 300),
      color: bgColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                      ClipRRect(
          borderRadius: BorderRadius.circular(16), // curved square
          child: Image.asset(
            'assets/images/bluepixels_icon.png',
            width: 64, height: 64,
            fit: BoxFit.cover,
          ),
        ),
              const SizedBox(width: 16),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Smart',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: smartColor,
                      ),
                    ),
                    TextSpan(
                      text: 'Locator',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: locatorColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: Text(
              'BY BLUEPIXELS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}

// ==================== FRONT PAGE (GET STARTED) ====================
class FrontPage extends StatefulWidget {
  const FrontPage({super.key});

  @override
  State<FrontPage> createState() => _FrontPageState();
}

class _FrontPageState extends State<FrontPage>
    with TickerProviderStateMixin {
  
  late AnimationController _waveController;
  late AnimationController _floatController;
  late AnimationController _entranceController;
  
  late Animation<double> _floatAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _floatController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(
        parent: _floatController,
        curve: Curves.easeInOutSine,
      ),
    );

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(begin: 80, end: 0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _floatController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // NAVIGATION TO ONBOARDING PAGE
  void _goToOnboardingPage() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const OnboardingPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;
          
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          
          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              
              // BIGGER Bluetooth Icon + Waves
              SizedBox(
                width: 320,
                height: 320,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_waveController, _floatController]),
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildWave(0.0, 0.15, 2.2),
                        _buildWave(0.33, 0.25, 1.8),
                        _buildWave(0.66, 0.35, 1.4),
                        
                        Transform.translate(
                          offset: Offset(0, _floatAnimation.value),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF0084FF),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0084FF).withOpacity(0.4),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                                BoxShadow(
                                  color: const Color(0xFF0084FF).withOpacity(0.2),
                                  blurRadius: 50,
                                  spreadRadius: 15,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.bluetooth,
                              size: 60,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              
              const Spacer(flex: 4),
              
              // SHORTER BUTTON
              AnimatedBuilder(
                animation: _entranceController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: Opacity(
                      opacity: _fadeAnimation.value,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 80),
                        child: SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _goToOnboardingPage, // NAVIGATION HERE
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0084FF),
                              foregroundColor: Colors.white,
                              elevation: 8,
                              shadowColor: const Color(0xFF0084FF).withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              "Get Started",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWave(double delay, double maxOpacity, double maxScale) {
    double progress = (_waveController.value - delay) % 1.0;
    if (progress < 0) progress += 1.0;
    
    double easedProgress = Curves.easeOutCubic.transform(progress);
    double scale = 1.0 + (easedProgress * (maxScale - 1.0));
    double opacity = (1.0 - easedProgress) * maxOpacity;

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF0084FF),
              width: 2.5,
            ),
            color: const Color(0xFF0084FF).withOpacity(opacity * 0.1),
          ),
        ),
      ),
    );
  }
}