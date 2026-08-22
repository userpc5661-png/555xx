import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/developer_diagnostics_service.dart';

class DeveloperDiagnosticsScreen extends StatelessWidget {
  const DeveloperDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'Developer diagnostics are debug-only.');
    final service = DeveloperDiagnosticsService.instance;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تشخيص المطوّر'),
          actions: [
            IconButton(
              onPressed: service.clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'مسح السجل',
            ),
          ],
        ),
        body: ValueListenableBuilder<Map<String, String>>(
          valueListenable: service.context,
          builder: (context, values, _) {
            return ValueListenableBuilder<List<DiagnosticEntry>>(
              valueListenable: service.entries,
              builder: (context, entries, _) => ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'هذه الشاشة متاحة في وضع Debug فقط. التوكنات والكوكي '
                        'وكلمات المرور تُخفى تلقائيًا.',
                      ),
                    ),
                  ),
                  for (final item in values.entries)
                    _Section(title: item.key, value: item.value),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('لا توجد طلبات مسجلة بعد.')),
                    ),
                  for (final entry in entries.reversed)
                    _RequestCard(entry: entry),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final DiagnosticEntry entry;
  const _RequestCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final encoder = const JsonEncoder.withIndent('  ');
    String pretty(Object? value) {
      if (value == null) return '<empty>';
      try {
        return encoder.convert(value);
      } catch (_) {
        return value.toString();
      }
    }

    return Card(
      child: ExpansionTile(
        title: Text('${entry.method}  ${entry.statusCode ?? '—'}'),
        subtitle: Text(entry.url, textDirection: TextDirection.ltr),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          _Section(title: 'Payload', value: pretty(entry.payload)),
          _Section(title: 'Response', value: pretty(entry.response)),
          if (entry.error != null)
            _Section(title: 'Exception', value: entry.error!),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String value;
  const _Section({required this.title, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              SelectableText(
                value,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      );
}
