import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scan_models.dart';
import '../models/task_item.dart';
import '../services/navigation_service.dart';
import '../screens/shipment_status_screen.dart';
import '../screens/scanner_screen.dart';
import '../services/phone_action_service.dart';
import '../services/scan_api_service.dart';
import '../services/sms_action_service.dart';
import '../services/whatsapp_action_service.dart';
import '../services/local_contact_controller.dart';
import '../services/local_contact_store.dart';
import '../services/local_shipment_status_store.dart';
import '../utils/phone_number_utils.dart';

class TaskCard extends StatelessWidget {
  final TaskItem task;
  final String? savedSession;
  final Future<void> Function()? onUpdated;
  final LocalContactController? contactController;
  final LocalContactData? contactData;
  final LocalShipmentStatus? localStatus;
  final Future<void> Function()? onLocalStatusChanged;

  const TaskCard({
    super.key,
    required this.task,
    this.savedSession,
    this.onUpdated,
    this.contactController,
    this.contactData,
    this.localStatus,
    this.onLocalStatusChanged,
  });

  String get _storageKey => '${task.referenceNumber}_${task.id}';

  Future<void> _call(BuildContext context) async {
    final opened = contactController != null
        ? await contactController!.handleCall(_storageKey, task.customerPhone)
        : await PhoneActionService.call(task.customerPhone);
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم الهاتف غير صالح أو تعذر فتح الاتصال'),
        ),
      );
      return;
    }
    if (contactController == null) return;

    final outcome = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'نتيجة الاتصال',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('هل أجاب العميل؟'),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext, 'no_answer'),
                      child: const Text(
                        'لم يجيب',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, 'answered'),
                      child: const Text('أجاب العميل'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (outcome != null) {
      await contactController!.setOutcome(_storageKey, outcome);
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final result = await WhatsAppActionService.openForTask(task);
    if (!context.mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'تعذر فتح واتساب')),
      );
      return;
    }
    if (contactController != null) {
      await contactController!.setOutcome(
        _storageKey,
        'answered',
        type: 'whatsapp',
      );
    }
  }

  Future<void> _openSms(BuildContext context) async {
    final result = await SmsActionService.openForTask(task);
    if (!context.mounted || result.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'تعذر فتح الرسائل')),
    );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم نسخ رقم الشحنة')));
    }
  }

  Future<void> _openLocalStatusDialog(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تسجيل حالة محلياً (تخزين محلي)',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'هذه الحالة تحفظ في جهازك فقط وتستبعد الشحنة من الخريطة دون إرسالها لسيرفر SLS.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Icon(Icons.cancel_outlined, color: Colors.white),
                ),
                title: const Text('العميل ألغى الطلبية'),
                onTap: () => Navigator.pop(sheetContext, 'customer_cancelled'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.event_repeat_rounded, color: Colors.white),
                ),
                title: const Text('العميل أعاد الجدولة'),
                onTap: () => Navigator.pop(sheetContext, 'rescheduled'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(
                    Icons.wrong_location_outlined,
                    color: Colors.white,
                  ),
                ),
                title: const Text('الموقع غير صحيح / غير دقيق'),
                onTap: () => Navigator.pop(sheetContext, 'wrong_location'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueGrey,
                  child: Icon(
                    Icons.phone_disabled_outlined,
                    color: Colors.white,
                  ),
                ),
                title: const Text('رقم الهاتف خاطئ'),
                onTap: () => Navigator.pop(sheetContext, 'wrong_phone'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.phone_missed_rounded, color: Colors.white),
                ),
                title: const Text('العميل لم يجب'),
                onTap: () => Navigator.pop(sheetContext, 'no_answer'),
              ),
              if (localStatus != null) ...[
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.restore_rounded, color: Colors.white),
                  ),
                  title: const Text(
                    'إلغاء الحالة المحلية واستعادة الشحنة للخريطة',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'clear'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    if (choice == 'clear') {
      await LocalShipmentStatusStore.instance.removeStatus(_storageKey);
    } else {
      await LocalShipmentStatusStore.instance.setStatus(_storageKey, choice);
      if (choice == 'no_answer' && contactController != null) {
        await contactController!.setOutcome(_storageKey, 'no_answer');
      }
    }

    if (onLocalStatusChanged != null) {
      await onLocalStatusChanged!();
    } else if (onUpdated != null) {
      await onUpdated!();
    }
  }

  Future<void> _openStatus(BuildContext context) async {
    final session = savedSession;
    if (session == null || session.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات الجلسة غير متوفرة لتحديث الحالة')),
      );
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تحديث الحالة',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.check_rounded, color: Colors.white),
                ),
                title: const Text('تم التوصيل (رسمي)'),
                subtitle: const Text('مسح الشحنة ثم OTP عند الحاجة'),
                onTap: () => Navigator.pop(sheetContext, 'delivered'),
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.close_rounded, color: Colors.white),
                ),
                title: const Text('لم يتم التوصيل (رسمي)'),
                subtitle: const Text('اختيار السبب وإرفاق صورة إثبات'),
                onTap: () => Navigator.pop(sheetContext, 'not_delivered'),
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: Icon(
                    Icons.bookmark_outline_rounded,
                    color: Colors.white,
                  ),
                ),
                title: const Text('تسجيل حالة محلياً'),
                subtitle: const Text(
                  'تخزين محلي واستبعاد من الخريطة دون إرسال للسيرفر',
                ),
                onTap: () => Navigator.pop(sheetContext, 'local_status'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'local_status') {
      await _openLocalStatusDialog(context);
      return;
    }

    final api = ScanApiService(savedSession: session);
    if (choice == 'delivered') {
      final shipment = await Navigator.of(context).push<ScannedShipment>(
        MaterialPageRoute(
          builder: (_) => ScannerScreen(token: session, verificationTask: task),
        ),
      );
      if (shipment == null || !context.mounted) return;

      // Continue through the exact same status flow used by the smart
      // scanner. This preserves the real status_code, status_label, OTP and
      // COD fields returned by the shipment lookup endpoint.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShipmentStatusScreen(
            task: TaskItem.fromJson(shipment.raw),
            savedSession: session,
            awbOverride: shipment.actualAwb,
            onUpdated: onUpdated,
            mode: ShipmentStatusMode.all,
          ),
        ),
      );
      return;
    }

    // Not Delivered flow: Fetch the authoritative shipment data directly
    // without opening the camera UI.
    final awb = task.realAwb;
    debugPrint('NOT DELIVERED AWB: $awb');

    try {
      final shipment = await api.scanOrder(awb);
      debugPrint('SCAN RAW KEYS: ${shipment.raw.keys}');
      debugPrint(
        'DRIVER STATUS LABELS: ${shipment.raw['driver_status_labels']}',
      );

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShipmentStatusScreen(
            task: TaskItem.fromJson(shipment.raw),
            savedSession: session,
            awbOverride: shipment.actualAwb,
            onUpdated: onUpdated,
            mode: ShipmentStatusMode.all,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر جلب خيارات تحديث الحالة: $e')),
      );
    }
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

    final target = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
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
    final normalizedPhone = PhoneNumberUtils.normalizeSaudiMobile(
      task.customerPhone,
    );
    final isCod = task.paymentKind == PaymentKind.cashOnDelivery;
    final isAnswered = contactData?.status == 'answered';
    final isNoAnswer = contactData?.status == 'no_answer';
    final isContacted = isAnswered || isNoAnswer;
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
            if (localStatus != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bookmark_remove_rounded,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'حالة محلية: ${localStatus!.label}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const Text(
                            'مستبعدة من الخريطة النشطة محلياً فقط',
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(60, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        await LocalShipmentStatusStore.instance.removeStatus(
                          _storageKey,
                        );
                        if (onLocalStatusChanged != null) {
                          await onLocalStatusChanged!();
                        } else if (onUpdated != null) {
                          await onUpdated!();
                        }
                      },
                      icon: const Icon(Icons.restore_rounded, size: 14),
                      label: const Text(
                        'استعادة',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
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
                      color: isNoAnswer ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isNoAnswer ? 'العميل لم يجيب' : 'العميل أجاب',
                      style: TextStyle(
                        fontSize: 11,
                        color: isNoAnswer ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (contactData?.timestamp != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${TimeOfDay.fromDateTime(contactData!.timestamp!).format(context)})',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (reminderText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
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
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: Colors.green,
                  ),
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
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
                icon: Icons.person_rounded,
                text: task.customerName,
              ),
            if (task.customerPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ModernInfoRow(
                  icon: Icons.phone_rounded,
                  text: task.customerPhone,
                ),
              ),
            if (task.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ModernInfoRow(
                  icon: Icons.location_on_rounded,
                  text: task.address,
                ),
              ),
            if (isCod && task.codAmount != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.payments_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'المطلوب تحصيله:',
                      style: TextStyle(fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${task.codAmount!.toStringAsFixed(2)} ر.س',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange,
                      ),
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
                        ? () => _openStatus(context)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.sync_alt_rounded, size: 18),
                    label: const Text('تحديث الحالة'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: normalizedPhone == null
                      ? null
                      : () => _call(context),
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
                  tooltip: 'واتساب',
                ),
                PopupMenuButton<String>(
                  tooltip: 'إجراءات إضافية',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (value) async {
                    if (value == 'sms') await _openSms(context);
                    if (value == 'local_status' && context.mounted) {
                      await _openLocalStatusDialog(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'sms',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.sms_outlined),
                        title: Text('إرسال رسالة SMS'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'local_status',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.bookmark_add_outlined),
                        title: Text('تسجيل حالة محلياً'),
                      ),
                    ),
                  ],
                ),
                if (isContacted)
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.history_toggle_off_rounded,
                      color: Colors.blue,
                    ),
                    onSelected: (val) {
                      if (val == '30m') {
                        contactController?.setReminder(
                          _storageKey,
                          const Duration(minutes: 30),
                        );
                      }
                      if (val == '1h') {
                        contactController?.setReminder(
                          _storageKey,
                          const Duration(hours: 1),
                        );
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
                        value: '30m',
                        child: Text('تذكير بعد 30 دقيقة'),
                      ),
                      const PopupMenuItem(
                        value: '1h',
                        child: Text('تذكير بعد ساعة'),
                      ),
                      const PopupMenuItem(
                        value: 'custom',
                        child: Text('تحديد وقت مخصص'),
                      ),
                      if (hasReminder)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('إلغاء التذكير'),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text(
                          'إعادة إلى "لم يتم التواصل"',
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
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
