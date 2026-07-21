import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task_item.dart';
import '../services/navigation_service.dart';
import '../screens/shipment_delivery_screen.dart';
import '../screens/shipment_status_screen.dart';
import '../services/phone_action_service.dart';
import '../services/local_contact_controller.dart';
import '../services/local_contact_store.dart';
import '../utils/phone_number_utils.dart';

class TaskCard extends StatelessWidget {
  final TaskItem task;
  final String? savedSession;
  final Future<void> Function()? onUpdated;
  final LocalContactController? contactController;
  final LocalContactData? contactData;

  const TaskCard({
    super.key,
    required this.task,
    this.savedSession,
    this.onUpdated,
    this.contactController,
    this.contactData,
  });

  String get _storageKey => '${task.referenceNumber}_${task.id}';

  Future<void> _call(BuildContext context) async {
    if (contactController != null) {
      final opened = await contactController!.handleCall(
        _storageKey,
        task.customerPhone,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رقم الهاتف غير صالح أو تعذر فتح الاتصال'),
          ),
        );
      }
      return;
    }
    final opened = await PhoneActionService.call(task.customerPhone);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('رقم الهاتف غير صالح أو تعذر فتح الاتصال')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    if (contactController != null) {
      final opened = await contactController!.handleWhatsApp(
        _storageKey,
        task.customerPhone,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر فتح واتساب. تحقق من رقم العميل أو تثبيت واتساب.',
            ),
          ),
        );
      }
      return;
    }
    final opened = await PhoneActionService.openWhatsApp(task.customerPhone);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح واتساب. تحقق من رقم العميل أو تثبيت واتساب.'),
        ),
      );
    }
  }

  Future<void> _openLocation(BuildContext context) async {
    final opened = await NavigationService.openTask(task);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الخرائط أو لا يوجد موقع متاح')),
      );
    }
  }

  Future<void> _copyReference(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: task.displayReference));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ رقم الشحنة')),
      );
    }
  }

  Future<void> _openDelivery(BuildContext context) async {
    final session = savedSession;
    if (session == null || session.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('بيانات الجلسة غير متوفرة لإتمام التسليم')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentDeliveryScreen(
          task: task,
          savedSession: session,
          onUpdated: onUpdated,
        ),
      ),
    );
  }

  Future<void> _openStatus(BuildContext context) async {
    final session = savedSession;
    if (session == null || session.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات الجلسة غير متوفرة لتحديث الحالة')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShipmentStatusScreen(
          task: task,
          savedSession: session,
          onUpdated: onUpdated,
        ),
      ),
    );
  }

  Future<void> _pickCustomReminder(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );
    if (time == null) return;

    final target =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (target.isBefore(DateTime.now())) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار وقت في المستقبل')),
        );
      }
      return;
    }

    await contactController?.setCustomReminder(_storageKey, target);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedPhone =
        PhoneNumberUtils.normalizeSaudiMobile(task.customerPhone);
    final isCod = task.paymentKind == PaymentKind.cashOnDelivery;
    final isContacted = contactData?.status == 'contacted';
    final hasReminder = contactData?.reminderAt != null;

    String? reminderText;
    bool needsFollowUp = false;
    if (hasReminder) {
      final diff = contactData!.reminderAt!.difference(DateTime.now());
      if (diff.isNegative) {
        reminderText = 'يحتاج متابعة الآن';
        needsFollowUp = true;
      } else {
        if (diff.inHours > 0) {
          reminderText = 'تذكير خلال ${diff.inHours} ساعة';
        } else {
          reminderText = 'تذكير خلال ${diff.inMinutes} دقيقة';
        }
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: needsFollowUp
              ? Colors.red.withValues(alpha: 0.5)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.05)),
          width: needsFollowUp ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isContacted)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      contactData?.type == 'whatsapp'
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.phone_callback_rounded,
                      size: 14,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تم التواصل عبر ${contactData?.type == 'whatsapp' ? 'واتساب' : 'اتصال'}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold),
                    ),
                    if (contactData?.timestamp != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${TimeOfDay.fromDateTime(contactData!.timestamp!).format(context)})',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                    const Spacer(),
                    if (reminderText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: needsFollowUp
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          reminderText,
                          style: TextStyle(
                            fontSize: 10,
                            color: needsFollowUp ? Colors.red : Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.inventory_2_rounded,
                      color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              task.displayReference,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _copyReference(context),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'نسخ رقم الشحنة',
                          ),
                        ],
                      ),
                      Text(
                        task.displayStoreName,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(task: task),
              ],
            ),
            const SizedBox(height: 20),
            if (task.customerName.isNotEmpty)
              _ModernInfoRow(
                  icon: Icons.person_rounded, text: task.customerName),
            if (task.customerPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ModernInfoRow(
                    icon: Icons.phone_rounded, text: task.customerPhone),
              ),
            if (task.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ModernInfoRow(
                    icon: Icons.location_on_rounded, text: task.address),
              ),
            if (isCod && task.codAmount != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_rounded,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    const Text('المطلوب تحصيله:',
                        style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text(
                      '${task.codAmount!.toStringAsFixed(2)} ر.س',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: task.progress == TaskProgress.remaining
                        ? () => _openDelivery(context)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('تسليم'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed:
                      normalizedPhone == null ? null : () => _call(context),
                  icon: const Icon(Icons.call_rounded),
                  tooltip: 'اتصال',
                ),
                IconButton.filledTonal(
                  onPressed: () => _openLocation(context),
                  icon: const Icon(Icons.navigation_rounded),
                ),
                IconButton.filledTonal(
                  onPressed: () => _openWhatsApp(context),
                  icon: const Icon(Icons.chat_rounded, color: Colors.green),
                ),
                IconButton.filledTonal(
                  onPressed: () => _openStatus(context),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
                if (isContacted)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.history_toggle_off_rounded,
                        color: Colors.blue),
                    onSelected: (val) {
                      if (val == '30m') {
                        contactController?.setReminder(
                            _storageKey, const Duration(minutes: 30));
                      }
                      if (val == '1h') {
                        contactController?.setReminder(
                            _storageKey, const Duration(hours: 1));
                      }
                      if (val == 'custom') _pickCustomReminder(context);
                      if (val == 'cancel') {
                        contactController?.cancelReminder(_storageKey);
                      }
                      if (val == 'reset') {
                        contactController?.moveToNotContacted(_storageKey);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: '30m', child: Text('تذكير بعد 30 دقيقة')),
                      const PopupMenuItem(
                          value: '1h', child: Text('تذكير بعد ساعة')),
                      const PopupMenuItem(
                          value: 'custom', child: Text('تحديد وقت مخصص')),
                      if (hasReminder)
                        const PopupMenuItem(
                            value: 'cancel', child: Text('إلغاء التذكير')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('إعادة إلى "لم يتم التواصل"',
                            style: TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TaskItem task;
  const _StatusBadge({required this.task});

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.progress == TaskProgress.completed;
    final color = isCompleted ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isCompleted ? 'مكتمل' : 'قيد التنفيذ',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ModernInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ModernInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
