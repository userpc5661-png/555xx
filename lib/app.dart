import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/token_store.dart';
import 'theme/theme_controller.dart';

class SlsAssistantApp extends StatelessWidget {
  const SlsAssistantApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primaryColor =
        isDark ? const Color(0xFF00C853) : const Color(0xFF2E7D32);

    final scheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      brightness: brightness,
      surface: isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF),
      onSurface: isDark ? Colors.white : Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF8F9FA),
      appBarTheme: AppBarThemeData(
        centerTitle: true,
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: isDark ? const Color(0xFF121212) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark
              ? BorderSide(color: Colors.green.withValues(alpha: 0.1), width: 1)
              : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF1F3F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: isDark
              ? BorderSide(color: Colors.green.withValues(alpha: 0.2))
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        indicatorColor: primaryColor.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primaryColor);
          }
          return IconThemeData(color: isDark ? Colors.white70 : Colors.black54);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : (isDark ? Colors.white70 : Colors.black54),
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SLS Assistant Pro',
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: ThemeController.instance.mode,
          home: const SessionGate(),
        );
      },
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final TokenStore _store = TokenStore();
  late final Future<String?> _savedSession = _restoreSession();

  Future<String?> _restoreSession() async {
    try {
      final value = await _store.read();
      if (value == null || value.trim().isEmpty) return null;
      return value;
    } catch (_) {
      // A storage migration/device issue must not prevent opening the app.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _savedSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final session = snapshot.data;
        if (session != null && session.trim().isNotEmpty) {
          return HomeScreen(token: session);
        }
        return const LoginScreen();
      },
    );
  }
}
