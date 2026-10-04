import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task_item.dart';
import '../services/developer_diagnostics_service.dart';

/// The shipment exactly as the server sent it in /tasks (tokens masked),
/// to see every field available for building features.
Future<void> showShipmentRawSheet(BuildContext context, TaskItem task) {
  final text = DeveloperDiagnosticsService.pretty(task.raw);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'بيانات الشحنة من السيرفر\n${task.displayReference}  •  ${task.raw.length} حقل',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ بيانات الشحنة')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('نسخ'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  text,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
