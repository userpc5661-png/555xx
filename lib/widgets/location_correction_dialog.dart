import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../services/location_correction_service.dart';

Future<bool> showLocationCorrectionDialog(
    BuildContext context, TaskItem task) async {
  final controller = TextEditingController();
  var loading = false;
  final existing = await LocationCorrectionService.load(task);
  if (!context.mounted) return false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !loading,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('تصحيح موقع العميل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              enabled: !loading,
              keyboardType: TextInputType.url,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ألصق رابط Google Maps أو الإحداثيات',
                hintText: '24.7136, 46.6753',
              ),
            ),
            if (loading)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator()),
          ],
        ),
        actions: [
          TextButton(
              onPressed: loading ? null : () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          if (existing != null)
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      await LocationCorrectionService.restore(task);
                      if (context.mounted) Navigator.pop(context, true);
                    },
              child: const Text('الرجوع للموقع الأصلي'),
            ),
          FilledButton(
            onPressed: loading
                ? null
                : () async {
                    setState(() => loading = true);
                    final value =
                        await LocationCorrectionService.parse(controller.text);
                    if (!context.mounted) return;
                    if (value == null) {
                      setState(() => loading = false);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'تعذر استخراج الإحداثيات من الرابط، أدخل خط العرض وخط الطول يدويًا')));
                      return;
                    }
                    await LocationCorrectionService.save(task, value);
                    if (context.mounted) Navigator.pop(context, true);
                  },
            child: const Text('حفظ الموقع'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result ?? false;
}
