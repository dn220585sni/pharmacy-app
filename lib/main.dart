import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/pos_screen.dart';
import 'services/auth_service.dart';
import 'services/prro_queue.dart';
import 'services/prro_service.dart';
import 'services/registry_config.dart';
import 'services/shift_service.dart';
import 'widgets/shift_end_dialog.dart';

/// Глобальний navigator — щоб показувати попап завершення зміни з обсервера
/// закриття вікна (де немає звичайного BuildContext).
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Per-аптека конфіг із реєстру ZSMU\Farm (baseUrl з MAddr, код каси) — до API.
  RegistryConfig.load();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Logout active session when the app window is closed
  binding.addObserver(_AppCloseObserver());

  // ПРРО: підняти кешований токен і чергу відкладених чеків.
  // Спроба flush у фоні — якщо мережа є, відкладені чеки відразу пушнуться.
  unawaited(() async {
    await PrroService.loadCachedToken();
    await PrroQueue.load();
    if (PrroQueue.count > 0) await PrroQueue.flush();
    // Відновити стан зміни з РРО (щоб рестарт посеред дня не робив авто-Z і
    // пропонував Z при виході). Дедуплікується з викликом у pos_screen.
    await ShiftService.ensureRestored();
  }());

  runApp(const PharmacyApp());
}

class _AppCloseObserver extends WidgetsBindingObserver {
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // Якщо зміна відкрита — спитати про завершення (Z-звіт) перед виходом.
    if (ShiftService.state.isOpen) {
      // Підтягнути реальні суми (готівка/чеки) з xReport перед діалогом.
      await ShiftService.refreshTotals();
      final ctx = navigatorKey.currentContext; // свіжий контекст після await
      if (ctx != null && ctx.mounted) {
        final choice = await showShiftEndDialog(ctx);
        if (choice == ShiftEndChoice.cancel) return AppExitResponse.cancel;
        if (choice == ShiftEndChoice.closeShift) {
          await ShiftService.closeShift();
        }
        // justExit → вийти без Z-звіту (напр. перезапуск програми).
      }
    }
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
      navigatorKey: navigatorKey,
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
