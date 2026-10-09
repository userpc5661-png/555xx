import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../services/delivery_history_store.dart';
import '../services/driver_preferences_store.dart';
import '../services/shipment_outcome_tracker.dart';
import '../theme/theme_controller.dart';
import 'account_info_screen.dart';
import 'developer_diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  final List<TaskItem> tasks;
  final String token;
  const SettingsScreen({super.key, this.tasks = const [], this.token = ''});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _driverWhatsApp;

  @override
  void initState() {
    super.initState();
    _loadDriverWhatsApp();
  }

  Future<void> _loadDriverWhatsApp() async {
    final value = await DriverPreferencesStore.instance.readWhatsAppNumber();
    if (mounted) setState(() => _driverWhatsApp = value);
  }

  Future<void> _editDriverWhatsApp() async {
    final controller = TextEditingController(text: _driverWhatsApp ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رقم واتساب المندوب'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: '05xxxxxxxx أو +9665xxxxxxxx',
            helperText: 'يُحفظ محليًا لهذا الحساب ولا يُرسل إلى SLS.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final saved = await DriverPreferencesStore.instance.saveWhatsAppNumber(
      value,
    );
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رقم جوال سعودي صحيح.')),
      );
      return;
    }
    await _loadDriverWhatsApp();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('معلومات الحساب'),
              subtitle: const Text('اللي يرسله سيرفر SLS عن حسابك'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountInfoScreen(token: widget.token),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('التحصيل'),
              subtitle: const Text('محفظة الكاش والمبالغ المحصلة والمتبقية'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CollectionWalletScreen(tasks: widget.tasks),
                ),
              ),
            ),
            const Divider(height: 1),
            _ServerStatsCard(tasks: widget.tasks),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('رقم واتساب المندوب'),
              subtitle: Text(
                _driverWhatsApp ??
                    'مطلوب لإضافة رابط واتساب داخل رسالة العميل النصية',
                textDirection: _driverWhatsApp == null
                    ? TextDirection.rtl
                    : TextDirection.ltr,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editDriverWhatsApp,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              title: Text(dark ? 'الوضع الفاتح' : 'الوضع الداكن'),
              onTap: () => ThemeController.instance.toggle(context),
            ),
            ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('تشخيص المطوّر'),
                subtitle: const Text('طلبات السيرفر وملخص المهام وأوقات الإرسال'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeveloperDiagnosticsScreen(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CollectionWalletScreen extends StatefulWidget {
  final List<TaskItem> tasks;
  const CollectionWalletScreen({super.key, required this.tasks});

  @override
  State<CollectionWalletScreen> createState() => _CollectionWalletScreenState();
}

class _CollectionWalletScreenState extends State<CollectionWalletScreen> {
  List<DeliveryHistoryRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final history = await DeliveryHistoryStore.instance.today();
    if (mounted) setState(() => _history = history);
  }

  String _money(double value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    return '$text ريال';
  }

  @override
  Widget build(BuildContext context) {
    final currentByAwb = <String, TaskItem>{
      for (final task in widget.tasks) ...{
        task.displayReference: task,
        if (task.realAwb.trim().isNotEmpty) task.realAwb.trim(): task,
      },
    };
    final collectedHistory = _history
        .where((record) => record.collected)
        .toList();
    final collectedAwbs = collectedHistory.map((record) => record.awb).toSet();

    final currentCash = widget.tasks
        .where(
          (task) =>
              task.isCashOnDelivery &&
              !collectedAwbs.contains(task.realAwb.trim()) &&
              !collectedAwbs.contains(task.displayReference),
        )
        .toList();
    final serverCompletedCash = currentCash
        .where(
          (task) =>
              task.progress == TaskProgress.completed &&
              (task.codAmount ?? 0) > 0,
        )
        .toList();

    final total =
        currentCash.fold<double>(
          0,
          (sum, task) => sum + (task.codAmount ?? 0),
        ) +
        collectedHistory.fold<double>(
          0,
          (sum, record) => sum + record.codAmount,
        );
    final collected =
        serverCompletedCash.fold<double>(
          0,
          (sum, task) => sum + (task.codAmount ?? 0),
        ) +
        collectedHistory.fold<double>(
          0,
          (sum, record) => sum + record.codAmount,
        );
    final remaining = (total - collected).clamp(0, double.infinity).toDouble();
    final cashCount = currentCash.length + collectedHistory.length;
    final collectedCount = serverCompletedCash.length + collectedHistory.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التحصيل')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _WalletMetric(
                title: 'إجمالي المطلوب',
                value: _money(total),
                icon: Icons.payments_outlined,
              ),
              _WalletMetric(
                title: 'تم تحصيله',
                value: _money(collected),
                icon: Icons.check_circle_outline,
              ),
              _WalletMetric(
                title: 'المتبقي',
                value: _money(remaining),
                icon: Icons.pending_actions_outlined,
              ),
              _WalletMetric(
                title: 'عدد شحنات الكاش',
                value: '$cashCount',
                icon: Icons.inventory_2_outlined,
              ),
              _WalletMetric(
                title: 'الشحنات المحصلة',
                value: '$collectedCount',
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 16),
              Text(
                'سجل التحصيل',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (collectedCount == 0)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('لا توجد شحنات كاش محصلة حتى الآن'),
                    ),
                  ),
                )
              else ...[
                ...serverCompletedCash.map(
                  (task) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.payments)),
                      title: Text(
                        task.customerName.isEmpty
                            ? task.displayReference
                            : task.customerName,
                      ),
                      subtitle: Text(task.displayReference),
                      trailing: Text(
                        _money(task.codAmount ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                ...collectedHistory.map((record) {
                  final current = currentByAwb[record.awb];
                  final name = record.customerName.trim().isNotEmpty
                      ? record.customerName
                      : (current?.customerName ?? '');
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.payments)),
                      title: Text(name.isEmpty ? record.awb : name),
                      subtitle: Text(record.awb),
                      trailing: Text(
                        _money(record.codAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _WalletMetric({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

class _ServerStatsCard extends StatefulWidget {
  final List<TaskItem> tasks;
  const _ServerStatsCard({required this.tasks});

  @override
  State<_ServerStatsCard> createState() => _ServerStatsCardState();
}

class _ServerStatsCardState extends State<_ServerStatsCard> {
  OutcomeCounts? _counts;

  @override
  void initState() {
    super.initState();
    ShipmentOutcomeTracker.instance.revision.addListener(_loadStats);
    _loadStats();
  }

  @override
  void dispose() {
    ShipmentOutcomeTracker.instance.revision.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final counts =
        await ShipmentOutcomeTracker.instance.countsFor(widget.tasks);
    if (mounted) setState(() => _counts = counts);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: ExpansionTile(
          leading: const Icon(Icons.analytics_outlined, color: Colors.blue),
          title: const Text(
            'إحصائيات الشحنات والتوصيل',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('توصيل اليوم: ${counts?.deliveredToday ?? '…'} شحنة'),
          children: [
            if (counts == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _StatRow(
                      title: 'تم التوصيل اليوم',
                      value: '${counts.deliveredToday}',
                      icon: Icons.today_outlined,
                      color: Colors.green,
                    ),
                    const Divider(),
                    _StatRow(
                      title: 'مغلقة اليوم (ملغاة/مرتجعة/لم تُسلَّم)',
                      value: '${counts.closedToday}',
                      icon: Icons.block_outlined,
                      color: Colors.red,
                    ),
                    const Divider(),
                    _StatRow(
                      title: 'تم التوصيل من بداية الشهر',
                      value: '${counts.deliveredMonth}',
                      icon: Icons.calendar_month_outlined,
                      color: Colors.blue,
                    ),
                    const Divider(),
                    _StatRow(
                      title: 'مغلقة من بداية الشهر',
                      value: '${counts.closedMonth}',
                      icon: Icons.event_busy_outlined,
                      color: Colors.deepOrange,
                    ),
                    const Divider(),
                    _StatRow(
                      title: 'شحنات معك الآن',
                      value: '${widget.tasks.length}',
                      icon: Icons.local_shipping_outlined,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تُحسب من السيرفر لكل شحنة ظهرت في مهامك، حتى لو وُصّلت '
                      'من التطبيق الرسمي. تبدأ من تاريخ تثبيت هذه النسخة.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _StatRow({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

