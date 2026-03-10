import 'package:flutter/material.dart';

// Cyberpunk color palette
const Color kCyberPurple = Color(0xFF7B2CBF);
const Color kCyberPink = Color(0xFFFF006E);
const Color kCyberCyan = Color(0xFF00F5FF);
const Color kCyberGreen = Color(0xFF39FF14);
const Color kCyberOrange = Color(0xFFFF6D00);
const Color kDarkBg = Color(0xFF0a0a1a);
const Color kCardBg = Color(0xFF1a1a2e);

ThemeData buildCyberpunkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.dark(
      primary: kCyberCyan,
      secondary: kCyberPink,
      tertiary: kCyberPurple,
      surface: kCardBg,
      error: kCyberPink,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kCyberCyan.withAlpha(51),
        foregroundColor: kCyberCyan,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kCyberCyan,
        foregroundColor: Colors.black,
        elevation: 8,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCardBg.withAlpha(128),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kCyberCyan.withAlpha(77)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kCyberCyan.withAlpha(77)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: kCyberCyan, width: 2),
      ),
      labelStyle: const TextStyle(color: kCyberCyan),
      hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    iconTheme: const IconThemeData(color: kCyberCyan),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
      displayMedium: TextStyle(fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontWeight: FontWeight.bold),
      titleLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.15),
    ),
  );
}

// Cyberpunk gradient background
Widget cyberpunkBackground({required Widget child}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0a0a1a),
          Color(0xFF1a0a2e),
          Color(0xFF0f0a1a),
        ],
      ),
    ),
    child: child,
  );
}

// Glossy card with glassmorphism effect
Widget cyberpunkCard({
  required Widget child,
  bool selected = false,
  VoidCallback? onTap,
}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kCyberCyan.withAlpha(77),
                kCyberPurple.withAlpha(51),
              ],
            )
          : null,
      border: Border.all(
        color: selected ? kCyberCyan : kCyberCyan.withAlpha(77),
        width: selected ? 2 : 1,
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: kCyberCyan.withAlpha(77),
                blurRadius: 20,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: kCyberPink.withAlpha(51),
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ]
          : null,
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kCardBg.withAlpha(153),
                kCardBg.withAlpha(102),
              ],
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

// Neon text with gradient
Widget neonText(String text, {double fontSize = 18, FontWeight fontWeight = FontWeight.bold}) {
  return ShaderMask(
    shaderCallback: (bounds) => const LinearGradient(
      colors: [kCyberCyan, kCyberPink],
    ).createShader(bounds),
    child: Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: fontSize > 16 ? 2 : 0.5,
        color: Colors.white,
      ),
    ),
  );
}
