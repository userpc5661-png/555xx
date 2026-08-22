import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  void toggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void useSystemTheme() {
    _mode = ThemeMode.system;
    notifyListeners();
  }
}
