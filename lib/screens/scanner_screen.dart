import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_models.dart';
import '../models/task_item.dart';
import '../repositories/scan_repository.dart';
import '../services/alert_sounds.dart';
import '../services/developer_diagnostics_service.dart';
import '../services/scan_api_service.dart';
import '../utils/shipment_field_mapper.dart';
import 'shipment_status_screen.dart';

enum _ScanMode { automatic, verifyShipment }

class ScannerScreen extends StatefulWidget {
  final String token;
  final TaskItem? verificationTask;

  const ScannerScreen({
    super.key,
    required this.token,
    this.verificationTask,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: true,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    // Frequent reads, so a code has to stay in the frame (see _stableFor).
    detectionTimeoutMs: 100,
  );
  final Map<String, ScannedShipment> _shipmentCache = {};
  late final ScanRepository _repository;

  late final _ScanMode _mode;
  bool _handled = false;
  bool _busy = false;
  final List<LinehaulGroup> _linehaulGroups = [];
  ScannedOrderGroup? _orderGroup;
  final Set<String> _confirmedAwbs = {};
  // IDs returned by the server for shipments confirmed in this session, so
  // the list can mark them green even if the label shows another number.
  final Set<String> _confirmedOrderKeys = {};
  // Codes scanned during this group session that are not part of the group
  // (the server refused to confirm them). Display only.
  final List<_NotInGroupScan> _notInGroup = [];
  int _initialConfirmedCount = 0;
  int _locallyConfirmedCount = 0;
  // Shipments confirmed in this group session, in scan order.
  final List<_ScanEntry> _scanLog = [];

  // A code is accepted only after it stays alone in the frame for
  // [_stableFor]; a gap longer than [_maxGap] starts the wait again. This
  // stops quick reads of a neighbouring label while the phone moves.
  static const _stableFor = Duration(milliseconds: 500);
  static const _maxGap = Duration(milliseconds: 700);
  String? _candidate;
  DateTime? _candidateSince;
  DateTime? _candidateLastSeen;
  Timer? _candidateTimer;
  bool _multipleInFrame = false;
  Timer? _multipleTimer;

  // Collapsed height of the group list sheet, as a share of the screen.
  static const double _sheetInitial = 0.3;

  static String _key(String value) =>
      value.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  static String _withoutPieceSuffix(String key) =>
      key.replaceFirst(RegExp(r'[-_]\d+$'), '');

  /// Whether a scanned code / looked-up shipment is one of the group's
  /// shipments, as far as the app can tell from the group data.
  bool _belongsToGroup(String code, ScannedShipment? shipment) {
    final group = _orderGroup;
    if (group == null) return false;
    final scanned = {
      _key(code),
      _withoutPieceSuffix(code.trim()).replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase(),
      if (shipment != null) ...[
        _key(shipment.referenceNumber),
        _key(shipment.actualAwb),
        '${shipment.id}',
      ],
    }..remove('');
    return group.orders.any((order) {
      final keys = {
        _key(order.referenceNumber),
        _key(order.orderId),
        if (order.id != null) '${order.id}',
      }..remove('');
      return keys.any(scanned.contains);
    });
  }

  static Set<String> _orderKeys(GroupOrder order) => {
        _key(order.referenceNumber),
        _key(order.orderId),
        if (order.id != null) '${order.id}',
      }..remove('');

  /// Position (1-based) of [order] in this session's scans, or null.
  int? _scanNumberOf(GroupOrder order) {
    final keys = _orderKeys(order);
    for (var i = 0; i < _scanLog.length; i++) {
      if (_scanLog[i].keys.any(keys.contains)) return i + 1;
    }
    return null;
  }

  bool _isOrderScanned(GroupOrder order) {
    if (order.isConfirmed) return true;
    final keys = {
      _key(order.referenceNumber),
      _key(order.orderId),
      if (order.id != null) '${order.id}',
    }..remove('');
    return keys.any(_confirmedOrderKeys.contains);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository = ScanRepository(savedSession: widget.token);
    _mode = widget.verificationTask != null
        ? _ScanMode.verifyShipment
        : _ScanMode.automatic;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _candidateTimer?.cancel();
    _multipleTimer?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_busy) unawaited(_startScanner());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_controller.stop());
        break;
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _busy) return;
    // Let the camera preview attach before starting it. Starting an external
    // controller before MobileScanner is attached causes a generic camera
    // error on some Android devices.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted || _busy) return;
    await _controller.start();
  }

  Future<void> _resumeScanner() async {
    if (!mounted) return;
    setState(() {
      _handled = false;
      _busy = false;
    });
    await _startScanner();
  }

  Widget _buildCameraError(
    BuildContext context,
    MobileScannerException error,
    Widget? child,
  ) {
    final details = error.errorDetails;
    final technical = <String>[
      error.errorCode.name,
      if (details?.code?.isNotEmpty ?? false) details!.code!,
      if (details?.message?.isNotEmpty ?? false) details!.message!,
    ].join(' | ');
    DeveloperDiagnosticsService.instance
        .setContext('QR camera error', technical);

    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'صلاحية الكاميرا غير مفعلة. فعّل الكاميرا للتطبيق من إعدادات الجهاز ثم اضغط إعادة المحاولة.',
      MobileScannerErrorCode.unsupported =>
        'لم يتم العثور على كاميرا متوافقة في هذا الجهاز.',
      _ =>
        'تعذر تشغيل الكاميرا. أغلق أي تطبيق آخر يستخدم الكاميرا ثم اضغط إعادة المحاولة.',
    };

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                technical,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _startScanner,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || _busy) return;
    final codes = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final code = _singleShipmentCode(codes);
    if (code == null) {
      if (codes.length > 1) _showMultipleInFrame();
      return;
    }
    if (!_isStable(code)) return;

    _handled = true;
    _candidateTimer?.cancel();
    _candidate = null;
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _busy = true;
    });

    try {
      if (_mode == _ScanMode.verifyShipment) {
        await _verifyShipment(code);
      } else if (_orderGroup != null) {
        await _scanAndConfirmShipment(code);
      } else {
        await _detectAndHandleCode(code);
      }
    } catch (error) {
      AlertSounds.error();
      await _showError(error.toString());
      await _resumeScanner();
    }
  }

  /// The one shipment code in the frame, or null when there is none or the
  /// frame holds different shipments. One label can carry the same number
  /// twice (e.g. a barcode and a QR link that contains it); then the
  /// shortest code is used.
  String? _singleShipmentCode(Set<String> codes) {
    if (codes.isEmpty) return null;
    if (codes.length == 1) return codes.first;
    final sorted = codes.toList()
      ..sort((a, b) => _key(a).length.compareTo(_key(b).length));
    final shortest = _key(sorted.first);
    if (shortest.isEmpty) return null;
    final sameShipment = sorted.every((code) => _key(code).contains(shortest));
    return sameShipment ? sorted.first : null;
  }

  /// Whether [code] has stayed in the frame for [_stableFor].
  bool _isStable(String code) {
    final now = DateTime.now();
    final lastSeen = _candidateLastSeen;
    final isNew = code != _candidate ||
        lastSeen == null ||
        now.difference(lastSeen) > _maxGap;
    _candidateLastSeen = now;
    _candidateTimer?.cancel();
    _candidateTimer = Timer(_maxGap, () {
      if (mounted) setState(() => _candidate = null);
    });
    if (isNew) {
      _candidateSince = now;
      if (_candidate != code || _multipleInFrame) {
        setState(() {
          _candidate = code;
          _multipleInFrame = false;
        });
      }
      return false;
    }
    return now.difference(_candidateSince!) >= _stableFor;
  }

  void _showMultipleInFrame() {
    _candidateTimer?.cancel();
    _multipleTimer?.cancel();
    _multipleTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _multipleInFrame = false);
    });
    if (!_multipleInFrame || _candidate != null) {
      setState(() {
        _multipleInFrame = true;
        _candidate = null;
      });
    }
  }

  String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  Future<void> _detectAndHandleCode(String code) async {
    final attempts = <ScanAttemptResult>[];

    Future<bool> attempt(String type, Future<void> Function() action) async {
      try {
        await action();
        return true;
      } catch (error) {
        if (error is ScanApiException && error.attempt != null) {
          attempts.add(error.attempt!);
        } else {
          attempts.add(ScanAttemptResult(
            type: type,
            method: 'UNKNOWN',
            sanitizedUrl: '',
            sanitizedQuery: const {},
            sanitizedBody: null,
            statusCode: 0,
            responseBody: '',
            errorMessage: error.toString(),
            timestamp: DateTime.now(),
            succeeded: false,
          ));
        }
        return false;
      }
    }

    if (await attempt('ROUTE', () => _scanLinehaul(code))) return;
    if (await attempt('GROUP', () => _scanOrderGroup(code))) return;
    if (await attempt('SHIPMENT', () => _verifyShipment(code))) return;

    await _showUnifiedError(attempts);
    await _resumeScanner();
  }

  Future<void> _showUnifiedError(List<ScanAttemptResult> attempts) async {
    if (!mounted) return;
    AlertSounds.error();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعذر التعرف على الكود'),
        content: const Text(
          'تعذر التعرف على الكود كمسار أو مجموعة أو شحنة. تأكد من صحة الباركود وحاول مرة أخرى.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showScanDiagnosticDetails(attempts);
            },
            child: const Text('عرض التفاصيل'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showScanDiagnosticDetails(List<ScanAttemptResult> attempts) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفاصيل محاولات المسح'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: attempts.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final attempt = attempts[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'النوع: ${attempt.type}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('HTTP Status: ${attempt.statusCode}'),
                  if (attempt.sanitizedUrl.isNotEmpty)
                    Text('URL: ${attempt.sanitizedUrl}', style: const TextStyle(fontSize: 10)),
                  const SizedBox(height: 4),
                  const Text('الرد:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      attempt.responseBody.isEmpty 
                          ? (attempt.errorMessage ?? 'لا يوجد رد') 
                          : attempt.responseBody,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final buffer = StringBuffer();
              for (final a in attempts) {
                buffer.writeln('Type: ${a.type}');
                buffer.writeln('Status: ${a.statusCode}');
                buffer.writeln('URL: ${a.sanitizedUrl}');
                buffer.writeln('Response: ${a.responseBody}');
                buffer.writeln('Error: ${a.errorMessage}');
                buffer.writeln('-------------------');
              }
              await Clipboard.setData(ClipboardData(text: buffer.toString()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ جميع التفاصيل')),
              );
            },
            icon: const Icon(Icons.copy_all),
            label: const Text('نسخ الكل'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyShipment(String code) async {
    final task = widget.verificationTask;
    if (task != null) {
      final scanned = _normalize(code);
      final expected = <String>{
        _normalize(task.referenceNumber),
        _normalize(task.id),
        _normalize(task.officialOrderId.toString()),
      }..removeWhere((value) => value.isEmpty);
      if (!expected.contains(scanned)) {
        DeveloperDiagnosticsService.instance
            .setContext('QR scan results', 'Mismatch: $code');
        throw const ScanApiException(
          'الباركود الممسوح لا يطابق الشحنة المحددة.',
        );
      }
    }

    final shipment = await _repository.scanOrder(code);
    DeveloperDiagnosticsService.instance.setContext(
      'QR scan results',
      'Verified ${shipment.referenceNumber.isEmpty ? code : shipment.referenceNumber}',
    );
    if (!mounted) return;
    AlertSounds.success();
    if (task != null) {
      // Return the complete shipment fetched by the same API used by the
      // smart scanner. The task flow must continue with this fresh server
      // payload, not with the older TaskItem from the tasks list.
      Navigator.of(context).pop(shipment);
      return;
    }
    await _showShipmentDetails(shipment, fallbackCode: code);
    if (!mounted) return;
    await _resumeScanner();
  }

  Future<void> _showShipmentDetails(
    ScannedShipment shipment, {
    required String fallbackCode,
  }) async {
    if (!mounted) return;

    final triggerUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined),
            SizedBox(width: 10),
            Text('بيانات الشحنة'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShipmentInfoRow(
                label: 'اسم العميل',
                value: shipment.customerName.isEmpty
                    ? 'غير متوفر'
                    : shipment.customerName,
              ),
              _ShipmentInfoRow(
                label: 'المتجر',
                value: shipment.storeName.isEmpty
                    ? 'غير متوفر'
                    : shipment.storeName,
              ),
              _ShipmentInfoRow(
                label: 'رقم الجوال',
                value: shipment.customerPhone.isEmpty
                    ? 'غير متوفر'
                    : shipment.customerPhone,
              ),
              _ShipmentInfoRow(
                label: 'العنوان',
                value: shipment.address.isEmpty
                    ? 'غير متوفر'
                    : shipment.address,
              ),
              _ShipmentInfoRow(
                label: 'رقم الشحنة',
                value: shipment.referenceNumber.isEmpty
                    ? fallbackCode
                    : shipment.referenceNumber,
              ),
              _ShipmentInfoRow(
                label: 'الحالة',
                value: shipment.statusText.isEmpty
                    ? 'غير متوفر'
                    : shipment.statusText,
              ),
              _ShipmentInfoRow(
                label: 'مبلغ COD',
                value: shipment.amount,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('تحديث حالة الشحنة'),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () async {
              final pretty = const JsonEncoder.withIndent('  ').convert(
                DeveloperDiagnosticsService.mask(shipment.raw),
              );
              await Clipboard.setData(ClipboardData(text: pretty));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('تم نسخ JSON مع إخفاء البيانات السرية')),
              );
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('نسخ JSON'),
          ),
          TextButton.icon(
            onPressed: () {
              final pretty = const JsonEncoder.withIndent('  ').convert(
                DeveloperDiagnosticsService.mask(shipment.raw),
              );
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('رد الشحنة الخام'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        pretty,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.data_object_outlined),
            label: const Text('عرض JSON'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );

    if (triggerUpdate == true && mounted) {
      final updated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ShipmentStatusScreen(
            task: TaskItem.fromJson(shipment.raw),
            savedSession: widget.token,
            awbOverride: shipment.actualAwb,
          ),
        ),
      );

      if (updated == true && mounted) {
        try {
          setState(() => _busy = true);
          final updatedShipment =
              await _repository.scanOrder(shipment.actualAwb);
          setState(() => _busy = false);
          // Show updated details and let it decide whether to loop or end.
          await _showShipmentDetails(updatedShipment,
              fallbackCode: shipment.actualAwb);
          return; // The recursive call handles resumption
        } catch (e) {
          if (mounted) setState(() => _busy = false);
          await _showError('تم التحديث، لكن فشل جلب البيانات الجديدة: $e');
        }
      }
    }
  }

  Future<void> _scanLinehaul(String code) async {
    final group = await _repository.scanLinehaulGroup(code);
    if (!mounted) return;
    AlertSounds.success();
    setState(() {
      _busy = false;
      if (!_linehaulGroups.any((item) => item.id == group.id)) {
        _linehaulGroups.add(group);
      }
    });
  }

  Future<void> _scanOrderGroup(String code) async {
    final group = await _repository.scanOrderGroup(code);
    if (!mounted) return;
    AlertSounds.success();
    setState(() {
      _orderGroup = group;
      _initialConfirmedCount =
          group.orders.where((order) => order.isConfirmed).length;
      _locallyConfirmedCount = 0;
      _confirmedOrderKeys.clear();
      _notInGroup.clear();
      _scanLog.clear();
      _confirmedAwbs
        ..clear()
        ..addAll(
          group.orders
              .where((order) => order.isConfirmed)
              .map((order) => order.referenceNumber.trim())
              .where((value) => value.isNotEmpty),
        );
      _busy = false;
      _handled = false;
    });
    await _controller.start();
  }

  Future<void> _scanAndConfirmShipment(String awb) async {
    final group = _orderGroup;
    if (group == null) return;
    if (_confirmedAwbs.contains(awb)) {
      final entry = _scanLog
          .where((item) => item.keys.contains(_key(awb)))
          .firstOrNull;
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _busy = false;
        _handled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1500),
          content: Text(
            'ممسوحة من قبل: ${entry?.label ?? awb}',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      await _controller.start();
      return;
    }

    // Same requests as before; a failure is only recorded for the list
    // ("scanned but not in this group") and then shown as usual.
    ScannedShipment? shipment;
    try {
      shipment = _shipmentCache[awb] ??= await _repository.scanOrder(awb);

      await _repository.confirmOrder(
        groupId: group.id,
        orderId: shipment.id,
        orderAwb: awb,
      );
    } catch (error) {
      if (mounted && !_belongsToGroup(awb, shipment)) {
        final message = error is ScanApiException
            ? error.message
            : error.toString();
        final wrong = _NotInGroupScan(
          code: awb,
          number: shipment == null ? awb : _shipmentNumber(shipment, awb),
          customer: shipment?.customerName.trim() ?? '',
          message: message,
        );
        setState(() {
          _notInGroup.removeWhere((item) => item.code == awb);
          _notInGroup.add(wrong);
        });
        throw ScanApiException(
          'الشحنة ${wrong.label} ليست من هذي المجموعة.\n$message',
        );
      }
      rethrow;
    }
    final confirmed = shipment;
    _shipmentCache.remove(awb);
    final orderKeys = {
      _key(awb),
      _key(confirmed.referenceNumber),
      _key(confirmed.actualAwb),
      '${confirmed.id}',
    }..remove('');
    final entry = _ScanEntry(
      number: _shipmentNumber(confirmed, awb),
      customer: confirmed.customerName.trim(),
      keys: orderKeys,
    );
    if (!mounted) return;
    AlertSounds.success();
    setState(() {
      _confirmedAwbs.add(awb);
      _confirmedOrderKeys.addAll(orderKeys);
      _scanLog.add(entry);
      _locallyConfirmedCount += 1;
      _busy = false;
      _handled = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Text(
          '✅ ${_scanLog.length}. ${entry.label}',
          textDirection: TextDirection.rtl,
        ),
      ),
    );
    await _controller.start();
  }

  /// The shipment number to show the driver, instead of the raw code
  /// (which can be a link or an internal code).
  static String _shipmentNumber(ScannedShipment shipment, String code) =>
      ShipmentFieldMapper.firstNonEmpty([
        shipment.referenceNumber,
        shipment.actualAwb,
        code,
      ]);

  Future<void> _executeLinehaulAction() async {
    final allClosed = _linehaulGroups.isNotEmpty &&
        _linehaulGroups.every((group) => group.status == 'closed');
    final allOutToDestination = _linehaulGroups.isNotEmpty &&
        _linehaulGroups.every(
          (group) => group.status.startsWith('Out to Destination'),
        );
    if (!allClosed && !allOutToDestination) return;

    setState(() => _busy = true);
    try {
      final result = allClosed
          ? await _repository.dispatchLinehaulGroups(_linehaulGroups)
          : await _repository.receiveLinehaulGroups(_linehaulGroups);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty ? 'تم تنفيذ العملية بنجاح' : result.message,
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      await _showError(error.toString());
    }
  }

  int get _confirmedCount {
    final total = _orderGroup?.orders.length ?? 0;
    final count = _initialConfirmedCount + _locallyConfirmedCount;
    return count > total ? total : count;
  }

  Future<void> _moveToOfd() async {
    final group = _orderGroup;
    if (group == null) return;
    if (group.orders.isEmpty || _confirmedCount < group.orders.length) {
      await _showError(
        'لا يمكن بدء التوصيل قبل تأكيد جميع شحنات المجموعة. '
        'المؤكد الآن $_confirmedCount من ${group.orders.length}.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خارج للتوصيل (OFD)'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'هل تريد تحويل جميع طلبات المجموعة ${group.id} إلى OFD؟',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _groupRows(compact: true),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _controller.stop();
    setState(() => _busy = true);
    try {
      final result = await _repository.moveOrderGroupToOfd(group.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty
                ? 'تم تحويل المجموعة إلى OFD'
                : result.message,
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      await _showError(error.toString());
      await _resumeScanner();
    }
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعذر تنفيذ العملية'),
        content: SelectableText(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: _buildScanner(),
      ),
    );
  }

  String get _title => _mode == _ScanMode.verifyShipment
      ? 'التحقق من الشحنة'
      : 'المسح الذكي';

  Widget _buildScanner() {
    if (_linehaulGroups.isNotEmpty) {
      return _buildLinehaulSummary();
    }
    final group = _orderGroup;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // The frame sits in the part of the screen above the bottom panel,
        // so the panel never covers it. Only codes inside it are read.
        final panelHeight =
            group != null ? size.height * _sheetInitial : 170.0;
        const frameHeight = 190.0;
        final frameWidth = math.min(size.width - 32, 380.0);
        final centerY = math.max(
          frameHeight / 2 + 56,
          (size.height - panelHeight) / 2,
        );
        final frame = Rect.fromCenter(
          center: Offset(size.width / 2, centerY),
          width: frameWidth,
          height: frameHeight,
        );
        final frameColor = _multipleInFrame
            ? Colors.redAccent
            : _candidate != null
                ? Colors.amber
                : Colors.white;
        final hint = _multipleInFrame
            ? 'وجّه على شحنة وحدة'
            : _candidate != null
                ? 'ثبّت الجوال…'
                : 'خلّ الباركود داخل الإطار';

        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              scanWindow: frame,
              onDetect: _onDetect,
              onDetectError: (error, stackTrace) {
                DeveloperDiagnosticsService.instance
                    .setContext('QR detection error', error.toString());
              },
              errorBuilder: _buildCameraError,
            ),
            Positioned.fromRect(
              rect: frame,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    border: Border.all(color: frameColor, width: 4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: math.max(8, frame.top - 48),
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _multipleInFrame
                          ? Colors.red.shade700
                          : Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _busy ? 'جارٍ المعالجة…' : hint,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (group != null)
              _buildGroupSheet(group)
            else
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _busy
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Flexible(child: Text('جارٍ المعالجة…')),
                            ],
                          )
                        : Text(
                            _mode == _ScanMode.verifyShipment
                                ? 'امسح باركود الشحنة ${widget.verificationTask!.displayReference}'
                                : 'وجّه الكاميرا لأي كود: مسار أو مجموعة أو شحنة',
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The group's shipments in a panel the driver drags up for the full
  /// list; collapsed it shows only the counts and stays below the frame.
  Widget _buildGroupSheet(ScannedOrderGroup group) {
    final total = group.orders.length;
    final remaining = total - _confirmedCount;
    final last = _scanLog.isEmpty ? null : _scanLog.last;
    return DraggableScrollableSheet(
      initialChildSize: _sheetInitial,
      minChildSize: 0.16,
      maxChildSize: 0.9,
      snap: true,
      builder: (context, scrollController) => Material(
        elevation: 12,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المجموعة ${group.id}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _CountChip('✅', _confirmedCount, Colors.green),
                const SizedBox(width: 6),
                _CountChip('⏳', remaining < 0 ? 0 : remaining, Colors.red),
                const SizedBox(width: 6),
                _CountChip('⚠️', _notInGroup.length, Colors.orange.shade800),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total == 0 ? 0 : _confirmedCount / total,
            ),
            if (last != null) ...[
              const SizedBox(height: 6),
              Text(
                'آخر شحنة: ${last.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: total > 0 && _confirmedCount >= total && !_busy
                  ? _moveToOfd
                  : null,
              icon: const Icon(Icons.local_shipping),
              label: const Text('خارج للتوصيل (OFD)'),
            ),
            if (_confirmedCount < total) ...[
              const SizedBox(height: 4),
              const Text(
                'أكمل مسح كل الشحنات حتى يتفعّل زر بدء التوصيل. اسحب لفوق لعرض القائمة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
            const Divider(height: 20),
            ..._groupRows(compact: false),
          ],
        ),
      ),
    );
  }

  /// Every shipment of the group: not in the group (orange), remaining
  /// (red), and scanned (green, numbered in scan order, latest first).
  List<Widget> _groupRows({required bool compact}) {
    final group = _orderGroup;
    if (group == null) return const [];
    String number(GroupOrder order) => order.referenceNumber.isNotEmpty
        ? order.referenceNumber
        : order.orderId;
    String customer(GroupOrder order) =>
        ShipmentFieldMapper.recipientName(order.raw);

    final remaining =
        group.orders.where((order) => !_isOrderScanned(order)).toList();
    final scanned = group.orders.where(_isOrderScanned).toList()
      ..sort((a, b) {
        // Latest scan on top; shipments confirmed before this session last.
        final ia = _scanNumberOf(a) ?? 0;
        final ib = _scanNumberOf(b) ?? 0;
        return ib.compareTo(ia);
      });

    return [
      if (_notInGroup.isNotEmpty)
        _SectionHeader(
          '⚠️ ليست من المجموعة (${_notInGroup.length})',
          Colors.orange.shade800,
        ),
      for (final extra in _notInGroup.reversed)
        _OrderRow(
          number: extra.number,
          customer: extra.customer,
          color: Colors.orange.shade800,
          icon: Icons.report_problem,
          note: compact ? 'ليست في المجموعة' : extra.message,
          compact: compact,
        ),
      if (remaining.isNotEmpty)
        _SectionHeader('⏳ باقي ما انمسحت (${remaining.length})', Colors.red),
      for (final order in remaining)
        _OrderRow(
          number: number(order),
          customer: customer(order),
          color: Colors.red,
          icon: Icons.hourglass_empty,
          note: 'لم تُمسح',
          compact: compact,
        ),
      if (scanned.isNotEmpty)
        _SectionHeader('✅ تم المسح (${scanned.length})', Colors.green),
      for (final order in scanned)
        () {
          final index = _scanNumberOf(order);
          final entry = index == null ? null : _scanLog[index - 1];
          return _OrderRow(
            number: number(order),
            customer: entry?.customer.isNotEmpty == true
                ? entry!.customer
                : customer(order),
            color: Colors.green,
            icon: Icons.check_circle,
            note: index == null ? 'مؤكدة من قبل' : 'تم المسح',
            badge: index == null ? null : '$index',
            compact: compact,
          );
        }(),
    ];
  }

  Widget _buildLinehaulSummary() {
    final allClosed =
        _linehaulGroups.every((group) => group.status == 'closed');
    final allOut = _linehaulGroups.every(
      (group) => group.status.startsWith('Out to Destination'),
    );
    final canAct = allClosed || allOut;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'المجموعات الممسوحة (${_linehaulGroups.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final group in _linehaulGroups)
          Card(
            child: ListTile(
              leading: const Icon(Icons.route),
              title: Text('المجموعة ${group.id}'),
              subtitle: Text(
                '${group.status}\n${group.originHub?.name ?? ''} → ${group.destinationHub?.name ?? ''}\n${group.orders.length} شحنة',
              ),
              isThreeLine: true,
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _resumeScanner,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('مسح مجموعة إضافية'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canAct && !_busy ? _executeLinehaulAction : null,
          icon: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(allClosed ? 'إرسال المسار' : 'استلام المسار'),
        ),
        if (!canAct) ...[
          const SizedBox(height: 8),
          const Text(
            'التطبيق الرسمي ينفذ الإرسال فقط عندما تكون كل المجموعات closed، والاستلام عندما تبدأ حالتها بـ Out to Destination.',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

String _labelOf(String number, String customer) =>
    customer.isEmpty ? number : '$number — $customer';

/// A shipment confirmed in this group session.
class _ScanEntry {
  final String number;
  final String customer;
  final Set<String> keys;
  const _ScanEntry({
    required this.number,
    required this.customer,
    required this.keys,
  });

  String get label => _labelOf(number, customer);
}

/// A shipment scanned in this group session that is not in the group.
class _NotInGroupScan {
  final String code;
  final String number;
  final String customer;
  final String message;
  const _NotInGroupScan({
    required this.code,
    required this.number,
    required this.customer,
    required this.message,
  });

  String get label => _labelOf(number, customer);
}

class _CountChip extends StatelessWidget {
  final String icon;
  final int count;
  final Color color;
  const _CountChip(this.icon, this.count, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$icon $count',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader(this.title, this.color);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      );
}

class _OrderRow extends StatelessWidget {
  final String number;
  final String customer;
  final Color color;
  final IconData icon;
  final String note;
  final String? badge;
  final bool compact;

  const _OrderRow({
    required this.number,
    required this.customer,
    required this.color,
    required this.icon,
    required this.note,
    required this.compact,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: compact ? 5 : 8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (badge != null)
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              )
            else ...[
              Icon(icon, color: color, size: compact ? 16 : 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  if (customer.isNotEmpty)
                    Text(
                      customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

class _ShipmentInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ShipmentInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
