import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/task_item.dart';
import '../services/label_address_resolver.dart';
import '../services/label_address_store.dart';
import '../services/label_ocr_service.dart';
import '../utils/suspicious_addresses.dart';
import '../widgets/location_correction_dialog.dart';

/// Photograph shipment labels one after another: each photo's shipment
/// number finds the shipment, its National Address is read and becomes the
/// customer's location on this device. Nothing is sent to SLS.
class LabelBatchScreen extends StatefulWidget {
  final List<TaskItem> tasks;
  final String savedSession;

  const LabelBatchScreen({
    super.key,
    required this.tasks,
    required this.savedSession,
  });

  @override
  State<LabelBatchScreen> createState() => _LabelBatchScreenState();
}

class _LabelBatchScreenState extends State<LabelBatchScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _lastMessage;
  bool _lastOk = true;

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  TaskItem? _taskForAwbs(List<String> awbs) {
    for (final awb in awbs) {
      for (final task in widget.tasks) {
        final keys = {
          _digits(task.realAwb),
          _digits(task.displayReference),
          _digits(task.referenceNumber),
        }..remove('');
        if (keys.contains(awb)) return task;
      }
    }
    return null;
  }

  List<TaskItem> get _ordered {
    final suspicious = widget.tasks.where(SuspiciousAddresses.isSuspicious);
    final others = widget.tasks.where((t) => !SuspiciousAddresses.isSuspicious(t));
    return [...suspicious, ...others];
  }

  Future<TaskItem?> _pickTask() => showDialog<TaskItem>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('لم أقرأ رقم الشحنة. أي شحنة هذه؟'),
          children: [
            for (final task in _ordered)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, task),
                child: Text(
                  '${task.customerName.isEmpty ? task.displayReference : task.customerName}'
                  '\n${task.displayReference}',
                ),
              ),
          ],
        ),
      );

  Future<void> _scanNext() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final scan = await LabelOcrService.readLabel(photo.path);
      var task = _taskForAwbs(scan.awbCandidates);
      if (task == null) {
        setState(() => _busy = false);
        task = await _pickTask();
        if (task == null || !mounted) return;
        setState(() => _busy = true);
      }
      var chosen = await customerShortFromLabel(
        task,
        scan,
        savedSession: widget.savedSession,
      );
      if (!mounted) return;
      if (chosen == null && scan.shortAddresses.isNotEmpty) {
        setState(() => _busy = false);
        chosen = await chooseLabelAddress(context, scan.shortAddresses);
        if (!mounted) return;
        setState(() => _busy = true);
      }
      final name = task.customerName.isEmpty
          ? task.displayReference
          : task.customerName;
      if (chosen == null) {
        _show('لم أقرأ العنوان الوطني لـ $name. قرّب الكاميرا وصوّر مرة أخرى.', false);
        return;
      }
      final location = await applyLabelAddress(task, chosen);
      _show(
        location == null
            ? '$name: حُفظ العنوان $chosen، لكن الجوال لم يحدد موقعه.'
            : '✓ $name: $chosen — تم تحديد الموقع',
        location != null,
      );
    } catch (error) {
      _show('تعذر قراءة الصورة: $error', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message, bool ok) {
    if (!mounted) return;
    setState(() {
      _lastMessage = message;
      _lastOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('العناوين من البوالص')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : _scanNext,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_rounded),
          label: Text(_busy ? 'جارٍ القراءة…' : 'صوّر بوليصة'),
        ),
        body: ValueListenableBuilder<Map<String, String>>(
          valueListenable: LabelAddressStore.instance.values,
          builder: (context, labels, _) {
            final tasks = _ordered;
            final suspicious =
                tasks.where(SuspiciousAddresses.isSuspicious).toList();
            final fixed = suspicious
                .where((t) => LabelAddressStore.instance.forTask(t) != null)
                .length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'صوّر البوالص واحدة بعد الأخرى. البرنامج يقرأ رقم الشحنة '
                      'والعنوان الوطني للعميل، ويحدد موقعه على هذا الجهاز.\n'
                      'العناوين المكررة المصححة: $fixed من ${suspicious.length}',
                    ),
                  ),
                ),
                if (_lastMessage != null)
                  Card(
                    color: (_lastOk ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _lastMessage!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                for (final task in tasks)
                  _row(task, LabelAddressStore.instance.forTask(task)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(TaskItem task, String? label) {
    final suspicious = SuspiciousAddresses.isSuspicious(task);
    final color = label != null
        ? Colors.green
        : suspicious
            ? Colors.red
            : Colors.grey;
    return ListTile(
      leading: Icon(
        label != null
            ? Icons.check_circle
            : suspicious
                ? Icons.warning_amber_rounded
                : Icons.radio_button_unchecked,
        color: color,
      ),
      title: Text(task.customerName.isEmpty ? task.displayReference : task.customerName),
      subtitle: Text(
        label != null
            ? 'من البوليصة: $label'
            : suspicious
                ? 'عنوان مكرر لعدة عملاء — يحتاج تصوير'
                : task.displayReference,
        style: TextStyle(color: color),
      ),
    );
  }
}
