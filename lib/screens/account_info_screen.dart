import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_credentials.dart';

/// Everything SLS returned about the signed-in account at login, without
/// tokens or passwords.
class AccountInfoScreen extends StatelessWidget {
  final String token;
  const AccountInfoScreen({super.key, required this.token});

  static String _text(Object? value) {
    if (value == null) return '—';
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    final text = '$value'.trim();
    return text.isEmpty ? '—' : text;
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionCredentials.fromSavedSession(token);
    final profile = session.profile;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('معلومات الحساب'),
          actions: [
            if (profile.isNotEmpty)
              IconButton(
                tooltip: 'نسخ',
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(profile),
                  ));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ معلومات الحساب')),
                  );
                },
              ),
          ],
        ),
        body: profile.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'ما فيه معلومات محفوظة لهذا الحساب.\n'
                    'سجّل خروج وادخل مرة وحدة عشان تنحفظ اللي يرسله السيرفر.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (session.driverName.isNotEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(
                          session.driverName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('الاسم في SLS'),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'هذي البيانات كما أرسلها السيرفر عند الدخول (بدون التوكن وكلمة المرور).',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  for (final entry in profile.entries)
                    Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          entry.key,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: SelectableText(
                          _text(entry.value),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
