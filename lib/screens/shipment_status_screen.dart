import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/task_item.dart';
import '../services/developer_diagnostics_service.dart';
import '../services/phone_action_service.dart';
import '../services/scan_api_service.dart';
import '../services/whatsapp_action_service.dart';
import '../widgets/location_correction_dialog.dart';
import 'scanner_screen.dart';

class ShipmentStatusScreen extends StatefulWidget {
  final TaskItem task;
  final String savedSession;
  final Future<void> Function()? onUpdated;

  const ShipmentStatusScreen({
    super.key,
    required this.task,
    required this.savedSession,
    this.onUpdated,
  });

  @override
  State<ShipmentStatusScreen> createState() => _ShipmentStatusScreenState();
}

class _ShipmentStatusScreenState extends State<ShipmentStatusScreen> {
  static const _labels = <String, String>{
    'Delivered': 'تم التسليم',
    'Consignee is not answering': 'العميل لا يجيب',
    'Consignee refused the shipment': 'العميل رفض الشحنة',
    'Unclear National Address': 'العنوان الوطني غير واضح',
    'Consignee wrong number': 'رقم العميل خاطئ',
    'consignee reschedule the delivery': 'العميل أعاد جدولة الاستلام',
    'Failed to Attempt': 'تعذر التوصيل',
  };

  late final ScanApiService _api;
  final _nationalAddress = TextEditingController();
  final _otp = TextEditingController();
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _options = const [];
  Map<String, dynamic>? _selected;
  XFile? _image;
  DateTime? _rescheduleAt;
  bool _deliveryVerified = false;
  bool _cashCollected = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  DeveloperDiagnosticsService get _diagnostics =>
      DeveloperDiagnosticsService.instance;

  @override
  void initState() {
    super.initState();
    _api = ScanApiService(savedSession: widget.savedSession);
    _diagnostics
      ..setContext('Current shipment ID', widget.task.officialOrderId)
      ..setContext('Current AWB', widget.task.displayReference);
    _loadStatuses();
  }

  @override
  void dispose() {
    _nationalAddress.dispose();
    _otp.dispose();
    super.dispose();
  }

  dynamic _find(dynamic node, List<String> keys) {
    final wanted = keys
        .map((key) => key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .toSet();
    dynamic walk(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key
              .toString()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (wanted.contains(key) && entry.value != null) return entry.value;
        }
        for (final child in value.values) {
          final result = walk(child);
          if (result != null) return result;
        }
      } else if (value is List) {
        for (final child in value) {
          final result = walk(child);
          if (result != null) return result;
        }
      }
      return null;
    }

