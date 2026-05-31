import 'package:flutter/material.dart';

/// Central design system for the app — "Industrial Blue + Amber".
///
/// Every screen reads its colors, card shapes, inputs and buttons from the
/// [AppTheme.light] ThemeData so the UI stays consistent. Screens should never
/// hardcode raw `Colors.blue` again — use `Theme.of(context).colorScheme` or the
/// brand constants below.

// --- Brand palette ---------------------------------------------------------
const Color kBrandBlue = Color(0xFF1B3A6B); // primary — deep professional blue
const Color kBrandBlueDark = Color(0xFF12294D); // gradient end / pressed
const Color kBrandBlueLight = Color(0xFF2E5AA0); // lighter accents
const Color kBrandAmber = Color(0xFFF5A623); // secondary — safety amber
const Color kBrandAmberDark = Color(0xFFD2870A);
const Color kSurface = Color(0xFFF7F9FC); // app background — soft white
const Color kCardSurface = Colors.white;
const Color kInk = Color(0xFF1A2233); // primary text
const Color kInkMuted = Color(0xFF63708A); // secondary text

/// Brand gradient used on auth/home headers and hero elements.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kBrandBlueLight, kBrandBlue, kBrandBlueDark],
);

/// Status colors for the report lifecycle (shared by StatusChip).
const Color kStatusPending = Color(0xFF8A94A6);
const Color kStatusAssigned = kBrandAmber;
const Color kStatusFixerDone = kBrandBlueLight;
const Color kStatusCompleted = Color(0xFF2E9E5B);

class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kBrandBlue,
      primary: kBrandBlue,
      onPrimary: Colors.white,
      secondary: kBrandAmber,
      onSecondary: const Color(0xFF3A2A05),
      surface: kCardSurface,
      onSurface: kInk,
      brightness: Brightness.light,
    );

    final baseText = ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: kSurface,
      visualDensity: VisualDensity.adaptivePlatformDensity,

      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4),
        titleLarge: baseText.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, color: kInk),
        titleMedium: baseText.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, color: kInk),
        bodyMedium: baseText.bodyMedium?.copyWith(color: kInk),
        bodySmall: baseText.bodySmall?.copyWith(color: kInkMuted),
        labelLarge: baseText.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: kBrandBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      cardTheme: CardThemeData(
        color: kCardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kBrandBlue.withValues(alpha: 0.06)),
        ),
        shadowColor: kBrandBlue.withValues(alpha: 0.10),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: kInkMuted),
        labelStyle: const TextStyle(color: kInkMuted),
        prefixIconColor: kInkMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kBrandBlue.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kBrandBlue.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBrandBlue, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD64545), width: 1.4),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kBrandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kBrandAmber,
          foregroundColor: const Color(0xFF3A2A05),
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kBrandBlue,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: kBrandBlue.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: kBrandBlue),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? kBrandBlue
                  : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.white : kInk),
          side: WidgetStatePropertyAll(
              BorderSide(color: kBrandBlue.withValues(alpha: 0.25))),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: kBrandBlue.withValues(alpha: 0.06),
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w600, color: kInk),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),

      dividerTheme: DividerThemeData(
        color: kBrandBlue.withValues(alpha: 0.08),
        thickness: 1,
        space: 24,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kInk,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kBrandAmber,
        foregroundColor: Color(0xFF3A2A05),
      ),

      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: kBrandBlue),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
