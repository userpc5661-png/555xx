import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import '../services/location_correction_service.dart';
import '../services/navigation_service.dart';
import '../services/scan_api_service.dart';
import '../utils/location_sources.dart';

/// Shows every location the SLS server sent for [task], which one the app
/// is using, and lets the driver adopt another one as a local correction.
/// It compares three read-only server sources: the task list (/tasks), the
/// shipment lookup used by the scanner (orders/awb) and the route
/// sequencer (sequencer-odd-orders). Nothing here is sent to the server.
Future<void> showLocationSourcesSheet(
  BuildContext context,
  TaskItem task, {
  String? savedSession,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _LocationSourcesSheet(task: task, savedSession: savedSession),
  );
}

class _LocationSourcesSheet extends StatefulWidget {
  final TaskItem task;
  final String? savedSession;
  const _LocationSourcesSheet({required this.task, this.savedSession});

  @override
  State<_LocationSourcesSheet> createState() => _LocationSourcesSheetState();
}

class _LocationSourcesSheetState extends State<_LocationSourcesSheet> {
  late final List<LocationSource> _sources = _tagged(
    'tasks',
    LocationSources.find(widget.task.raw),
  );
  CorrectedLocation? _correction;
  bool _busy = false;
  bool _fetching = false;
  final List<String> _fetchNotes = [];

  static List<LocationSource> _tagged(
    String origin,
    List<LocationSource> sources,
  ) =>
      [
        for (final s in sources)
          LocationSource(
            path: '[$origin] ${s.path}',
            location: s.location,
            rawText: s.rawText,
          ),
      ];

  bool _matchesTask(Map<String, dynamic> order) {
    final task = widget.task;
    final keys = <String>{
      task.id.trim(),
      task.realAwb.trim(),
      task.displayReference.trim(),
    }..remove('');
    for (final field in const ['order_id', 'id', 'order_awb', 'awb']) {
      final value = order[field]?.toString().trim() ?? '';
      if (value.isNotEmpty && keys.contains(value)) return true;
    }
    return false;
  }

  /// Read-only GET requests; they do not change anything in SLS.
  Future<void> _fetchServerSources() async {
    final session = widget.savedSession;
    if (session == null || session.isEmpty) return;
    setState(() => _fetching = true);
    final api = ScanApiService(savedSession: session);
    final found = <LocationSource>[];
    final notes = <String>[];

    final awb = widget.task.realAwb.trim();
    if (awb.isNotEmpty) {
      try {
        final shipment = await api.scanOrder(awb);
        found.addAll(_tagged('awb', LocationSources.find(shipment.raw)));
      } catch (error) {
        notes.add('orders/awb: $error');
      }
    }
    try {
      final orders = await api.getSequencerOddOrders();
      final matches = orders.where((o) => _matchesTask(o.raw)).toList();
      if (matches.isEmpty) notes.add('sequencer: الشحنة غير موجودة في المسار');
      for (final order in matches) {
        found.addAll(_tagged('sequencer', LocationSources.find(order.raw)));
      }
    } catch (error) {
      notes.add('sequencer: $error');
    }

    if (!mounted) return;
    setState(() {
      _sources.addAll(found);
      _fetchNotes
        ..clear()
        ..addAll(notes);
      _fetching = false;
    });
  }

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
    _fetchServerSources();
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
      for (final note in _fetchNotes) '! $note',
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
            if (_busy || _fetching)
              const LinearProgressIndicator(minHeight: 2),
            if (_fetching)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'جاري جلب الموقع من بيانات مسح الشحنة والمسار…',
                  style: TextStyle(fontSize: 12),
                ),
              ),
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
