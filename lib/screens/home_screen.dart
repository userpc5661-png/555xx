import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre/maplibre.dart' as ml;
import '../models/task_item.dart';
import '../services/api_service.dart';
import '../services/navigation_service.dart';
import '../services/location_correction_service.dart';
import '../services/token_store.dart';
import '../theme/theme_controller.dart';
import '../widgets/task_card.dart';
import '../services/local_contact_controller.dart';
import '../services/local_contact_store.dart';
import '../services/local_shipment_status_store.dart';
import '../services/delivery_history_store.dart';
import 'login_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String token;

  const HomeScreen({super.key, required this.token});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  final _store = TokenStore();
  late final LocalContactController _contactController;

  List<TaskItem> _tasks = const [];
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  int _index = 0;

  void _setIndex(int index) {
    if (mounted) {
      setState(() {
        _index = index;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _contactController = LocalContactController(
      onUpdate: () {
        if (mounted) setState(() {});
      },
    );
    _loadTasks();
  }

  @override
  void dispose() {
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final hasExistingData = _tasks.isNotEmpty;
    if (mounted) {
      setState(() {
        _error = null;
        _loading = !hasExistingData;
        _refreshing = hasExistingData;
      });
    }

    try {
      final tasks = await _api.fetchTasks(widget.token);
      if (!mounted) return;

      final activeKeys = tasks
          .map((t) => '${t.referenceNumber}_${t.id}')
          .toList();
      final deliveredKeys = tasks
          .where((t) => t.progress == TaskProgress.completed)
          .map((t) => '${t.referenceNumber}_${t.id}')
          .toList();

      await LocalContactStore.instance.cleanup(activeKeys, deliveredKeys);
      await LocalShipmentStatusStore.instance.cleanup(deliveredKeys);
      _contactController.updateActiveKeys(activeKeys);
      _contactController.scheduleNextReminder();

      setState(() {
        _tasks = tasks;
        _error = null;
      });
    } catch (error) {
      if (error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        await _store.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
      });
      if (hasExistingData) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _handleScanCompleted() async {
    await _loadTasks();
    if (!mounted) return;
    setState(() => _index = 1);
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SettingsScreen(tasks: _tasks)));
  }

  Future<void> _logout() async {
    await _store.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'الرئيسية',
      'قائمة المهام',
      'خريطة الشحنات',
      'الماسح الضوئي',
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            titles[_index],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              onPressed: () => ThemeController.instance.toggle(context),
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 20,
              ),
            ),
            IconButton(
              onPressed: _refreshing ? null : _loadTasks,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (value) {
                if (value == 'settings') _openSettings();
                if (value == 'logout') _logout();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.settings_rounded),
                    title: Text('الإعدادات'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.logout_rounded, color: Colors.red),
                    title: Text('خروج', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: NavigationBar(
          elevation: 0,
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_list_outlined),
              selectedIcon: Icon(Icons.view_list_rounded),
              label: 'المهام',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'الخريطة',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_rounded),
              selectedIcon: Icon(Icons.qr_code_2_rounded),
              label: 'المسح',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _tasks.isEmpty) {
      return _RequestState(
        icon: Icons.cloud_off,
        message: _error.toString(),
        onRetry: _loadTasks,
        onDebug: null,
      );
    }

    return Stack(
      children: [
        IndexedStack(
          index: _index,
          children: [
            _DashboardPage(tasks: _tasks, onRefresh: _loadTasks),
            _TasksPage(
              tasks: _tasks,
              onRefresh: _loadTasks,
              savedSession: widget.token,
              contactController: _contactController,
            ),
            _MapPage(
              tasks: _tasks,
              active: _index == 2,
              savedSession: widget.token,
              onUpdated: _loadTasks,
              contactController: _contactController,
            ),
            _ScannerTab(token: widget.token, onChanged: _handleScanCompleted),
          ],
        ),
        if (_refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _DashboardPage extends StatefulWidget {
  final List<TaskItem> tasks;
  final Future<void> Function() onRefresh;

  const _DashboardPage({required this.tasks, required this.onRefresh});

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  List<DeliveryHistoryRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant _DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await DeliveryHistoryStore.instance.today();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _refresh() async {
    await widget.onRefresh();
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.tasks
        .where((task) => task.progress == TaskProgress.remaining)
        .length;
    final serverCompleted = widget.tasks
        .where((task) => task.progress == TaskProgress.completed)
        .length;
    // History records are stored by realAwb (falling back to displayReference).
    final currentAwbs = {
      for (final task in widget.tasks) ...[
        task.realAwb.trim(),
        task.displayReference,
      ],
    };
    final localCompleted = _history
        .where((record) => !currentAwbs.contains(record.awb))
        .length;
    final completed = serverCompleted + localCompleted;
    final cash = widget.tasks
        .where((t) => t.paymentKind == PaymentKind.cashOnDelivery)
        .length;
    final prepaid = widget.tasks
        .where((t) => t.paymentKind == PaymentKind.prepaid)
        .length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _WelcomeCard(
            total: widget.tasks.length + localCompleted,
            remaining: remaining,
          ),
          const SizedBox(height: 24),

          // القسم السريع للعمليات المهمة
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  title: 'مسح باركود',
                  icon: Icons.qr_code_scanner_rounded,
                  onTap: () {
                    // الانتقال لتبويب المسح
                    final state = context
                        .findAncestorStateOfType<_HomeScreenState>();
                    state?._setIndex(3);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionButton(
                  title: 'عرض الخريطة',
                  icon: Icons.map_rounded,
                  onTap: () {
                    // الانتقال لتبويب الخريطة
                    final state = context
                        .findAncestorStateOfType<_HomeScreenState>();
                    state?._setIndex(2);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
          Text(
            'حالة العمل اليوم',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _MetricCard(
                title: 'شحنات منجزة',
                value: '$completed',
                icon: Icons.check_circle_rounded,
                color: Colors.green,
              ),
              _MetricCard(
                title: 'شحنات متبقية',
                value: '$remaining',
                icon: Icons.pending_rounded,
                color: Colors.orange,
              ),
            ],
          ),

          const SizedBox(height: 24),
          _SummaryListTile(
            title: 'إجمالي الشحنات',
            value: '${widget.tasks.length + localCompleted}',
            icon: Icons.inventory_2_rounded,
          ),
          _SummaryListTile(
            title: 'شحنات الكاش',
            value: '$cash',
            icon: Icons.payments_rounded,
          ),
          _SummaryListTile(
            title: 'الشحنات المدفوعة',
            value: '$prepaid',
            icon: Icons.credit_card_rounded,
          ),
          _SummaryListTile(
            title: 'الموقع محدد',
            value: '${widget.tasks.where((t) => t.hasCoordinates).length}',
            icon: Icons.location_on_rounded,
          ),

          if (widget.tasks.isEmpty && !remaining.isNegative) ...[
            const SizedBox(height: 40),
            Opacity(
              opacity: 0.5,
              child: Column(
                children: const [
                  Icon(Icons.inbox_rounded, size: 64),
                  SizedBox(height: 8),
                  Text('لا توجد بيانات حالياً'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.green.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryListTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryListTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final int total;
  final int remaining;

  const _WelcomeCard({required this.total, required this.remaining});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'أهلاً بك، كابتن',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  remaining == 0 ? 'أنهيت جميع مهامك!' : 'لديك $remaining شحنة',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (remaining > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'من أصل $total اليوم',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.local_shipping_rounded,
            size: 50,
            color: Colors.white24,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.03),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

enum _ContactTaskFilter { all, notContacted, answered, noAnswer }

enum _PaymentTaskFilter { all, cash, prepaid }

enum _LocalTaskFilter {
  active,
  all,
  anyLocal,
  customerCancelled,
  rescheduled,
  wrongLocation,
  wrongPhone,
  noAnswer,
}

class _TasksPage extends StatefulWidget {
  final List<TaskItem> tasks;
  final Future<void> Function() onRefresh;
  final String savedSession;
  final LocalContactController contactController;

  const _TasksPage({
    required this.tasks,
    required this.onRefresh,
    required this.savedSession,
    required this.contactController,
  });

  @override
  State<_TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<_TasksPage> {
  final _searchController = TextEditingController();
  String _query = '';
  Map<String, LocalContactData> _contactData = {};
  Map<String, LocalShipmentStatus> _localStatuses = {};
  _ContactTaskFilter _contactFilter = _ContactTaskFilter.all;
  _PaymentTaskFilter _paymentFilter = _PaymentTaskFilter.all;
  _LocalTaskFilter _localFilter = _LocalTaskFilter.active;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final data = await LocalContactStore.instance.getAll();
    final statuses = await LocalShipmentStatusStore.instance.getAll();
    if (mounted) {
      setState(() {
        _contactData = data;
        _localStatuses = statuses;
      });
    }
  }

  String _taskKey(TaskItem task) => '${task.referenceNumber}_${task.id}';

  bool _matchesContact(TaskItem task) {
    final status = _contactData[_taskKey(task)]?.status ?? 'not_contacted';
    return switch (_contactFilter) {
      _ContactTaskFilter.all => true,
      _ContactTaskFilter.notContacted => status == 'not_contacted',
      _ContactTaskFilter.answered => status == 'answered',
      _ContactTaskFilter.noAnswer => status == 'no_answer',
    };
  }

  bool _matchesPayment(TaskItem task) => switch (_paymentFilter) {
    _PaymentTaskFilter.all => true,
    _PaymentTaskFilter.cash => task.paymentKind == PaymentKind.cashOnDelivery,
    _PaymentTaskFilter.prepaid => task.paymentKind == PaymentKind.prepaid,
  };

  bool _matchesLocalStatus(TaskItem task) {
    final local = _localStatuses[_taskKey(task)];
    return switch (_localFilter) {
      _LocalTaskFilter.active => local == null,
      _LocalTaskFilter.all => true,
      _LocalTaskFilter.anyLocal => local != null,
      _LocalTaskFilter.customerCancelled =>
        local?.statusKey == 'customer_cancelled',
      _LocalTaskFilter.rescheduled => local?.statusKey == 'rescheduled',
      _LocalTaskFilter.wrongLocation => local?.statusKey == 'wrong_location',
      _LocalTaskFilter.wrongPhone => local?.statusKey == 'wrong_phone',
      _LocalTaskFilter.noAnswer => local?.statusKey == 'no_answer',
    };
  }

  int get _activeFilterCount =>
      (_contactFilter == _ContactTaskFilter.all ? 0 : 1) +
      (_paymentFilter == _PaymentTaskFilter.all ? 0 : 1) +
      (_localFilter == _LocalTaskFilter.active ? 0 : 1);

  Future<void> _showFilters() async {
    var contact = _contactFilter;
    var payment = _paymentFilter;
    var local = _localFilter;
    final result =
        await showModalBottomSheet<
          (_ContactTaskFilter, _PaymentTaskFilter, _LocalTaskFilter)
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تصفية المهام',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'حالة التواصل',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: contact == _ContactTaskFilter.all,
                          onSelected: (_) => setSheetState(
                            () => contact = _ContactTaskFilter.all,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('لم يتم التواصل'),
                          selected: contact == _ContactTaskFilter.notContacted,
                          onSelected: (_) => setSheetState(
                            () => contact = _ContactTaskFilter.notContacted,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('أجاب العميل'),
                          selected: contact == _ContactTaskFilter.answered,
                          onSelected: (_) => setSheetState(
                            () => contact = _ContactTaskFilter.answered,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('لم يجب'),
                          selected: contact == _ContactTaskFilter.noAnswer,
                          onSelected: (_) => setSheetState(
                            () => contact = _ContactTaskFilter.noAnswer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'طريقة الدفع',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: payment == _PaymentTaskFilter.all,
                          onSelected: (_) => setSheetState(
                            () => payment = _PaymentTaskFilter.all,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('كاش'),
                          selected: payment == _PaymentTaskFilter.cash,
                          onSelected: (_) => setSheetState(
                            () => payment = _PaymentTaskFilter.cash,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('مدفوع'),
                          selected: payment == _PaymentTaskFilter.prepaid,
                          onSelected: (_) => setSheetState(
                            () => payment = _PaymentTaskFilter.prepaid,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'الحالة المحلية',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('النشطة'),
                          selected: local == _LocalTaskFilter.active,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.active,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: local == _LocalTaskFilter.all,
                          onSelected: (_) =>
                              setSheetState(() => local = _LocalTaskFilter.all),
                        ),
                        ChoiceChip(
                          label: const Text('كل الحالات المحلية'),
                          selected: local == _LocalTaskFilter.anyLocal,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.anyLocal,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('ألغى الطلبية'),
                          selected: local == _LocalTaskFilter.customerCancelled,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.customerCancelled,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('إعادة الجدولة'),
                          selected: local == _LocalTaskFilter.rescheduled,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.rescheduled,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('الموقع غير صحيح'),
                          selected: local == _LocalTaskFilter.wrongLocation,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.wrongLocation,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('رقم خاطئ'),
                          selected: local == _LocalTaskFilter.wrongPhone,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.wrongPhone,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('لم يجب'),
                          selected: local == _LocalTaskFilter.noAnswer,
                          onSelected: (_) => setSheetState(
                            () => local = _LocalTaskFilter.noAnswer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              contact = _ContactTaskFilter.all;
                              payment = _PaymentTaskFilter.all;
                              local = _LocalTaskFilter.active;
                              setSheetState(() {});
                            },
                            child: const Text('إعادة الافتراضي'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, (
                              contact,
                              payment,
                              local,
                            )),
                            child: const Text('عرض النتائج'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      _contactFilter = result.$1;
      _paymentFilter = result.$2;
      _localFilter = result.$3;
    });
  }

  TaskCard _taskCard(TaskItem task) {
    final key = _taskKey(task);
    return TaskCard(
      task: task,
      savedSession: widget.savedSession,
      onUpdated: () async {
        await widget.onRefresh();
        await _loadLocalData();
      },
      contactController: widget.contactController,
      contactData: _contactData[key],
      localStatus: _localStatuses[key],
      onLocalStatusChanged: () async {
        await _loadLocalData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.tasks.where((task) {
      final searchable =
          '${task.referenceNumber} ${task.id} '
                  '${task.storeName} ${task.customerName} ${task.customerPhone} ${task.address}'
              .toLowerCase();
      final matchesSearch = _query.isEmpty || searchable.contains(_query);
      return matchesSearch &&
          _matchesContact(task) &&
          _matchesPayment(task) &&
          _matchesLocalStatus(task);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'ابحث برقم الشحنة أو المتجر أو العميل أو الجوال',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                        FocusScope.of(context).unfocus();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              Expanded(child: Text('النتائج: ${items.length}')),
              FilledButton.tonalIcon(
                onPressed: _showFilters,
                icon: Badge(
                  isLabelVisible: _activeFilterCount > 0,
                  label: Text('$_activeFilterCount'),
                  child: const Icon(Icons.tune_rounded),
                ),
                label: const Text('تصفية'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await widget.onRefresh();
              await _loadLocalData();
            },
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Icon(
                        Icons.filter_alt_off_outlined,
                        size: 52,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 12),
                      Center(child: Text('لا توجد مهام تطابق هذه الفلاتر')),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _taskCard(items[index]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterStrip extends StatelessWidget {
  final List<Widget> children;

  const _FilterStrip({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: children.map((child) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: child,
          );
        }).toList(),
      ),
    );
  }
}

class _MapPage extends StatefulWidget {
  final List<TaskItem> tasks;
  final bool active;
  final String savedSession;
  final Future<void> Function() onUpdated;
  final LocalContactController contactController;

  const _MapPage({
    required this.tasks,
    required this.active,
    required this.savedSession,
    required this.onUpdated,
    required this.contactController,
  });

  @override
  State<_MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<_MapPage> {
  Map<String, LocalContactData> _contactData = {};
  Map<String, LocalShipmentStatus> _localStatuses = {};
  PaymentKind? _paymentFilter;
  TaskProgress? _progressFilter;

  ml.MapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Position? _currentPosition;
  double _displayHeading = 0;
  bool _hasHeading = false;
  DateTime? _lastCompassCameraUpdate;
  bool _mapReady = false;
  bool _locating = true;
  bool _followUser = true;
  bool _hasCenteredOnUser = false;
  String? _locationError;
  final Map<String, CorrectedLocation> _corrections = {};
  int _correctionsGeneration = 0;

  String _correctionKey(TaskItem task) =>
      LocationCorrectionService.shipmentKey(task);

  Future<void> _loadMapContactData() async {
    final data = await LocalContactStore.instance.getAll();
    if (mounted) setState(() => _contactData = data);
  }

  Future<void> _loadLocalStatuses() async {
    final data = await LocalShipmentStatusStore.instance.getAll();
    if (mounted) setState(() => _localStatuses = data);
  }

  Future<void> _loadCorrections() async {
    // A newer load or a local edit supersedes this one; dropping its result
    // keeps a slow, older read from putting a marker back at its old place.
    final generation = ++_correctionsGeneration;
    final tasks = widget.tasks;
    final results = await Future.wait(tasks.map(LocationCorrectionService.load));
    final loaded = <String, CorrectedLocation>{
      for (var i = 0; i < tasks.length; i++)
        if (results[i] case final correction?)
          _correctionKey(tasks[i]): correction,
    };
    if (!mounted || generation != _correctionsGeneration) return;
    setState(() {
      _corrections
        ..clear()
        ..addAll(loaded);
    });
  }

  void _onCorrectionChanged() {
    final change = LocationCorrectionService.changes.value;
    if (change == null || !mounted) return;
    _correctionsGeneration++;
    setState(() {
      final location = change.location;
      if (location == null) {
        _corrections.remove(change.shipmentKey);
      } else {
        _corrections[change.shipmentKey] = location;
      }
    });
  }

  /// Latest copy of [task] after a refresh, so open sheets show fresh data.
  TaskItem _currentTask(TaskItem task) {
    final key = '${task.referenceNumber}_${task.id}';
    for (final current in widget.tasks) {
      if ('${current.referenceNumber}_${current.id}' == key) return current;
    }
    return task;
  }

  CorrectedLocation? _effectiveLocation(TaskItem task) {
    final corrected = _corrections[_correctionKey(task)];
    if (corrected != null) return corrected;
    if (task.latitude == null || task.longitude == null) return null;
    return CorrectedLocation(task.latitude!, task.longitude!);
  }

  @override
  void initState() {
    super.initState();
    LocationCorrectionService.changes.addListener(_onCorrectionChanged);
    _loadCorrections();
    _loadMapContactData();
    _loadLocalStatuses();
    if (widget.active) {
      _startLiveLocation();
    } else {
      _locating = false;
    }
  }

  @override
  void didUpdateWidget(covariant _MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadMapContactData();
    _loadLocalStatuses();
    if (oldWidget.tasks != widget.tasks) {
      _loadCorrections();
    }
    if (!oldWidget.active && widget.active) {
      _startLiveLocation();
    } else if (oldWidget.active && !widget.active) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _compassSubscription?.cancel();
      _compassSubscription = null;
      _followUser = false;
    }
  }

  @override
  void dispose() {
    LocationCorrectionService.changes.removeListener(_onCorrectionChanged);
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLiveLocation() async {
    await _positionSubscription?.cancel();
    await _compassSubscription?.cancel();
    _positionSubscription = null;
    _compassSubscription = null;
    if (mounted) {
      setState(() {
        _locating = true;
        _followUser = true;
        _locationError = null;
      });
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError = 'خدمة الموقع متوقفة. فعّل GPS ثم أعد المحاولة.';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError =
            'صلاحية الموقع مرفوضة نهائيًا. فعّلها من إعدادات التطبيق.';
      });
      return;
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError =
            'اسمح للتطبيق باستخدام موقعك لعرضه مباشرة على الخريطة.';
      });
      return;
    }
    _startCompass();

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null && mounted) {
      _updateHeadingFromGps(lastKnown);
      setState(() {
        _currentPosition = lastKnown;
        _locating = false;
      });
      _followPosition(lastKnown, firstFix: true);
    }

    if (!mounted || !widget.active) return;
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _liveLocationSettings(),
        ).listen(
          (position) {
            if (!mounted || !widget.active) return;
            _updateHeadingFromGps(position);
            setState(() {
              _currentPosition = position;
              _locating = false;
              _locationError = null;
            });
            _followPosition(position);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _locating = false;
              _locationError = 'توقف تحديث الموقع المباشر: $error';
            });
          },
        );

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted || !widget.active) return;
      if (mounted) {
        _updateHeadingFromGps(current);
        setState(() {
          _currentPosition = current;
          _locating = false;
          _locationError = null;
        });
      }
      _followPosition(current, firstFix: true);
    } catch (_) {
      if (_currentPosition == null && mounted) {
        setState(() {
          _locating = false;
          _locationError =
              'تعذر تحديد موقعك الآن. تأكد أنك في مكان تصل إليه إشارة GPS.';
        });
      }
    }
  }

  LocationSettings _liveLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 250),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  void _startCompass() {
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSubscription = events.listen((event) {
      if (!mounted || !widget.active) return;
      final position = _currentPosition;
      final gpsHeadingIsReliable =
          position != null &&
          position.speed.isFinite &&
          position.speed >= 1.4 &&
          position.heading.isFinite &&
          position.heading >= 0;
      if (gpsHeadingIsReliable) return;

      final rawHeading = event.heading;
      if (rawHeading == null || !rawHeading.isFinite || rawHeading < 0) return;
      _setHeading(rawHeading, smoothing: 0.28);

      final now = DateTime.now();
      if (_lastCompassCameraUpdate == null ||
          now.difference(_lastCompassCameraUpdate!).inMilliseconds >= 80) {
        _lastCompassCameraUpdate = now;
        _rotateFollowingCamera();
      }
    });
  }

  void _updateHeadingFromGps(Position position) {
    if (!position.speed.isFinite ||
        position.speed < 1.0 ||
        !position.heading.isFinite ||
        position.heading < 0) {
      return;
    }
    _setHeading(position.heading, smoothing: 0.42);
  }

  void _setHeading(double value, {required double smoothing}) {
    final normalized = (value % 360 + 360) % 360;
    final next = !_hasHeading
        ? normalized
        : (_displayHeading +
                  (((normalized - _displayHeading + 540) % 360) - 180) *
                      smoothing) %
              360;
    if (_hasHeading && (next - _displayHeading).abs() < 0.35) return;
    if (mounted) {
      setState(() {
        _displayHeading = next;
        _hasHeading = true;
      });
    }
  }

  void _rotateFollowingCamera() {
    final controller = _mapController;
    if (!_mapReady || !_followUser || !_hasHeading || controller == null) {
      return;
    }
    unawaited(
      controller
          .moveCamera(bearing: _displayHeading, pitch: 45)
          .catchError((_) {}),
    );
  }

  void _followPosition(Position position, {bool firstFix = false}) {
    final controller = _mapController;
    if (!_mapReady || !_followUser || controller == null) return;
    try {
      final target = ml.Geographic(
        lon: position.longitude,
        lat: position.latitude,
      );
      final currentZoom = controller.camera?.zoom ?? 16.8;
      unawaited(
        controller
            .moveCamera(
              center: target,
              zoom: (!_hasCenteredOnUser || firstFix) ? 16.8 : currentZoom,
              bearing: _hasHeading ? _displayHeading : 0,
              pitch: 45,
            )
            .catchError((_) {}),
      );
      _hasCenteredOnUser = true;
    } catch (_) {
      // The controller may not be attached while switching tabs.
    }
  }

  Future<void> _centerOnUser() async {
    final position = _currentPosition;
    if (position == null) {
      await _startLiveLocation();
      return;
    }
    setState(() => _followUser = true);
    _hasCenteredOnUser = false;
    _followPosition(position, firstFix: true);
  }

  Future<void> _openLocationSettings() async {
    final opened = await Geolocator.openLocationSettings();
    if (!opened) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _openTask(TaskItem task) async {
    final opened = await NavigationService.openTask(task);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الملاحة')));
    }
  }

  void _showTask(TaskItem task) {
    final storageKey = '${task.referenceNumber}_${task.id}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: TaskCard(
            task: task,
            savedSession: widget.savedSession,
            onUpdated: () async {
              await widget.onUpdated();
              await _loadLocalStatuses();
              await _loadMapContactData();
              await _loadCorrections();
              if (mounted) setState(() {});
            },
            contactController: widget.contactController,
            contactData: _contactData[storageKey],
            localStatus: _localStatuses[storageKey],
            onLocalStatusChanged: () async {
              await widget.onUpdated();
              await _loadLocalStatuses();
              await _loadMapContactData();
              await _loadCorrections();
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
  }

  void _showClusterTasks(List<TaskItem> clusterTasks, ml.Geographic point) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'شحنات في هذا الموقع (${clusterTasks.length})',
                              style: Theme.of(sheetContext).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              clusterTasks.first.address.isNotEmpty
                                  ? clusterTasks.first.address
                                  : '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: clusterTasks.length,
                    itemBuilder: (context, index) {
                      final task = _currentTask(clusterTasks[index]);
                      final storageKey = '${task.referenceNumber}_${task.id}';
                      return TaskCard(
                        task: task,
                        savedSession: widget.savedSession,
                        onUpdated: () async {
                          await widget.onUpdated();
                          await _loadLocalStatuses();
                          await _loadMapContactData();
                          await _loadCorrections();
                          if (mounted) setState(() {});
                          if (context.mounted) setSheetState(() {});
                        },
                        contactController: widget.contactController,
                        contactData: _contactData[storageKey],
                        localStatus: _localStatuses[storageKey],
                        onLocalStatusChanged: () async {
                          await widget.onUpdated();
                          await _loadLocalStatuses();
                          await _loadMapContactData();
                          await _loadCorrections();
                          if (mounted) setState(() {});
                          if (context.mounted) setSheetState(() {});
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLocallyExcluded(List<TaskItem> tasks) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cancel_presentation_rounded,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الشحنات الملغاة / المستبعدة محلياً (${tasks.length})',
                            style: Theme.of(sheetContext).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'مستبعدة من الخريطة محلياً فقط دون إرسالها للسيرفر',
                            style: TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (tasks.isEmpty)
                const Expanded(
                  child: Center(child: Text('لا توجد شحنات ملغاة محلياً')),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final storageKey = '${task.referenceNumber}_${task.id}';
                      return TaskCard(
                        task: task,
                        savedSession: widget.savedSession,
                        onUpdated: () async {
                          await widget.onUpdated();
                          await _loadLocalStatuses();
                          await _loadMapContactData();
                        },
                        contactController: widget.contactController,
                        contactData: _contactData[storageKey],
                        localStatus: _localStatuses[storageKey],
                        onLocalStatusChanged: () async {
                          await widget.onUpdated();
                          await _loadLocalStatuses();
                          if (mounted) setState(() {});
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWithoutCoordinates(List<TaskItem> tasks) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'شحنات بلا إحداثيات (${tasks.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return ListTile(
                      leading: const Icon(Icons.location_off_outlined),
                      title: Text(
                        task.storeName.isEmpty
                            ? task.displayReference
                            : task.storeName,
                      ),
                      subtitle: Text(
                        [
                          'الشحنة: ${task.displayReference}',
                          if (task.address.isNotEmpty) task.address,
                        ].join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: task.address.isEmpty
                          ? null
                          : const Icon(Icons.open_in_new),
                      onTap: task.address.isEmpty
                          ? null
                          : () => _openTask(task),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TaskItem> get _locallyExcludedTasks => widget.tasks.where((task) {
    final key = '${task.referenceNumber}_${task.id}';
    return _localStatuses.containsKey(key);
  }).toList();

  List<TaskItem> get _filteredTasks => widget.tasks.where((task) {
    final key = '${task.referenceNumber}_${task.id}';
    if (_localStatuses.containsKey(key)) return false;
    final matchesPayment =
        _paymentFilter == null || task.paymentKind == _paymentFilter;
    final matchesProgress =
        _progressFilter == null || task.progress == _progressFilter;
    return matchesPayment && matchesProgress;
  }).toList();

  ml.Geographic _initialCenter(List<TaskItem> located) {
    final position = _currentPosition;
    if (position != null) {
      return ml.Geographic(lon: position.longitude, lat: position.latitude);
    }
    if (located.isEmpty) {
      return const ml.Geographic(lon: 46.6753, lat: 24.7136);
    }
    return ml.Geographic(
      lon:
          located.fold<double>(
            0,
            (sum, task) => sum + _effectiveLocation(task)!.longitude,
          ) /
          located.length,
      lat:
          located.fold<double>(
            0,
            (sum, task) => sum + _effectiveLocation(task)!.latitude,
          ) /
          located.length,
    );
  }

  List<ml.Marker> _customerMarkers(List<TaskItem> located) {
    final groups = <String, List<TaskItem>>{};
    final points = <String, ml.Geographic>{};

    for (final task in located) {
      final loc = _effectiveLocation(task);
      if (loc == null) continue;
      final key =
          '${loc.latitude.toStringAsFixed(5)}_${loc.longitude.toStringAsFixed(5)}';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        points[key] = ml.Geographic(lon: loc.longitude, lat: loc.latitude);
      }
      groups[key]!.add(task);
    }

    return groups.entries.map((entry) {
      final key = entry.key;
      final clusterTasks = entry.value;
      final point = points[key]!;
      final isMultiple = clusterTasks.length > 1;
      final firstTask = clusterTasks.first;

      final hasAnswered = clusterTasks.any(
        (t) =>
            _contactData['${t.referenceNumber}_${t.id}']?.status == 'answered',
      );
      final hasNoAnswer = clusterTasks.any(
        (t) =>
            _contactData['${t.referenceNumber}_${t.id}']?.status == 'no_answer',
      );

      Color markerColor;
      if (hasAnswered && !hasNoAnswer) {
        markerColor = Colors.green;
      } else if (hasNoAnswer) {
        markerColor = Colors.red;
      } else if (clusterTasks.any(
        (t) => _corrections.containsKey(_correctionKey(t)),
      )) {
        markerColor = Colors.purple;
      } else if (clusterTasks.any(
        (t) => t.paymentKind == PaymentKind.cashOnDelivery,
      )) {
        markerColor = Colors.orange;
      } else {
        markerColor = Colors.blue;
      }

      if (!isMultiple) {
        return ml.Marker(
          point: point,
          size: const Size(48, 48),
          alignment: Alignment.bottomCenter,
          child: Tooltip(
            message: firstTask.storeName.isNotEmpty
                ? firstTask.storeName
                : firstTask.displayReference,
            child: GestureDetector(
              onTap: () => _showTask(firstTask),
              child: Icon(
                Icons.location_pin,
                size: 46,
                color: markerColor,
                shadows: const [Shadow(blurRadius: 3, color: Colors.black45)],
              ),
            ),
          ),
        );
      }

      // Clustered marker with count badge
      return ml.Marker(
        point: point,
        size: const Size(52, 52),
        alignment: Alignment.bottomCenter,
        child: Tooltip(
          message: '${clusterTasks.length} شحنات في هذا الموقع',
          child: GestureDetector(
            onTap: () => _showClusterTasks(clusterTasks, point),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Icon(
                  Icons.location_pin,
                  size: 50,
                  color: markerColor,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
                ),
                Positioned(
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black38, blurRadius: 2),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 19,
                      minHeight: 19,
                    ),
                    child: Center(
                      child: Text(
                        '${clusterTasks.length}',
                        style: TextStyle(
                          color: markerColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  ml.Marker? _userMarker() {
    final position = _currentPosition;
    if (position == null) return null;
    return ml.Marker(
      point: ml.Geographic(lon: position.longitude, lat: position.latitude),
      size: const Size(42, 42),
      rotate: true,
      child: Transform.rotate(
        angle: _displayHeading * math.pi / 180,
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black38, blurRadius: 6, spreadRadius: 1),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: const Icon(Icons.navigation, color: Colors.blue, size: 30),
        ),
      ),
    );
  }

  void _fitAll(List<TaskItem> located) {
    final controller = _mapController;
    final points = <ml.Geographic>[
      ...located.map((task) {
        final location = _effectiveLocation(task)!;
        return ml.Geographic(lon: location.longitude, lat: location.latitude);
      }),
      if (_currentPosition != null)
        ml.Geographic(
          lon: _currentPosition!.longitude,
          lat: _currentPosition!.latitude,
        ),
    ];
    if (!_mapReady || points.isEmpty || controller == null) return;

    setState(() => _followUser = false);
    if (points.length == 1) {
      unawaited(
        controller
            .animateCamera(
              center: points.first,
              zoom: 15.5,
              bearing: 0,
              pitch: 40,
              nativeDuration: const Duration(milliseconds: 450),
            )
            .catchError((_) {}),
      );
      return;
    }
    unawaited(
      controller
          .fitBounds(
            bounds: ml.LngLatBounds.fromPoints(points),
            bearing: 0,
            pitch: 35,
            padding: const EdgeInsets.fromLTRB(52, 120, 52, 90),
            nativeDuration: const Duration(milliseconds: 500),
          )
          .catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTasks;
    final located = filtered
        .where((task) => _effectiveLocation(task) != null)
        .toList();
    final withoutCoordinates = filtered
        .where((task) => _effectiveLocation(task) == null)
        .toList();
    final locallyExcluded = _locallyExcludedTasks;
    final initialCenter = _initialCenter(located);
    final scheme = Theme.of(context).colorScheme;
    final markers = <ml.Marker>[
      ..._customerMarkers(located),
      if (_userMarker() case final marker?) marker,
    ];

    return Column(
      children: [
        _FilterStrip(
          children: [
            ChoiceChip(
              label: const Text('كل طرق الدفع'),
              selected: _paymentFilter == null,
              onSelected: (_) => setState(() => _paymentFilter = null),
            ),
            ChoiceChip(
              label: const Text('كاش'),
              selected: _paymentFilter == PaymentKind.cashOnDelivery,
              onSelected: (_) =>
                  setState(() => _paymentFilter = PaymentKind.cashOnDelivery),
            ),
            ChoiceChip(
              label: const Text('مدفوعة'),
              selected: _paymentFilter == PaymentKind.prepaid,
              onSelected: (_) =>
                  setState(() => _paymentFilter = PaymentKind.prepaid),
            ),
          ],
        ),
        _FilterStrip(
          children: [
            ChoiceChip(
              label: const Text('كل الحالات'),
              selected: _progressFilter == null,
              onSelected: (_) => setState(() => _progressFilter = null),
            ),
            ChoiceChip(
              label: const Text('المتبقي'),
              selected: _progressFilter == TaskProgress.remaining,
              onSelected: (_) =>
                  setState(() => _progressFilter = TaskProgress.remaining),
            ),
            ChoiceChip(
              label: const Text('المنجز'),
              selected: _progressFilter == TaskProgress.completed,
              onSelected: (_) =>
                  setState(() => _progressFilter = TaskProgress.completed),
            ),
          ],
        ),
        Expanded(
          child: Stack(
            children: [
              Listener(
                onPointerDown: (_) {
                  if (_followUser) setState(() => _followUser = false);
                },
                child: ml.MapLibreMap(
                  options: ml.MapOptions(
                    initStyle: 'https://tiles.openfreemap.org/styles/liberty',
                    initCenter: initialCenter,
                    initZoom: _currentPosition != null ? 16.3 : 11,
                    initPitch: 45,
                    initBearing: _hasHeading ? _displayHeading : 0,
                    minZoom: 3,
                    maxZoom: 20,
                    maxPitch: 60,
                    gestures: const ml.MapGestures.all(),
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _mapReady = true;
                    if (_currentPosition != null) {
                      _centerOnUser();
                    } else if (located.isNotEmpty) {
                      Future<void>.delayed(
                        const Duration(milliseconds: 350),
                        () {
                          if (mounted) _fitAll(located);
                        },
                      );
                    }
                  },
                  onEvent: (event) {
                    if (event is ml.MapEventStartMoveCamera &&
                        event.reason == ml.CameraChangeReason.apiGesture &&
                        _followUser &&
                        mounted) {
                      setState(() => _followUser = false);
                    }
                  },
                  children: [
                    ml.WidgetLayer(markers: markers, allowInteraction: true),
                    const ml.SourceAttribution(
                      alignment: Alignment.bottomLeft,
                      padding: EdgeInsets.only(left: 6, bottom: 4),
                      showMapLibre: true,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        if (_locating)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _locationError == null
                                ? Icons.gps_fixed
                                : Icons.gps_off,
                            color: _locationError == null
                                ? Colors.green
                                : scheme.error,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locating
                                ? 'جاري تحديد موقعك المباشر…'
                                : _locationError ??
                                      'موقع مباشر • دقة ±${_currentPosition?.accuracy.round() ?? 0}م • ${located.length} عميل',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_locationError != null)
                          TextButton(
                            onPressed: _startLiveLocation,
                            child: const Text('إعادة'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: 12,
                bottom: 48,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'fit-all-map',
                      onPressed: located.isEmpty && _currentPosition == null
                          ? null
                          : () => _fitAll(located),
                      tooltip: 'عرض كل العملاء',
                      child: const Icon(Icons.center_focus_strong),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton(
                      heroTag: 'follow-live-location',
                      onPressed: _centerOnUser,
                      tooltip: 'متابعة موقعي المباشر',
                      child: Icon(
                        _followUser
                            ? Icons.my_location
                            : Icons.location_searching,
                      ),
                    ),
                  ],
                ),
              ),
              if (_locationError != null)
                Positioned(
                  left: 12,
                  bottom: 48,
                  child: FilledButton.tonalIcon(
                    onPressed: _openLocationSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('إعدادات الموقع'),
                  ),
                ),
              if (located.isEmpty)
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.location_off_outlined, size: 48),
                          SizedBox(height: 8),
                          Text('لا توجد إحداثيات للعملاء في هذا التصنيف'),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (locallyExcluded.isNotEmpty || withoutCoordinates.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  if (locallyExcluded.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.5),
                          ),
                        ),
                        onPressed: () => _showLocallyExcluded(locallyExcluded),
                        icon: const Icon(
                          Icons.cancel_presentation_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'الملغاة محلياً (${locallyExcluded.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (locallyExcluded.isNotEmpty &&
                      withoutCoordinates.isNotEmpty)
                    const SizedBox(width: 8),
                  if (withoutCoordinates.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _showWithoutCoordinates(withoutCoordinates),
                        icon: const Icon(Icons.location_off_outlined, size: 18),
                        label: Text(
                          'بلا إحداثيات (${withoutCoordinates.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ScannerTab extends StatelessWidget {
  final String token;
  final Future<void> Function() onChanged;

  const _ScannerTab({required this.token, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                size: 80,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'جاهز للمسح الضوئي؟',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'استخدم الكاميرا لمسح الباركود أو رمز QR الخاص بالشحنات لتحديث حالتها بسرعة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ScannerScreen(token: token),
                  ),
                );
                if (changed == true) await onChanged();
              },
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('افتح الكاميرا الآن'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback? onDebug;

  const _RequestState({
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.onDebug,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 104),
        Icon(icon, size: 64),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
              if (onDebug != null)
                OutlinedButton.icon(
                  onPressed: onDebug,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('تفاصيل التشخيص'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