    return walk(node);
  }

  List<Map<String, dynamic>> _extractOptions(dynamic response) {
    if (response is! Map) return const [];
    final statuses = response['statuses'];
    if (statuses is! List) return const [];
    final result = <Map<String, dynamic>>[];
    for (final status in statuses.whereType<Map>()) {
      final labels = status['driver_status_labels'];
      if (labels is! List) continue;
      for (final label in labels.whereType<Map>()) {
        result.add({
          ...Map<String, dynamic>.from(label),
          'status_id': status['id'],
          'status_text': status['text'],
        });
      }
    }
    return result;
  }

  String _optionLabel(Map<String, dynamic> option) => (option['text'] ??
          _find(option, const [
            'label',
            'name',
            'status_label',
            'title',
            'value',
          ]) ??
          '')
      .toString()
      .trim();

  Object? _statusId(Map<String, dynamic> option) => option['status_id'];

  Object? _statusLabelId(Map<String, dynamic> option) =>
      option['id'] ??
      _find(option, const ['status_label_id', 'reason_id', 'label_id']);

  String _fingerprint(Map<String, dynamic> option) =>
      '${_statusId(option)}|${_statusLabelId(option)}|${_optionLabel(option).toLowerCase()}';

  Future<void> _loadStatuses() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    Map<String, dynamic>? withoutScan;
    Map<String, dynamic>? withScan;
    Object? firstError;
    final task = widget.task;
    try {
      withoutScan = await _api.getDriverStatuses(
        withoutScan: true,
        currentStatus: task.statusId ?? task.statusCode,
        currentStatusLabel: task.statusLabel,
        currentIsRvp: task.isRvp,
        currentOrderType: task.orderTypeId ?? task.orderType,
      );
    } catch (error) {
      firstError = error;
    }
    try {
      withScan = await _api.getDriverStatuses(
        withoutScan: false,
        currentStatus: task.statusId ?? task.statusCode,
        currentStatusLabel: task.statusLabel,
        currentIsRvp: task.isRvp,
        currentOrderType: task.orderTypeId ?? task.orderType,
      );
    } catch (error) {
      firstError ??= error;
    }

    if (!mounted) return;
    if (withoutScan == null && withScan == null) {
      setState(() {
        _loading = false;
        _error = firstError?.toString() ?? 'تعذر جلب الحالات المتاحة.';
      });
      return;
    }

    final regular = _extractOptions(withoutScan ?? const {});
    final scan = _extractOptions(withScan ?? const {});
    final regularKeys = regular.map(_fingerprint).toSet();
    final merged = <String, Map<String, dynamic>>{};
    for (final option in regular) {
      merged[_fingerprint(option)] = {
        ...option,
        '_requires_qr_verification': false,
      };
    }
    for (final option in scan) {
      final key = _fingerprint(option);
      merged[key] = {
        ...option,
        '_requires_qr_verification': !regularKeys.contains(key),
      };
    }
    final options = merged.values.toList()
      ..sort((a, b) {
        final aDelivered = _isDelivered(_optionLabel(a));
        final bDelivered = _isDelivered(_optionLabel(b));
        if (aDelivered != bDelivered) return aDelivered ? -1 : 1;
        return _optionLabel(a).compareTo(_optionLabel(b));
      });
    setState(() {
      _options = options;
      _selected = options.isEmpty ? null : options.first;
      _loading = false;
      if (options.isEmpty) {
        _error = 'لا توجد حالات متاحة لهذه الشحنة حاليًا في نظام SLS.';
      }
    });
  }

  bool _isDelivered(String label) {
    final value = label.trim().toLowerCase();
    return value.contains('delivered') ||
        value.contains('delivery completed') ||
        value.contains('تم التسليم') ||
        value.contains('تم التوصيل');
  }

  bool _requiresNationalAddress(String label) {
    final value = label.trim().toLowerCase();
    return value == 'unclear national address' ||
        value.contains('national address') ||
        value.contains('العنوان الوطني');
  }

  bool _requiresQr(Map<String, dynamic> option) =>
      option['_requires_qr_verification'] == true;

  bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (const {'true', '1', 'yes', 'required'}.contains(text)) return true;
    if (const {'false', '0', 'no', 'optional'}.contains(text)) return false;
    return null;
  }

  bool _requiresAttachment(Map<String, dynamic> option) {
    final explicit = _asBool(_find(option, const [
      'requires_attachment',
      'attachment_required',
      'is_attachment_required',
      'requires_proof',
      'proof_required',
      'poc_attachment_required',
    ]));
    if (explicit != null) return explicit;
    final label = _optionLabel(option).toLowerCase();
    if (label.contains('picked up') || label.contains('تم الاستلام')) {
      return false;
    }
    final id = int.tryParse(_statusId(option)?.toString() ?? '');
    return id != null && id != 3;
  }

  bool _requiresReschedule(String label) =>
      label.toLowerCase().contains('reschedule') || label.contains('جدول');

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من الصور'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (picked != null && mounted) setState(() => _image = picked);
  }

  Future<void> _pickReschedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
      initialDate: _rescheduleAt ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_rescheduleAt ?? now),
    );
    if (time == null) return;
    setState(() {
      _rescheduleAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _formatOfficialDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  void _validation(String message) {
    _diagnostics.validation(message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _verifyDeliveryIfNeeded(
    Map<String, dynamic> selected,
  ) async {
    if (!_isDelivered(_optionLabel(selected)) ||
        !_requiresQr(selected) ||
        _deliveryVerified) {
      return true;
    }
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          token: widget.savedSession,
          verificationTask: widget.task,
        ),
      ),
    );
    if (!mounted || verified != true) return false;
    setState(() => _deliveryVerified = true);
    return true;
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) return;
    final label = _optionLabel(selected);
    final delivered = _isDelivered(label);
    final needsAddress = _requiresNationalAddress(label);
    final needsAttachment = _requiresAttachment(selected);
    final needsReschedule = _requiresReschedule(label);
    final address = _nationalAddress.text.trim();

    if (needsAddress && address.isEmpty) {
      _validation('أدخل العنوان الوطني الجديد للعميل.');
      return;
    }
    if (needsAttachment && _image == null) {
      _validation('هذه الحالة تتطلب صورة إثبات.');
      return;
    }
    if (needsReschedule && _rescheduleAt == null) {
      _validation('اختر تاريخ ووقت إعادة الجدولة.');
      return;
    }
    if (delivered && widget.task.requiresDeliveryOtp) {
      final entered = _otp.text.trim();
      if (entered.isEmpty) {
        _validation('أدخل رمز OTP أولًا.');
        return;
      }
      final expected = widget.task.deliveryOtpValue;
      if (expected.isNotEmpty && entered != expected) {
        _validation('رمز OTP غير صحيح.');
        return;
      }
    }
    if (delivered && (widget.task.codAmount ?? 0) > 0 && !_cashCollected) {
      _validation('أكد تحصيل مبلغ COD النقدي قبل التسليم.');
      return;
    }
    if (!await _verifyDeliveryIfNeeded(selected)) return;

    final statusId = _statusId(selected);
    final labelId = _statusLabelId(selected);
    if (statusId == null || label.isEmpty) {
      _validation('بيانات الحالة المعتمدة من SLS غير مكتملة.');
      return;
    }
    final assigneeId = widget.task.assigneeId;
    if (assigneeId == null) {
      _validation('تعذر العثور على معرّف السائق في بيانات الشحنة.');
      return;
    }

    setState(() => _submitting = true);
    try {
      double? latitude;
      double? longitude;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        latitude = position.latitude;
        longitude = position.longitude;
        _diagnostics.setContext(
          'GPS coordinates',
          '$latitude, $longitude',
        );
      } catch (error) {
        _diagnostics.setContext('GPS coordinates', 'Unavailable: $error');
      }
      if (needsAddress && (latitude == null || longitude == null)) {
        throw const ScanApiException(
          'يلزم تحديد موقع السائق لحفظ العنوان الوطني في SLS.',
        );
      }

      final body = <String, dynamic>{
        'status': statusId,
        'status_label': label,
        'awbs': widget.task.displayReference,
        if (_image != null)
          'poc_attachment': await MultipartFile.fromFile(
            _image!.path,
            filename: _image!.name,
          ),
        if (_rescheduleAt != null)
          'reschedule_date': _formatOfficialDate(_rescheduleAt!),
        if (delivered && (widget.task.codAmount ?? 0) > 0)
          'cod_payment_method': 'cash',
      };
      _diagnostics
        ..setContext('Selected status ID', statusId)
        ..setContext('Selected status label ID', labelId)
        ..setContext('Image upload status',
            _image == null ? 'Not required/selected' : 'Uploading')
        ..setContext(
            'National Address payload',
            needsAddress
                ? {
                    'location': address,
                    'latitude': latitude,
                    'longitude': longitude
                  }
                : 'Not required');

      await _api.updateStatus(
        officialBody: body,
        assigneeId: assigneeId,
        latitude: latitude,
        longitude: longitude,
      );
      if (needsAddress) {
        await _api.addPickupLocation(
          location: address,
          latitude: latitude!,
          longitude: longitude!,
        );
      }
      _diagnostics.setContext(
        'Image upload status',
        _image == null ? 'Not required/selected' : 'Uploaded',
      );
      await widget.onUpdated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الحالة رسميًا في SLS.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      _diagnostics.validation(error.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openWhatsApp() async {
    final result = await WhatsAppActionService.openForTask(widget.task);
    if (!mounted || result.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'تعذر فتح واتساب')),
    );
  }

  Future<void> _correctLocation() async {
    final changed = await showLocationCorrectionDialog(context, widget.task);
    if (!mounted || !changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث موقع العميل محليًا فقط.')),
    );
    await widget.onUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final label = selected == null ? '' : _optionLabel(selected);
    final delivered = _isDelivered(label);
    final needsAddress = _requiresNationalAddress(label);
    final needsReschedule = _requiresReschedule(label);
    final needsAttachment = selected != null && _requiresAttachment(selected);
    final needsQr = selected != null && _requiresQr(selected) && delivered;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تحديث الحالة')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_rounded),
                title: Text(widget.task.displayReference),
                subtitle: Text(widget.task.displayStoreName),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.task.customerPhone.trim().isEmpty
                        ? null
                        : () => PhoneActionService.call(
                              widget.task.customerPhone,
                            ),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('اتصال'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.task.customerPhone.trim().isEmpty
                        ? null
                        : _openWhatsApp,
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('واتساب'),
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _correctLocation,
              icon: const Icon(Icons.edit_location_alt_rounded),
              label: const Text('تصحيح موقع العميل محليًا'),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                ),
              DropdownButtonFormField<Map<String, dynamic>>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحالة الجديدة'),
                items: _options.map((option) {
                  final english = _optionLabel(option);
                  return DropdownMenuItem(
                    value: option,
                    child: Text(
                      _labels[english] ?? english,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                          _selected = value;
                          _deliveryVerified = false;
                          _cashCollected = false;
                          _otp.clear();
                          _nationalAddress.clear();
                          _rescheduleAt = null;
                        }),
              ),
              if (needsQr)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _deliveryVerified
                        ? Icons.verified_rounded
                        : Icons.qr_code_scanner_rounded,
                    color: _deliveryVerified ? Colors.green : null,
                  ),
                  title: Text(_deliveryVerified
                      ? 'تم التحقق من باركود الشحنة'
                      : 'سيُفتح الماسح للتحقق قبل التسليم'),
                ),
              if (delivered && widget.task.requiresDeliveryOtp) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _otp,
                  enabled: !_submitting,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'رمز OTP',
                    prefixIcon: Icon(Icons.password_rounded),
                  ),
                ),
              ],
              if (delivered && (widget.task.codAmount ?? 0) > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _cashCollected,
                  onChanged: _submitting
                      ? null
                      : (value) =>
                          setState(() => _cashCollected = value ?? false),
                  title: Text(
                    'تم تحصيل ${(widget.task.codAmount ?? 0).toStringAsFixed(2)} ريال نقدًا',
                  ),
                  subtitle: const Text('COD نقدي فقط — لا يوجد دفع إلكتروني'),
                ),
              if (needsAddress) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _nationalAddress,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'العنوان الوطني الجديد',
                    hintText: 'العنوان الذي سيُحفظ رسميًا في SLS',
                  ),
                ),
              ],
              if (needsReschedule) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickReschedule,
                  icon: const Icon(Icons.calendar_today_rounded),
                  label: Text(_rescheduleAt == null
                      ? 'اختيار موعد إعادة الجدولة'
                      : _formatOfficialDate(_rescheduleAt!)),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                needsAttachment
                    ? 'صورة الإثبات (مطلوبة)'
                    : 'صورة الإثبات (اختيارية)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_image == null)
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickImage,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('إضافة صورة'),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(_image!.path),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: IconButton.filledTonal(
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _image = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _submitting || selected == null ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_submitting ? 'جارٍ الإرسال...' : 'إرسال التحديث'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
