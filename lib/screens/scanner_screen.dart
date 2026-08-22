import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_models.dart';
import '../models/task_item.dart';
import '../repositories/scan_repository.dart';
import '../services/developer_diagnostics_service.dart';
import '../services/scan_api_service.dart';
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
  );
  late final ScanRepository _repository;

  late final _ScanMode _mode;
  bool _handled = false;
  bool _busy = false;
  String? _lastCode;
  final List<LinehaulGroup> _linehaulGroups = [];
  ScannedOrderGroup? _orderGroup;
  final Set<String> _confirmedAwbs = {};
  int _initialConfirmedCount = 0;
  int _locallyConfirmedCount = 0;

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
      _lastCode = null;
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
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (code == null) return;

    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _lastCode = code;
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
      await _showError(error.toString());
      await _resumeScanner();
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
    setState(() {
      _busy = false;
      _lastCode = null;
      if (!_linehaulGroups.any((item) => item.id == group.id)) {
        _linehaulGroups.add(group);
      }
    });
  }

  Future<void> _scanOrderGroup(String code) async {
    final group = await _repository.scanOrderGroup(code);
    if (!mounted) return;
    setState(() {
      _orderGroup = group;
      _initialConfirmedCount =
          group.orders.where((order) => order.isConfirmed).length;
      _locallyConfirmedCount = 0;
      _confirmedAwbs
        ..clear()
        ..addAll(
          group.orders
              .where((order) => order.isConfirmed)
              .map((order) => order.referenceNumber.trim())
              .where((value) => value.isNotEmpty),
        );
      _busy = false;
      _lastCode = null;
      _handled = false;
    });
    await _controller.start();
  }

  Future<void> _scanAndConfirmShipment(String awb) async {
    final group = _orderGroup;
    if (group == null) return;
    if (_confirmedAwbs.contains(awb)) {
      throw StateError('تم مسح هذه الشحنة وتأكيدها مسبقًا في هذه الجلسة.');
    }

    final shipment = await _repository.scanOrder(awb);
    await _repository.confirmOrder(
      groupId: group.id,
      orderId: shipment.id,
      orderAwb: awb,
    );
    if (!mounted) return;
    setState(() {
      _confirmedAwbs.add(awb);
      _locallyConfirmedCount += 1;
      _busy = false;
      _lastCode = null;
      _handled = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تأكيد الشحنة $awb')),
    );
    await _controller.start();
  }

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
        title: const Text('تحويل المجموعة إلى OFD'),
        content: Text(
          'هل تريد تحويل جميع طلبات المجموعة ${group.id} إلى OFD؟',
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
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          onDetectError: (error, stackTrace) {
            DeveloperDiagnosticsService.instance
                .setContext('QR detection error', error.toString());
          },
          errorBuilder: _buildCameraError,
        ),
        Center(
          child: Container(
            width: 270,
            height: 210,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _busy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                            child: Text('جارٍ معالجة ${_lastCode ?? 'الكود'}')),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _mode == _ScanMode.verifyShipment
                              ? 'امسح باركود الشحنة ${widget.verificationTask!.displayReference}'
                              : _orderGroup == null
                                  ? 'وجّه الكاميرا لأي كود: مسار أو مجموعة أو شحنة'
                                  : 'المجموعة ${_orderGroup!.id} — امسح باركود الشحنة',
                          textAlign: TextAlign.center,
                        ),
                        if (_orderGroup != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'تم تأكيد $_confirmedCount من ${_orderGroup!.orders.length}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _orderGroup!.orders.isEmpty
                                ? 0
                                : _confirmedCount / _orderGroup!.orders.length,
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _orderGroup!.orders.isNotEmpty &&
                                    _confirmedCount >=
                                        _orderGroup!.orders.length
                                ? _moveToOfd
                                : null,
                            icon: const Icon(Icons.local_shipping),
                            label: const Text(
                                'بدء التوصيل وتحويل المجموعة إلى OFD'),
                          ),
                          if (_confirmedCount < _orderGroup!.orders.length) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'أكمل مسح كل الشحنات حتى يتفعّل زر بدء التوصيل.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
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
