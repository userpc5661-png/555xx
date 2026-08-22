import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../services/delivery_history_store.dart';
import '../theme/theme_controller.dart';
import 'developer_diagnostics_screen.dart';

class SettingsScreen extends StatelessWidget {
  final List<TaskItem> tasks;
  const SettingsScreen({super.key, this.tasks = const []});

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
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('التحصيل'),
              subtitle: const Text('محفظة الكاش والمبالغ المحصلة والمتبقية'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CollectionWalletScreen(tasks: tasks)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              title: Text(dark ? 'الوضع الفاتح' : 'الوضع الداكن'),
              onTap: () => ThemeController.instance.toggle(context),
            ),
            if (kDebugMode)
              ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text('تشخيص المطوّر'),
                subtitle: const Text('متاح في وضع Debug فقط'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeveloperDiagnosticsScreen()),
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
      for (final task in widget.tasks) task.displayReference: task,
    };
    final collectedHistory = _history.where((record) => record.collected).toList();
    final collectedAwbs = collectedHistory.map((record) => record.awb).toSet();

    final currentCash = widget.tasks
        .where((task) => task.isCashOnDelivery && !collectedAwbs.contains(task.displayReference))
        .toList();
    final serverCompletedCash = currentCash
        .where((task) => task.progress == TaskProgress.completed && (task.codAmount ?? 0) > 0)
        .toList();

    final total = currentCash.fold<double>(0, (sum, task) => sum + (task.codAmount ?? 0)) +
        collectedHistory.fold<double>(0, (sum, record) => sum + record.codAmount);
    final collected = serverCompletedCash.fold<double>(0, (sum, task) => sum + (task.codAmount ?? 0)) +
        collectedHistory.fold<double>(0, (sum, record) => sum + record.codAmount);
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
              _WalletMetric(title: 'إجمالي المطلوب', value: _money(total), icon: Icons.payments_outlined),
              _WalletMetric(title: 'تم تحصيله', value: _money(collected), icon: Icons.check_circle_outline),
              _WalletMetric(title: 'المتبقي', value: _money(remaining), icon: Icons.pending_actions_outlined),
              _WalletMetric(title: 'عدد شحنات الكاش', value: '$cashCount', icon: Icons.inventory_2_outlined),
              _WalletMetric(title: 'الشحنات المحصلة', value: '$collectedCount', icon: Icons.receipt_long_outlined),
              const SizedBox(height: 16),
              Text('سجل التحصيل', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (collectedCount == 0)
                const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد شحنات كاش محصلة حتى الآن'))))
              else ...[
                ...serverCompletedCash.map((task) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.payments)),
                        title: Text(task.customerName.isEmpty ? task.displayReference : task.customerName),
                        subtitle: Text(task.displayReference),
                        trailing: Text(_money(task.codAmount ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    )),
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
                      trailing: Text(_money(record.codAmount), style: const TextStyle(fontWeight: FontWeight.bold)),
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
  const _WalletMetric({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      );
}
