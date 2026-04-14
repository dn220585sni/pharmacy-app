import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/pos_screen.dart';
import 'services/auth_service.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Logout active session when the app window is closed
  binding.addObserver(_AppCloseObserver());

  runApp(const PharmacyApp());
}

class _AppCloseObserver extends WidgetsBindingObserver {
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await AuthService.logout();
    return AppExitResponse.exit;
  }
}

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ФармаПОС',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F5F8),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1E7DC8),
          secondary: Color(0xFF1E7DC8),
          surface: Color(0xFFFFFFFF),
          error: Color(0xFFEF5350),
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1C1C2E)),
          bodyMedium: TextStyle(color: Color(0xFF6B7280)),
          bodySmall: TextStyle(color: Color(0xFF9CA3AF)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(const Color(0xFFD1D5DB)),
          radius: const Radius.circular(4),
          thickness: WidgetStateProperty.all(4),
        ),
      ),
      home: const PosScreen(),
    );
  }
}
