import 'package:flutter/material.dart';
import 'package:kavasam_mobile/screens/caller_screen.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';

void main() => runApp(const KavasamApp());

class KavasamApp extends StatelessWidget {
  const KavasamApp({super.key, this.bridge});

  final PhoneBridge? bridge;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0B1F3A);
    const blue = Color(0xFF176BCE);
    const teal = Color(0xFF0B7A69);
    const surface = Color(0xFFF4F7FB);
    const scheme = ColorScheme.light(
      primary: blue,
      onPrimary: Colors.white,
      secondary: teal,
      onSecondary: Colors.white,
      error: Color(0xFFBA1A1A),
      surface: Colors.white,
      onSurface: navy,
      surfaceContainerHighest: Color(0xFFE8EEF7),
      outline: Color(0xFFBCC7D8),
    );
    return MaterialApp(
      title: 'Kavasam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: surface,
        visualDensity: VisualDensity.standard,
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
          headlineSmall: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
          titleLarge: TextStyle(fontWeight: FontWeight.w900),
          titleMedium: TextStyle(fontWeight: FontWeight.w800),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: navy,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            side: BorderSide(color: Color(0xFFE4EAF2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE1E8F1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: blue, width: 2),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 0,
          height: 76,
          indicatorColor: Color(0xFFDCEAFF),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Color(0xFFD9E2EE)),
          shape: StadiumBorder(),
          // The color is required: a labelStyle without one leaves chip labels
          // with no resolved color, which paints white-on-white in release.
          labelStyle: TextStyle(color: navy, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: blue, size: 17),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        ),
      ),
      home: CallerScreen(bridge: bridge ?? PhoneBridge()),
    );
  }
}
