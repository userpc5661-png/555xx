import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../services/navigation_service.dart';
import '../services/phone_action_service.dart';
import '../services/whatsapp_action_service.dart';
import '../widgets/location_correction_dialog.dart';
import 'shipment_status_screen.dart';

/// Shipment details only. Delivery is performed exclusively through the
/// status-update workflow so opening a shipment never starts the camera.
class ShipmentDeliveryScreen extends StatelessWidget {
  final TaskItem task;
  final String savedSession;
  final Future<void> Function()? onUpdated;

  const ShipmentDeliveryScreen({
    super.key,
    required this.task,
    required this.savedSession,
    this.onUpdated,
  });

  Future<void> _openWhatsApp(BuildContext context) async {
    final result = await WhatsAppActionService.openForTask(task);
    if (!context.mounted || result.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'تعذر فتح واتساب')),
    );
  }

  Future<void> _correctLocation(BuildContext context) async {
    final changed = await showLocationCorrectionDialog(context, task);
    if (!context.mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث موقع العميل محليًا على الخريطة')),
    );
    await onUpdated?.call();
  }

  Future<void> _openStatus(BuildContext context) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ShipmentStatusScreen(
          task: task,
          savedSession: savedSession,
          onUpdated: onUpdated,
        ),
      ),
    );
    if (updated == true && context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('بيانات الشحنة')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _Info(label: 'رقم الشحنة', value: task.displayReference),
                    _Info(label: 'اسم المتجر', value: task.displayStoreName),
                    _Info(label: 'اسم العميل', value: task.customerName),
                    _Info(label: 'رقم العميل', value: task.customerPhone),
                    _Info(label: 'العنوان', value: task.address),
                    _Info(label: 'الحالة', value: task.statusLabel),
                    if (task.codAmount != null && task.codAmount! > 0)
                      _Info(
                        label: 'المبلغ النقدي',
                        value: '${task.codAmount} ريال',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: task.customerPhone.trim().isEmpty
                        ? null
                        : () => PhoneActionService.call(task.customerPhone),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('اتصال'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: task.customerPhone.trim().isEmpty
                        ? null
                        : () => _openWhatsApp(context),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('واتساب'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: task.hasNavigableLocation
                        ? () => NavigationService.openTask(task)
                        : null,
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('ملاحة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _correctLocation(context),
                    icon: const Icon(Icons.edit_location_alt_rounded),
                    label: const Text('تصحيح الموقع'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => _openStatus(context),
              icon: const Icon(Icons.sync_alt_rounded),
              label: const Text('فتح تحديث الحالة'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اختيار “تم التسليم” والتحقق بالباركود ورمز OTP والإثبات '
              'تتم من داخل تحديث الحالة فقط.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(
              shown,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
