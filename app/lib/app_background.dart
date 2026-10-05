import 'package:flutter/material.dart';
import 'app_background.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
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
        ),
      ),
      child: child,
    );
  }
}