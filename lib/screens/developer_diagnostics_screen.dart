import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/developer_diagnostics_service.dart';

/// Everything the app sent to and received from the SLS server in this
/// session (last 40 requests), plus summaries such as /tasks and submit
/// timings. Tokens, cookies and passwords are masked.
class DeveloperDiagnosticsScreen extends StatefulWidget {
  const DeveloperDiagnosticsScreen({super.key});

  @override
  State<DeveloperDiagnosticsScreen> createState() =>
      _DeveloperDiagnosticsScreenState();
}

class _DeveloperDiagnosticsScreenState
    extends State<DeveloperDiagnosticsScreen> {
  final _service = DeveloperDiagnosticsService.instance;
  String _query = '';

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  String _summariesReport() => [
        for (final item in _service.context.value.entries)
          '## ${item.key}\n${item.value}',
      ].join('\n\n');

  String _fullReport(List<DiagnosticEntry> entries) => [
        _summariesReport(),
        for (final entry in entries) entry.toReport(),
      ].join('\n\n');

  bool _matches(DiagnosticEntry entry) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return entry.url.toLowerCase().contains(q) ||
        entry.method.toLowerCase().contains(q) ||
        '${entry.statusCode}'.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تشخيص المطوّر'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'نسخ',
              icon: const Icon(Icons.copy_all_rounded),
              onSelected: (value) {
                if (value == 'summaries') {
                  _copy(_summariesReport(), 'تم نسخ الملخصات');
                } else {
                  _copy(
                    _fullReport(_service.entries.value),
                    'تم نسخ كل شيء (الملخصات وجميع الطلبات)',
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'summaries',
                  child: Text('نسخ الملخصات فقط'),
                ),
                PopupMenuItem(
                  value: 'all',
                  child: Text('نسخ كل شيء مع الطلبات والردود'),
                ),
              ],
            ),
            IconButton(
              onPressed: _service.clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'مسح السجل',
            ),
          ],
        ),
        body: ValueListenableBuilder<Map<String, String>>(
          valueListenable: _service.context,
          builder: (context, values, _) {
            return ValueListenableBuilder<List<DiagnosticEntry>>(
              valueListenable: _service.entries,
              builder: (context, entries, _) {
                final shown = entries.reversed.where(_matches).toList();
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'كل ما أرسله البرنامج للسيرفر وما رجع منه في هذه الجلسة '
                          '(آخر 40 طلبًا). التوكنات والكوكي وكلمات المرور مخفية. '
                          'يُمسح السجل عند إغلاق البرنامج.',
                        ),
                      ),
                    ),
                    if (values.isNotEmpty) ...[
                      const _Header('الملخصات'),
                      for (final item in values.entries)
                        _CollapsibleText(title: item.key, value: item.value),
                    ],
                    _Header('الطلبات (${shown.length} من ${entries.length})'),
                    TextField(
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'بحث: tasks, orders/awb, bulk/status, 500…',
                        isDense: true,
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('لا توجد طلبات مسجلة.')),
                      ),
                    for (final entry in shown)
                      _RequestCard(
                        entry: entry,
                        onCopy: () =>
                            _copy(entry.toReport(), 'تم نسخ الطلب والرد'),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );
}

class _RequestCard extends StatelessWidget {
  final DiagnosticEntry entry;
  final VoidCallback onCopy;
  const _RequestCard({required this.entry, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final status = entry.statusCode;
    final ok = entry.error == null && status != null && status < 400;
    final time = TimeOfDay.fromDateTime(entry.timestamp).format(context);
    final path = Uri.tryParse(entry.url)?.path ?? entry.url;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? Colors.green : Colors.red,
        ),
        title: Text(
          '${entry.method} ${status ?? '—'}  $path',
          textDirection: TextDirection.ltr,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$time'
          '${entry.duration == null ? '' : '  •  ${entry.duration!.inMilliseconds}ms'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('نسخ الطلب والرد'),
            ),
          ),
          _CollapsibleText(title: 'URL', value: entry.url),
          _CollapsibleText(title: 'Payload', value: entry.prettyPayload),
          _CollapsibleText(title: 'Response', value: entry.prettyResponse),
          if (entry.error != null)
            _CollapsibleText(title: 'Exception', value: entry.error!),
        ],
      ),
    );
  }
}

/// Long server replies are cut to keep the screen fast; "show all" reveals
/// the rest, and copy always copies the full text.
class _CollapsibleText extends StatefulWidget {
  final String title;
  final String value;
  const _CollapsibleText({required this.title, required this.value});

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  static const _preview = 4000;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.value.length > _preview;
    final text = long && !_expanded
        ? '${widget.value.substring(0, _preview)}\n…'
        : widget.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.value));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم نسخ ${widget.title}')),
                  );
                },
              ),
            ],
          ),
          SelectableText(
            text,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (long)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? 'عرض أقل'
                      : 'عرض الكل (${(widget.value.length / 1024).toStringAsFixed(0)} KB)',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
