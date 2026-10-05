import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'isDarkMode';
  bool _isDark = false;
  bool _isLoaded = false;  // ✅ 加这行

  bool get isDark => _isDark;
  bool get isLoaded => _isLoaded;  // ✅ 加这行
  bool get isDarkMode => _isDark; // alias used by account/edit pages
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggleTheme() => toggle(); // alias

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool(_key) ?? false;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDark);
    notifyListeners();
  }

  // ── Light theme ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1976D2),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.white,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF323232),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    cardColor: Colors.white,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
    ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
  );

  // ── Dark theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1976D2),
      brightness: Brightness.dark,
      surface: const Color(0xFF0D1B2A),
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFF0D1B2A),
    // FIX image 5: snackbar dark background, white text — not white background
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF1E3A5F),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    cardColor: const Color(0xFF1A2D42),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF1E3A5F),
    ),
    dividerColor: Colors.white24, dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF1A2D42)),
  );
}