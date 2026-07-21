import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_models.dart';
import '../models/task_item.dart';
import '../repositories/scan_repository.dart';
import '../services/developer_diagnostics_service.dart';
import '../services/scan_api_service.dart';

enum _ScanMode { linehaul, orderGroup, verifyShipment }

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

  _ScanMode? _mode;
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
    if (widget.verificationTask != null) {
      _mode = _ScanMode.verifyShipment;
    }
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
        if (_mode != null && !_busy) unawaited(_startScanner());
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
    if (!mounted || _mode == null || _busy) return;
    // Let the camera preview attach before starting it. Starting an external
    // controller before MobileScanner is attached causes a generic camera
    // error on some Android devices.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted || _mode == null || _busy) return;
    await _controller.start();
  }

  Future<void> _chooseMode(_ScanMode mode) async {
    setState(() {
      _mode = mode;
      _handled = false;
      _lastCode = null;
    });
    // MobileScanner starts the controller only after it is attached.
  }

  Future<void> _resetMode() async {
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _mode = null;
      _handled = false;
      _busy = false;
      _lastCode = null;
      _linehaulGroups.clear();
      _orderGroup = null;
      _confirmedAwbs.clear();
      _initialConfirmedCount = 0;
      _locallyConfirmedCount = 0;
    });
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
      } else if (_mode == _ScanMode.linehaul) {
        await _scanLinehaul(code);
      } else if (_orderGroup == null) {
        await _scanOrderGroup(code);
      } else {
        await _scanAndConfirmShipment(code);
      }
    } catch (error) {
      await _showError(error.toString());
      await _resumeScanner();
    }
  }

  String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

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
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _handled = false;
      _lastCode = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم التحقق من الشحنة $code')),
    );
    await _controller.start();
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
        appBar: AppBar(
          title: Text(_title),
          actions: [
            if (_mode != null)
              IconButton(
                onPressed: _busy ? null : _resetMode,
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'تغيير نوع المسح',
              ),
          ],
        ),
        body: _mode == null ? _buildModePicker() : _buildScanner(),
      ),
    );
  }

  String get _title {
    if (_mode == _ScanMode.linehaul) return 'مسح QR للمسار';
    if (_mode == _ScanMode.orderGroup) return 'مسح مجموعة الشحنات';
    if (_mode == _ScanMode.verifyShipment) return 'التحقق من الشحنة';
    return 'مركز المسح';
  }

  Widget _buildModePicker() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.qr_code_scanner, size: 78),
        const SizedBox(height: 20),
        const Text(
          'اختر العملية التي تريد تنفيذها',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 28),
        _ModeCard(
          icon: Icons.local_shipping_outlined,
          title: 'مسح QR للمسار',
          subtitle: 'Linehaul: جلب المجموعة ثم الاستلام أو الإرسال',
          onTap: () => _chooseMode(_ScanMode.linehaul),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          icon: Icons.verified_outlined,
          title: 'التحقق من شحنة',
          subtitle: 'مسح باركود الشحنة والتحقق منه من نظام SLS دون تسليمها',
          onTap: () => _chooseMode(_ScanMode.verifyShipment),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          icon: Icons.inventory_2_outlined,
          title: 'مسح مجموعة الشحنات',
          subtitle: 'جلب المجموعة، تأكيد الشحنات، ثم OFD',
          onTap: () => _chooseMode(_ScanMode.orderGroup),
        ),
      ],
    );
  }

  Widget _buildScanner() {
    if (_mode == _ScanMode.linehaul && _linehaulGroups.isNotEmpty) {
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
                              ? widget.verificationTask == null
                                  ? 'امسح باركود الشحنة للتحقق منها'
                                  : 'امسح باركود الشحنة ${widget.verificationTask!.displayReference}'
                              : _orderGroup == null
                                  ? 'وجّه الكاميرا إلى QR'
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

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, size: 38),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
