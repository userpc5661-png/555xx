import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import '../services/location_correction_service.dart';
import '../services/navigation_service.dart';
import '../utils/location_sources.dart';

/// Shows every location the SLS server sent for [task], which one the app
/// is using, and lets the driver adopt another one as a local correction.
/// Nothing here is sent to the server.
Future<void> showLocationSourcesSheet(BuildContext context, TaskItem task) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LocationSourcesSheet(task: task),
  );
}

class _LocationSourcesSheet extends StatefulWidget {
  final TaskItem task;
  const _LocationSourcesSheet({required this.task});

  @override
  State<_LocationSourcesSheet> createState() => _LocationSourcesSheetState();
}

class _LocationSourcesSheetState extends State<_LocationSourcesSheet> {
  late final List<LocationSource> _sources = LocationSources.find(
    widget.task.raw,
  );
  CorrectedLocation? _correction;
  bool _busy = false;

  CorrectedLocation? get _serverPin {
    final task = widget.task;
    if (task.latitude == null || task.longitude == null) return null;
    return CorrectedLocation(task.latitude!, task.longitude!);
  }

  @override
  void initState() {
    super.initState();
    LocationCorrectionService.load(widget.task).then((value) {
      if (mounted) setState(() => _correction = value);
    });
  }

  String _coords(CorrectedLocation l) =>
      '${l.latitude.toStringAsFixed(6)}, ${l.longitude.toStringAsFixed(6)}';

  String _distance(double meters) => meters < 1000
      ? '${meters.round()} م'
      : '${(meters / 1000).toStringAsFixed(1)} كم';

  bool _same(CorrectedLocation a, CorrectedLocation? b) =>
      b != null && LocationSources.distanceMeters(a, b) < 2;

  String get _label => widget.task.customerName.trim().isNotEmpty
      ? widget.task.customerName.trim()
      : widget.task.displayReference;

  Future<void> _open(LocationSource source) async {
    final location = source.location;
    if (location != null) {
      await NavigationService.openLocation(location, label: _label);
      return;
    }
    final uri = Uri.tryParse(source.rawText ?? '');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _adopt(LocationSource source) async {
    setState(() => _busy = true);
    final location = source.location ??
        await LocationCorrectionService.parse(source.rawText ?? '');
    if (!mounted) return;
    setState(() => _busy = false);
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قراءة الإحداثيات من هذا الرابط')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اعتماد هذا الموقع؟'),
        content: Text(
          '${_coords(location)}\n\n'
          'سيُستخدم في الخريطة والملاحة على هذا الجهاز فقط، ولن يتغير شيء في SLS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await LocationCorrectionService.save(widget.task, location);
    if (!mounted) return;
    setState(() => _correction = location);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم اعتماد الموقع محليًا')),
    );
  }

  Future<void> _copyReport() async {
    final task = widget.task;
    final lines = <String>[
      'Shipment: ${task.displayReference}',
      'Address: ${task.address}',
      'App pin (server): ${_serverPin == null ? '-' : _coords(_serverPin!)}',
      'Local correction: ${_correction == null ? '-' : _coords(_correction!)}',
      'Sources from server:',
      for (final s in _sources)
        '- ${s.path}: ${s.location == null ? s.rawText : _coords(s.location!)}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ بيانات الموقع')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverPin = _serverPin;
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مواقع العميل القادمة من السيرفر',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    serverPin == null
                        ? 'البرنامج لم يجد إحداثيات أساسية لهذه الشحنة.'
                        : 'الموقع الذي يستخدمه البرنامج (والتطبيق الرسمي غالبًا): ${_coords(serverPin)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_correction != null)
                    Text(
                      'معدّل محليًا: ${_coords(_correction!)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.purple),
                    ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            Expanded(
              child: _sources.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'السيرفر لم يرسل أي إحداثيات أو روابط خرائط لهذه الشحنة.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _sources.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final source = _sources[index];
                        final location = source.location;
                        final used = location != null &&
                            _same(location, _correction ?? serverPin);
                        final away = location != null && serverPin != null
                            ? LocationSources.distanceMeters(
                                location,
                                serverPin,
                              )
                            : null;
                        return ListTile(
                          leading: Icon(
                            location == null
                                ? Icons.link_rounded
                                : Icons.location_on_outlined,
                            color: used ? Colors.green : null,
                          ),
                          title: Text(
                            source.path,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (location != null)
                                _coords(location)
                              else
                                source.rawText ?? '',
                              if (used) '✓ المستخدم حاليًا',
                              if (!used && away != null && away >= 2)
                                'يبعد ${_distance(away)} عن موقع البرنامج',
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'فتح في الخرائط',
                                icon: const Icon(Icons.map_outlined),
                                onPressed: () => _open(source),
                              ),
                              IconButton(
                                tooltip: 'اعتماد هذا الموقع',
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: _busy || used
                                    ? null
                                    : () => _adopt(source),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: OutlinedButton.icon(
                onPressed: _copyReport,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('نسخ بيانات الموقع لإرسالها'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
