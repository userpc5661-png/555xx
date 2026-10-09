import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/task_item.dart';
import '../services/address_geocoding_service.dart';
import '../services/location_correction_service.dart';
import '../services/navigation_service.dart';
import '../utils/national_address_utils.dart';

String _format(CorrectedLocation location) =>
    '${location.latitude.toStringAsFixed(7)}, ${location.longitude.toStringAsFixed(7)}';

Future<bool> _confirmLocation(
  BuildContext context,
  CorrectedLocation location,
  String label,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تأكيد الموقع الجديد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تم استخراج الإحداثيات التالية:'),
          const SizedBox(height: 12),
          SelectableText(
            _format(location),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () =>
                NavigationService.openLocation(location, label: label),
            icon: const Icon(Icons.map_outlined),
            label: const Text('معاينة في الخرائط'),
          ),
          const SizedBox(height: 4),
          const Text(
            'سيُحفظ الموقع على هذا الجهاز فقط ولن تتغير بيانات SLS.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('مراجعة'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('تأكيد وحفظ'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Lets the driver override the customer's location on this device only.
/// Returns true when the location was saved or restored.
Future<bool> showLocationCorrectionDialog(
  BuildContext context,
  TaskItem task,
) async {
  final existing = await LocationCorrectionService.load(task);
  if (!context.mounted) return false;
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _LocationCorrectionDialog(task: task, existing: existing),
  );
  return result ?? false;
}

class _LocationCorrectionDialog extends StatefulWidget {
  final TaskItem task;
  final CorrectedLocation? existing;

  const _LocationCorrectionDialog({required this.task, this.existing});

  @override
  State<_LocationCorrectionDialog> createState() =>
      _LocationCorrectionDialogState();
}

class _LocationCorrectionDialogState extends State<_LocationCorrectionDialog> {
  // Owned by the State so it is disposed only after the dialog's closing
  // animation, never while the TextField is still on screen.
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  String get _label => widget.task.customerName.trim().isNotEmpty
      ? widget.task.customerName.trim()
      : widget.task.displayReference;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  Future<CorrectedLocation?> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'خدمة الموقع متوقفة، فعّل GPS ثم أعد المحاولة.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'لا توجد صلاحية للوصول إلى الموقع.';
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return CorrectedLocation(position.latitude, position.longitude);
  }

  /// Fills the field with the customer's short address from the shipment
  /// data when available; otherwise the driver types it from the label.
  Future<void> _useNationalAddress() async {
    final known = NationalAddressUtils.customerShortAddress(widget.task.raw);
    if (known == null) {
      setState(() {
        _controller.clear();
        _error =
            'اكتب العنوان الوطني المختصر من البوليصة (مثل EHAC4301) ثم اضغط حفظ الموقع.';
      });
      return;
    }
    setState(() => _controller.text = known);
    await _resolveAndSave(useCurrentPosition: false);
  }

  Future<void> _resolveAndSave({required bool useCurrentPosition}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    CorrectedLocation? value;
    try {
      value = useCurrentPosition
          ? await _currentPosition()
          : await LocationCorrectionService.parse(_controller.text) ??
              // Not coordinates or a maps link: treat it as an address from
              // the label (short National Address or full text).
              await AddressGeocodingService.locate(_controller.text);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is String ? error : 'تعذر تحديد موقعك الحالي.';
      });
      return;
    }
    if (!mounted) return;
    if (value == null) {
      setState(() {
        _loading = false;
        _error =
            'لم يتم العثور على هذا العنوان. جرّب العنوان كاملًا كما في البوليصة (الحي والمدينة ورقم المبنى) أو ألصق رابط الموقع.';
      });
      return;
    }
    setState(() => _loading = false);
    final confirmed = await _confirmLocation(context, value, _label);
    if (!confirmed || !mounted) return;
    setState(() => _loading = true);
    await LocationCorrectionService.save(widget.task, value);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _restore() async {
    setState(() => _loading = true);
    await LocationCorrectionService.restore(widget.task);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return PopScope(
      canPop: !_loading,
      child: AlertDialog(
        title: const Text('تصحيح موقع العميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (existing != null) ...[
                Text(
                  'الموقع المعدّل حاليًا: ${_format(existing)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _controller,
                enabled: !_loading,
                keyboardType: TextInputType.url,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: 'رابط موقع، إحداثيات، أو العنوان الوطني',
                  hintText: 'EHAC4301 أو 24.7136, 46.6753',
                  errorText: _error,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: 'لصق',
                    onPressed: _loading ? null : _paste,
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _useNationalAddress,
                icon: const Icon(Icons.local_post_office_outlined),
                label: const Text('من العنوان الوطني'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _resolveAndSave(useCurrentPosition: true),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('استخدام موقعي الحالي'),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          if (existing != null)
            TextButton(
              onPressed: _loading ? null : _restore,
              child: const Text('الرجوع للموقع الأصلي'),
            ),
          FilledButton(
            onPressed: _loading
                ? null
                : () => _resolveAndSave(useCurrentPosition: false),
            child: const Text('حفظ الموقع'),
          ),
        ],
      ),
    );
  }
}
