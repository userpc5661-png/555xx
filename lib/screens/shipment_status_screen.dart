import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/task_item.dart';
import '../services/developer_diagnostics_service.dart';
import '../services/delivery_history_store.dart';
import '../services/phone_action_service.dart';
import '../services/scan_api_service.dart';
import '../services/softpos_service.dart';
import '../services/whatsapp_action_service.dart';
import '../widgets/location_correction_dialog.dart';

enum ShipmentStatusMode { all, deliveredOnly, nonDeliveredOnly }

class ShipmentStatusScreen extends StatefulWidget {
  final TaskItem task;
  final String savedSession;
  final String? awbOverride;
  final Future<void> Function()? onUpdated;
  final ShipmentStatusMode mode;

  const ShipmentStatusScreen({
    super.key,
    required this.task,
    required this.savedSession,
    this.awbOverride,
    this.onUpdated,
    this.mode = ShipmentStatusMode.all,
  });

  @override
  State<ShipmentStatusScreen> createState() => _ShipmentStatusScreenState();
}

enum _CodPaymentMethod { cash, softPos }

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
  _CodPaymentMethod? _codPaymentMethod;
  bool _softPosPaid = false;
  bool _softPosProcessing = false;
  String? _softPosTransactionId;
  bool _softPosRegisteredOnSls = false;
  late final SoftPosService _softPosService;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  // Diagnostics fields
  Map<String, dynamic>? _lastPayload;
  int? _lastStatusCode;
  String? _lastResponseBody;
  String? _verifiedStatusOnServer;

  DeveloperDiagnosticsService get _diagnostics =>
      DeveloperDiagnosticsService.instance;

  @override
  void initState() {
    super.initState();
    _api = ScanApiService(savedSession: widget.savedSession);
    _softPosService = SoftPosService();
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
    final result = <Map<String, dynamic>>[];

    void addLabel(Map status, Map label) {
      final item = <String, dynamic>{
        ...Map<String, dynamic>.from(label),
        'status_id': status['id'] ?? status['status_id'] ?? label['status_id'],
        'status_text': status['text'] ?? status['name'] ?? status['status'],
      };
      if (_optionLabel(item).isNotEmpty && _statusId(item) != null) {
        result.add(item);
      }
    }

    void walk(dynamic node) {
      if (node is List) {
        for (final item in node) walk(item);
        return;
      }
      if (node is! Map) return;

      final labels = node['driver_status_labels'] ??
          node['status_labels'] ??
          node['labels'] ??
          node['reasons'];

      if (labels is List) {
        for (final label in labels.whereType<Map>()) addLabel(node, label);
      }

      for (final entry in node.entries) {
        if (const {'driver_status_labels', 'status_labels', 'labels', 'reasons'}
            .contains(entry.key.toString())) continue;
        if (entry.value is Map || entry.value is List) walk(entry.value);
      }
    }

    walk(response);
    final unique = <String, Map<String, dynamic>>{};
    for (final option in result) {
      unique[_fingerprint(option)] = option;
    }
    return unique.values.toList();
  }

  bool _isDelivered(String label) {
    final value = label.trim().toLowerCase();
    return value.contains('delivered') ||
        value.contains('delivery completed') ||
        value.contains('shipment delivered') ||
        value.contains('تم التسليم') ||
        value.contains('تم التوصيل') ||
        value.contains('تم توصيل الشحنة');
  }

  bool _isDeliveredOption(Map<String, dynamic> option) =>
      _isDelivered(_optionSearchText(option));

  bool _isCurrentTransitOption(Map<String, dynamic> option) {
    final value = _optionSearchText(option);
    return value.contains('out for delivery') ||
        value.contains('out for transit') ||
        value.contains('خارج للتوصيل') ||
        value.contains('قيد التوصيل');
  }

  String _optionDisplayLabel(Map<String, dynamic> option) =>
      (option['text'] ??
              _find(option, const [
                'label',
                'name',
                'title',
                'status_label',
                'value',
              ]) ??
              '')
          .toString()
          .trim();

  // The official response normally uses `text` for display and `value` as the
  // exact status_label value expected by bulk/status.
  String _optionApiLabel(Map<String, dynamic> option) =>
      (option['value'] ??
              option['status_label'] ??
              option['text'] ??
              _find(option, const ['label', 'name', 'title']) ??
              '')
          .toString()
          .trim();

  String _optionLabel(Map<String, dynamic> option) =>
      _optionDisplayLabel(option);

  String _optionSearchText(Map<String, dynamic> option) =>
      '${_optionDisplayLabel(option)} ${_optionApiLabel(option)}'.toLowerCase();

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

    final task = widget.task;
    debugPrint(
      'TASK DRIVER STATUS LABELS: ${task.raw['driver_status_labels']}',
    );
    final awb = widget.awbOverride ?? task.realAwb;
    List<Map<String, dynamic>> options = [];

    // 1. Try authoritative data already in the task (e.g. from Smart Scanner)
    options = _extractOptions(task.raw);

    // 2. If empty and we need statuses, call the authoritative scanOrder
    // endpoint just like the Smart Scanner does.
    if (options.isEmpty) {
      try {
        final shipment = await _api.scanOrder(awb);
        options = _extractOptions(shipment.raw);
      } catch (e) {
        debugPrint('Discovery: scanOrder failed for $awb: $e');
      }
    }

    // 3. Fallback to discovery endpoints if still empty
    if (options.isEmpty) {
      Map<String, dynamic>? withoutScan;
      Map<String, dynamic>? withScan;
      try {
        withoutScan = await _api.getDriverStatuses(
          withoutScan: true,
          currentStatus: task.statusId ?? task.statusCode,
          currentStatusLabel: task.statusLabel,
          currentIsRvp: task.isRvp,
          currentOrderType: task.orderTypeId ?? task.orderType,
        );
      } catch (_) {}
      try {
        withScan = await _api.getDriverStatuses(
          withoutScan: false,
          currentStatus: task.statusId ?? task.statusCode,
          currentStatusLabel: task.statusLabel,
          currentIsRvp: task.isRvp,
          currentOrderType: task.orderTypeId ?? task.orderType,
        );
      } catch (_) {}

      final regular = _extractOptions(withoutScan ?? const {});
      final scan = _extractOptions(withScan ?? const {});
      final merged = <String, Map<String, dynamic>>{};
      for (final opt in regular) {
        merged[_fingerprint(opt)] = {...opt, '_requires_qr_verification': false};
      }
      for (final opt in scan) {
        final key = _fingerprint(opt);
        if (!merged.containsKey(key)) {
          merged[key] = {...opt, '_requires_qr_verification': true};
        }
      }
      options = merged.values.toList();
    }

    if (!mounted) return;

    options.sort((a, b) {
      final aDelivered = _isDeliveredOption(a);
      final bDelivered = _isDeliveredOption(b);
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

  Future<void> _startSoftPosPayment() async {
    final amountSar = widget.task.codAmount ?? 0;
    if (amountSar <= 0) {
      _validation('مبلغ التحصيل غير صالح (صفر أو أقل).');
      return;
    }
    final amountHalalas = (amountSar * 100).round();
    final awb = (widget.awbOverride?.trim().isNotEmpty ?? false)
        ? widget.awbOverride!.trim()
        : widget.task.realAwb.trim();
    final assigneeId = widget.task.assigneeId;

    debugPrint('================ SLS PAYMENT START ================');
    debugPrint('AWB: $awb');
    debugPrint('Payment Kind: ${widget.task.paymentKind}');
    debugPrint('Is COD: ${widget.task.isCashOnDelivery}');
    debugPrint('COD Amount SAR: $amountSar');
    debugPrint('Amount In Halalas: $amountHalalas');
    debugPrint('Assignee ID present: ${assigneeId != null}');
    debugPrint('Customer COD Payment ID present: false (before purchase)');

    // Note: JWT and TID are currently managed natively in MainActivity.kt
    // so their direct presence in SharedPreferences/Dart is false by default.
    debugPrint('JWT present: false (managed by native)');
    debugPrint('SoftPos TID present: false (managed by native)');

    setState(() {
      _softPosProcessing = true;
      _softPosPaid = false;
      _softPosRegisteredOnSls = false;
      _softPosTransactionId = null;
    });

    try {
      debugPrint('Nearpay purchase started');
      final result = await _softPosService.purchase(
        amountHalalas: amountHalalas,
        orderReference:
            awb.isNotEmpty ? awb : widget.task.displayReference,
      );

      debugPrint('Nearpay purchase result success: ${result.success}');
      debugPrint('Nearpay cancelled: ${result.cancelled}');

      if (!result.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        debugPrint('================ SLS PAYMENT END ==================');
        return;
      }

      final userId = _api.sessionIds['user_id'] ??
          _api.sessionIds['id'] ??
          _api.sessionIds['driver_id'];

      final posBody = result.toOfficialPosPayload(
        userId: userId,
        awb: awb.isNotEmpty ? awb : widget.task.displayReference.trim(),
        requestedAmountHalalas: amountHalalas,
      );

      debugPrint('bulk/pos called: true');
      _diagnostics.setContext('SLS bulk/pos payload', {
        ...posBody,
        'gateway_response': '[NearPay receipt JSON]',
        'card_number': result.cardNumber == null ? '' : '***',
      });

      await _api.registerPosPayment(officialBody: posBody);
      debugPrint('bulk/pos success: true');

      if (!mounted) return;
      setState(() {
        _softPosTransactionId = result.transactionId ?? result.tid;
        _softPosRegisteredOnSls = true;
        _softPosPaid = true;
      });

      debugPrint(
          'Customer COD Payment ID present: true (${_softPosTransactionId != null})');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('تم الدفع وتسجيل العملية في SLS. اضغط حفظ لإتمام التوصيل.'),
        ),
      );
      debugPrint('================ SLS PAYMENT END ==================');
    } on ScanApiException catch (error) {
      debugPrint('bulk/pos HTTP status: ${error.statusCode}');
      debugPrint('bulk/pos success: false');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('نجحت البطاقة لكن تعذر تسجيل الدفع في SLS: $error')),
      );
      debugPrint('================ SLS PAYMENT END ==================');
    } catch (e) {
      debugPrint('SoftPos flow error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ غير متوقع في تدفق الدفع: $e')),
      );
      debugPrint('================ SLS PAYMENT END ==================');
    } finally {
      if (mounted) setState(() => _softPosProcessing = false);
    }
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) return;
    final displayLabel = _optionDisplayLabel(selected);
    final label = _optionApiLabel(selected);
    final delivered = _isDeliveredOption(selected);
    final needsAddress = _requiresNationalAddress(displayLabel) ||
        _requiresNationalAddress(label);
    final needsAttachment = widget.mode == ShipmentStatusMode.nonDeliveredOnly ||
        _requiresAttachment(selected);
    final needsReschedule = _requiresReschedule(displayLabel) ||
        _requiresReschedule(label);
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
    final isCod = widget.task.paymentKind == PaymentKind.cashOnDelivery;
    final isPrepaid = widget.task.paymentKind == PaymentKind.prepaid;

    if (delivered && isPrepaid) {
      final entered = _otp.text.trim();
      if (!RegExp(r'^\d{4}$').hasMatch(entered)) {
        _validation('أدخل رمز OTP المكوّن من 4 أرقام.');
        return;
      }
      final expected = widget.task.deliveryOtpValue;
      if (expected.isNotEmpty && entered != expected) {
        _validation('رمز OTP غير صحيح.');
        return;
      }
    }
    if (delivered && isCod && _codPaymentMethod == null) {
      _validation('اختر طريقة الدفع: Cash أو SoftPOS.');
      return;
    }
    if (delivered &&
        isCod &&
        _codPaymentMethod == _CodPaymentMethod.softPos &&
        (!_softPosPaid || !_softPosRegisteredOnSls)) {
      _validation('أكمل عملية SoftPOS بنجاح قبل الحفظ.');
      return;
    }

    final statusId = _statusId(selected);
    final labelId = _statusLabelId(selected);
    if (statusId == null || label.isEmpty) {
      _validation('بيانات الحالة المعتمدة من SLS غير مكتملة.');
      return;
    }
    final assigneeId = widget.task.assigneeId;
    if (assigneeId == null) {
      debugPrint(
          'ROOT CAUSE: shipment.assignee_id is missing. Current raw data keys: ${widget.task.raw.keys.join(", ")}');
    }

    setState(() {
      _submitting = true;
      _lastPayload = null;
      _lastStatusCode = null;
      _lastResponseBody = null;
      _verifiedStatusOnServer = null;
    });

    try {
      double? latitude;
      double? longitude;
      try {
        // A recent cached fix keeps the submit fast; an old one could be far
        // from where the driver is now, so take a fresh fix instead. Never
        // substitute the customer's coordinates: they are sent as the
        // driver's position.
        final lastKnown = await Geolocator.getLastKnownPosition();
        final lastKnownIsFresh = lastKnown != null &&
            DateTime.now().difference(lastKnown.timestamp) <
                const Duration(minutes: 2) &&
            lastKnown.accuracy <= 100;
        final position = lastKnownIsFresh
            ? lastKnown
            : await Geolocator.getCurrentPosition(
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

      final officialStatusLabel = (selected['value'] ?? label).toString().trim();

      final awb = (widget.awbOverride?.trim().isNotEmpty ?? false)
          ? widget.awbOverride!.trim()
          : widget.task.realAwb.trim();

      final body = <String, dynamic>{
        'status': statusId,
        'status_label': officialStatusLabel,
        'awbs': [awb],
        if (needsAddress && address.isNotEmpty)
          'new_address_details': address,
        if (_image != null)
          'poc_attachment': await MultipartFile.fromFile(
            _image!.path,
            filename: _image!.name,
          ),
        if (_rescheduleAt != null)
          'reschedule_date': _formatOfficialDate(_rescheduleAt!),
        if (delivered && isCod)
          'cod_payment_method':
              _codPaymentMethod == _CodPaymentMethod.softPos ? 'pos' : 'cash',
        if (_softPosTransactionId != null)
          'customer_cod_payment_id': _softPosTransactionId,
      };
      _lastPayload = body;
      _diagnostics
        ..setContext('Selected status ID', statusId)
        ..setContext('Selected status label ID', labelId)
        ..setContext('Image upload status',
            _image == null ? 'Not required/selected' : 'Uploading')
        ..setContext(
            'National Address payload',
            needsAddress
                ? {
                    'new_address_details': address,
                    'latitude': latitude,
                    'longitude': longitude
                  }
                : 'Not required');

      debugPrint('bulk/status called: true');
      await _api.updateStatus(
        officialBody: body,
        assigneeId: assigneeId,
        latitude: latitude,
        longitude: longitude,
      );
      debugPrint('bulk/status HTTP status: 200');
      debugPrint('bulk/status response success: true');
      _verifiedStatusOnServer = 'تم التأكيد بنجاح من سيرفر SLS';

      _diagnostics.setContext(
        'Image upload status',
        _image == null ? 'Not required/selected' : 'Uploaded',
      );
      if (delivered) {
        await DeliveryHistoryStore.instance.recordCompleted(
          widget.task,
          awb: awb,
        );
      }
      widget.onUpdated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم تحديث الحالة وتأكيدها من السيرفر بنجاح.')),
      );
      Navigator.of(context).pop(true);
    } on ScanApiException catch (error) {
      debugPrint('bulk/status called: true');
      debugPrint('bulk/status HTTP status: ${error.statusCode}');
      debugPrint('bulk/status response success: false');
      _lastStatusCode = error.statusCode;
      _lastResponseBody = error.responseBody;
      _diagnostics.validation(error.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
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
    final needsAttachment = selected != null &&
        (widget.mode == ShipmentStatusMode.nonDeliveredOnly ||
            _requiresAttachment(selected));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.mode == ShipmentStatusMode.deliveredOnly
              ? 'تم التوصيل'
              : widget.mode == ShipmentStatusMode.nonDeliveredOnly
                  ? 'لم يتم التوصيل'
                  : 'تحديث الحالة'),
        ),
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
                          _codPaymentMethod = null;
                          _softPosPaid = false;
                          _softPosTransactionId = null;
                          _otp.clear();
                          _nationalAddress.clear();
                          _rescheduleAt = null;
                        }),
              ),
              if (delivered &&
                  widget.task.paymentKind == PaymentKind.prepaid) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _otp,
                  enabled: !_submitting,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'POD Code',
                    hintText: 'أدخل الرمز المكوّن من 4 أرقام',
                    counterText: '',
                    prefixIcon: Icon(Icons.password_rounded),
                  ),
                ),
              ],
              if (delivered &&
                  widget.task.paymentKind == PaymentKind.cashOnDelivery) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cod Payment method',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                RadioListTile<_CodPaymentMethod>(
                  contentPadding: EdgeInsets.zero,
                  value: _CodPaymentMethod.cash,
                  groupValue: _codPaymentMethod,
                  onChanged: _submitting || _softPosProcessing
                      ? null
                      : (value) => setState(() {
                            _codPaymentMethod = value;
                            _softPosPaid = false;
                            _softPosTransactionId = null;
                          }),
                  title: const Text('cash'),
                  subtitle: Text(
                    'تحصيل ${(widget.task.codAmount ?? 0).toStringAsFixed(2)} ريال',
                  ),
                ),
                RadioListTile<_CodPaymentMethod>(
                  contentPadding: EdgeInsets.zero,
                  value: _CodPaymentMethod.softPos,
                  groupValue: _codPaymentMethod,
                  onChanged: _submitting || _softPosProcessing
                      ? null
                      : (value) => setState(() {
                            _codPaymentMethod = value;
                            _softPosPaid = false;
                            _softPosTransactionId = null;
                          }),
                  title: const Text('pos'),
                  subtitle: Text(
                    _softPosPaid
                        ? 'تم الدفع بنجاح ويمكنك الضغط على حفظ.'
                        : 'الدفع بالبطاقة عبر NFC وPayment Plugin.',
                  ),
                ),
                if (_codPaymentMethod == _CodPaymentMethod.softPos)
                  FilledButton.tonalIcon(
                    onPressed: _submitting || _softPosProcessing || _softPosPaid
                        ? null
                        : _startSoftPosPayment,
                    icon: _softPosProcessing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_softPosPaid
                            ? Icons.verified_rounded
                            : Icons.contactless_rounded),
                    label: Text(_softPosPaid
                        ? 'تم الدفع عبر SoftPOS'
                        : 'بدء الدفع عبر SoftPOS'),
                  ),
              ],
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
              if (kDebugMode) _buildDiagnosticsPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, size: 18, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                'Delivery Diagnostics (Debug Only)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const Divider(),
          _diagRow('Session IDs', _api.sessionIds.toString()),
          _diagRow('Shipment ID', widget.task.officialOrderId.toString()),
          _diagRow('Shipment AWB', widget.task.displayReference),
          _diagRow('Shipment Assignee', widget.task.assigneeId.toString()),
          _diagRow('ID Source Used',
              _lastPayload?['_diagnostics_id_source']?.toString() ?? 'N/A'),
          _diagRow('Selected Status', _statusId(_selected ?? {}).toString()),
          const SizedBox(height: 8),
          const Text('Last Request Payload:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          _diagScrollBox(
              DeveloperDiagnosticsService.mask(_lastPayload).toString()),
          const SizedBox(height: 8),
          _diagRow('HTTP Status', _lastStatusCode?.toString() ?? 'N/A'),
          const Text('Raw Response Body:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          _diagScrollBox(_lastResponseBody ?? 'No response captured yet'),
          const SizedBox(height: 8),
          _diagRow('Verified Server Status',
              _verifiedStatusOnServer ?? 'Not verified yet'),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _diagScrollBox(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(6),
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
