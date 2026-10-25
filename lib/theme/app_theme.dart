import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color Palette - Blue White Gradient Theme
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF42A5F5);
  static const Color accentCyan = Color(0xFF00BCD4);
  static const Color backgroundLight = Color(0xFFF4F7FC);
  static const Color surfaceWhite = Color(0xFFFFFFFF);

  // Status Colors
  static const Color emergencyRed = Color(0xFFE53935);
  static const Color warningOrange = Color(0xFFFB8C00);
  static const Color successGreen = Color(0xFF43A047);
  static const Color infoBlue = Color(0xFF1E88E5);

  // Glassmorphism & Shadow Constants
  static BoxDecoration glassDecoration({
    double borderRadius = 20.0,
    Color color = Colors.white,
    double opacity = 0.85,
    Color borderColor = Colors.white,
    double borderOpacity = 0.4,
  }) {
    return BoxDecoration(
      color: color.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor.withOpacity(borderOpacity),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: primaryDark.withOpacity(0.08),
          blurRadius: 20,
          spreadRadius: 2,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration gradientBackgroundDecoration = const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF0A2540),
        Color(0xFF0D47A1),
        Color(0xFF1976D2),
        Color(0xFF29B6F6),
      ],
      stops: [0.0, 0.35, 0.7, 1.0],
    ),
  );

  static BoxDecoration mainScreenBackground = const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFEBF3FA),
        Color(0xFFF4F7FC),
      ],
    ),
  );

  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.poppinsTextTheme();

    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: primaryLight,
        surface: surfaceWhite,
        background: backgroundLight,
        error: emergencyRed,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.bold,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: const Color(0xFF334155),
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: const Color(0xFF64748B),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryDark),
        titleTextStyle: TextStyle(
          color: primaryDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: primaryDark.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryLight.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryLight.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: emergencyRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: primaryDark.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
