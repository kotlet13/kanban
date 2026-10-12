import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared Jivie identity; Flutter retains each platform's navigation behavior.
ThemeData buildJivieTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF365BD9),
        brightness: brightness,
      ).copyWith(
        surface: isDark ? const Color(0xFF22242A) : const Color(0xFFFFFFFF),
        primary: isDark ? const Color(0xFFA8B9FF) : const Color(0xFF365BD9),
        onPrimary: isDark ? const Color(0xFF18234B) : Colors.white,
        onSurface: isDark ? const Color(0xFFF1F2F5) : const Color(0xFF202329),
        onSurfaceVariant: isDark
            ? const Color(0xFFAEB3BF)
            : const Color(0xFF626875),
        surfaceContainerLow: isDark
            ? const Color(0xFF24262D)
            : const Color(0xFFF4F5F8),
        surfaceContainerHigh: isDark ? const Color(0xFF22242A) : Colors.white,
        surfaceContainerHighest: isDark
            ? const Color(0xFF343740)
            : const Color(0xFFE9EBEF),
        primaryContainer: isDark
            ? const Color(0xFF2A334F)
            : const Color(0xFFEDF1FF),
        outlineVariant: isDark
            ? const Color(0xFF343740)
            : const Color(0xFFE9EBEF),
        tertiary: isDark ? const Color(0xFF64D2FF) : const Color(0xFF007DA3),
        onTertiary: isDark ? const Color(0xFF102D38) : Colors.white,
      );

  final scaffoldBackground = isDark
      ? const Color(0xFF17181C)
      : const Color(0xFFFFFFFF);
  final baseText = ThemeData(
    brightness: brightness,
    typography: Typography.material2021(platform: defaultTargetPlatform),
  ).textTheme;
  const controlCornerRadius = 12.0;

  OutlineInputBorder fieldBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: 1.1),
    );
  }

  return ThemeData(
    useMaterial3: true,
    platform: defaultTargetPlatform,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    // Keep Android predictive-back transitions and the iOS edge-back gesture.
    pageTransitionsTheme: const PageTransitionsTheme(),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: colorScheme.primary,
      scaffoldBackgroundColor: scaffoldBackground,
      barBackgroundColor: isDark
          ? const Color(0xFF22242A)
          : const Color(0xFFFFFFFF),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: isDark
          ? const Color(0xFF22242A)
          : const Color(0xFFFFFFFF),
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      toolbarHeight: 56,
      titleTextStyle: baseText.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      color: isDark ? colorScheme.surfaceContainerHigh : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
    ),
    textTheme: baseText.copyWith(
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.65,
        height: 1.15,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.35,
      ),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
      bodySmall: baseText.bodySmall?.copyWith(fontSize: 13, height: 1.4),
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF22242A) : Colors.white,
      border: fieldBorder(colorScheme.outlineVariant),
      enabledBorder: fieldBorder(colorScheme.outlineVariant),
      focusedBorder: fieldBorder(colorScheme.primary),
      errorBorder: fieldBorder(colorScheme.error),
      focusedErrorBorder: fieldBorder(colorScheme.error),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlCornerRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colorScheme.outlineVariant),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlCornerRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlCornerRadius),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      foregroundColor: colorScheme.onPrimary,
      backgroundColor: colorScheme.primary,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colorScheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.55),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      closeIconColor: colorScheme.onSurface,
      contentTextStyle: TextStyle(color: colorScheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
