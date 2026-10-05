import 'package:flutter/material.dart';
import 'auth_intro_page.dart';
import 'app_background.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  
  late PageController _pageController;
  int _currentPage = 0;
  final int _totalPages = 2; // Just 2 pages: Page1 (Bluetooth) + Page2 (Alert)

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Finished onboarding - go to login or home
      _finishOnboarding();
    }
  }

    void _finishOnboarding() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const AuthIntroPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          var tween = Tween(begin: const Offset(0.0, 1.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(opacity: animation, child: child),
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
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              
              // PAGE CONTENT - Modern smooth transitions (NOT slide!)
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // PAGE 1: Bluetooth (Your original content)
                    _buildPage1(),
                    // PAGE 2: Alert (Your original content)
                    _buildPage2(),
                  ],
                ),
              ),
              
              // FIXED BOTTOM NAVIGATION (Indicators don't slide!)
              Padding(
                padding: const EdgeInsets.only(bottom: 40, left: 30, right: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ANIMATED INDICATORS (Stay in place, just change width)
                    Row(
                      children: [
                        _buildIndicator(0),
                        const SizedBox(width: 8),
                        _buildIndicator(1),
                      ],
                    ),
                    
                    // NEXT / DONE BUTTON
                    _currentPage == 0 ? _buildNextButton() : _buildDoneButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== PAGE 1: BLUETOOTH (Your original design) ====================
  Widget _buildPage1() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.8 + (0.2 * value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  
                  // Bluetooth Icon with pulse
                  _buildAnimatedIcon(
                    icon: Icons.bluetooth_searching_rounded,
                    bgColor: const Color(0xFFE3F2FD),
                    iconColor: const Color(0xFF0084FF),
                    glowColor: const Color(0xFF0084FF),
                  ),
                  
                  const SizedBox(height: 50),
                  
                  // Title
                  const Text(
                    'Bluetooth Indoor Tracking',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Description
                  const Text(
                    'Automatically allow the owner to quickly know the location of tracked items (floor levels + approximate distance)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF546E7A),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== PAGE 2: ALERT (Your original design) ====================
  Widget _buildPage2() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.8 + (0.2 * value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  
                  // Alert Icon with pulse
                  _buildAnimatedIcon(
                    icon: Icons.notifications_active_rounded,
                    bgColor: const Color(0xFFFFF3E0),
                    iconColor: const Color(0xFFFF8F00),
                    glowColor: const Color(0xFFFFB74D),
                  ),
                  
                  const SizedBox(height: 50),
                  
                  // Title
                  const Text(
                    'Alert System Provided',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Description
                  const Text(
                    'No worries. Remind the owner how far you stay with your items!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF546E7A),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== SHARED WIDGETS ====================
  
  Widget _buildAnimatedIcon({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required Color glowColor,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 1.05),
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(0.3),
                  blurRadius: 40 * scale,
                  spreadRadius: 10 * scale,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 100,
              color: iconColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildIndicator(int index) {
    bool isActive = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      width: isActive ? 24 : 8,
      height: 4,
      decoration: BoxDecoration(
        color: isActive 
            ? const Color(0xFF1976D2) 
            : const Color(0xFF1976D2).withOpacity(0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildNextButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _nextPage,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1976D2).withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_forward_ios_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildDoneButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _finishOnboarding,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 120,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C853), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Start',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}