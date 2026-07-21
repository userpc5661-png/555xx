import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import 'developer_diagnostics_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          children: [
            ListTile(
              leading: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              title: Text(dark ? 'الوضع الفاتح' : 'الوضع الداكن'),
              onTap: () => ThemeController.instance.toggle(context),
            ),
            if (kDebugMode)
              ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('تشخيص المطوّر'),
                subtitle: const Text('متاح في وضع Debug فقط'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeveloperDiagnosticsScreen(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
