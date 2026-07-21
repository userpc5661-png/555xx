import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/task_item.dart';
import '../services/api_service.dart';
import '../services/navigation_service.dart';
import '../services/location_correction_service.dart';
import '../services/token_store.dart';
import '../theme/theme_controller.dart';
import '../widgets/task_card.dart';
import '../services/local_contact_controller.dart';
import '../services/local_contact_store.dart';
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
    _contactController = LocalContactController(onUpdate: () {
      if (mounted) setState(() {});
    });
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

      final activeKeys =
          tasks.map((t) => '${t.referenceNumber}_${t.id}').toList();
      final deliveredKeys = tasks
          .where((t) => t.progress == TaskProgress.completed)
          .map((t) => '${t.referenceNumber}_${t.id}')
          .toList();

      await LocalContactStore.instance.cleanup(activeKeys, deliveredKeys);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
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
      'الماسح الضوئي'
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
                onUpdated: _loadTasks),
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

class _DashboardPage extends StatelessWidget {
  final List<TaskItem> tasks;
  final Future<void> Function() onRefresh;

  const _DashboardPage({required this.tasks, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final remaining =
        tasks.where((task) => task.progress == TaskProgress.remaining).length;
    final completed =
        tasks.where((task) => task.progress == TaskProgress.completed).length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _WelcomeCard(total: tasks.length, remaining: remaining),
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
                    final state =
                        context.findAncestorStateOfType<_HomeScreenState>();
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
                    final state =
                        context.findAncestorStateOfType<_HomeScreenState>();
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
            value: '${tasks.length}',
            icon: Icons.inventory_2_rounded,
          ),
          _SummaryListTile(
            title: 'الموقع محدد',
            value: '${tasks.where((t) => t.hasCoordinates).length}',
            icon: Icons.location_on_rounded,
          ),

          if (tasks.isEmpty && !remaining.isNegative) ...[
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
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
  String _query = '';
  PaymentKind? _paymentFilter;
  TaskProgress? _progressFilter;
  Map<String, LocalContactData> _contactData = {};

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  @override
  void didUpdateWidget(_TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final data = await LocalContactStore.instance.getAll();
    if (mounted) {
      setState(() {
        _contactData = data;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.tasks.where((task) {
      final matchesPayment =
          _paymentFilter == null || task.paymentKind == _paymentFilter;
      final matchesProgress =
          _progressFilter == null || task.progress == _progressFilter;
      final searchable = '${task.referenceNumber} ${task.id} '
              '${task.storeName} ${task.customerName} ${task.customerPhone} ${task.address}'
          .toLowerCase();
      return matchesPayment &&
          matchesProgress &&
          (_query.isEmpty || searchable.contains(_query));
    }).toList();

    final notContacted = <TaskItem>[];
    final contacted = <TaskItem>[];

    for (final item in items) {
      final key = '${item.referenceNumber}_${item.id}';
      final data = _contactData[key];
      if (data != null && data.status == 'contacted') {
        contacted.add(item);
      } else {
        notContacted.add(item);
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'ابحث برقم الشحنة أو المتجر أو العميل أو الجوال',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        _FilterStrip(
          children: [
            ChoiceChip(
              label: Text('الكل (${widget.tasks.length})'),
              selected: _paymentFilter == null,
              onSelected: (_) => setState(() => _paymentFilter = null),
            ),
            ChoiceChip(
              label: Text(
                'كاش (${widget.tasks.where((task) => task.paymentKind == PaymentKind.cashOnDelivery).length})',
              ),
              selected: _paymentFilter == PaymentKind.cashOnDelivery,
              onSelected: (_) => setState(
                () => _paymentFilter = PaymentKind.cashOnDelivery,
              ),
            ),
            ChoiceChip(
              label: Text(
                'مدفوعة (${widget.tasks.where((task) => task.paymentKind == PaymentKind.prepaid).length})',
              ),
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
              onSelected: (_) => setState(
                () => _progressFilter = TaskProgress.remaining,
              ),
            ),
            ChoiceChip(
              label: const Text('المنجز'),
              selected: _progressFilter == TaskProgress.completed,
              onSelected: (_) => setState(
                () => _progressFilter = TaskProgress.completed,
              ),
            ),
            ChoiceChip(
              label: const Text('الملغي'),
              selected: _progressFilter == TaskProgress.cancelled,
              onSelected: (_) => setState(
                () => _progressFilter = TaskProgress.cancelled,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('النتائج: ${items.length}'),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.inbox_outlined, size: 64),
                      SizedBox(height: 12),
                      Center(child: Text('لا توجد شحنات ضمن هذا التصنيف')),
                    ],
                  )
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (notContacted.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text(
                              'لم يتم التواصل',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => TaskCard(
                              task: notContacted[index],
                              savedSession: widget.savedSession,
                              onUpdated: widget.onRefresh,
                              contactController: widget.contactController,
                              contactData: _contactData[
                                  '${notContacted[index].referenceNumber}_${notContacted[index].id}'],
                            ),
                            childCount: notContacted.length,
                          ),
                        ),
                      ],
                      if (contacted.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                            child: Text(
                              'تم التواصل',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => TaskCard(
                              task: contacted[index],
                              savedSession: widget.savedSession,
                              onUpdated: widget.onRefresh,
                              contactController: widget.contactController,
                              contactData: _contactData[
                                  '${contacted[index].referenceNumber}_${contacted[index].id}'],
                            ),
                            childCount: contacted.length,
                          ),
                        ),
                      ],
                      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                    ],
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
      }).toList()),
    );
  }
}

class _MapPage extends StatefulWidget {
  final List<TaskItem> tasks;
  final bool active;
  final String savedSession;
  final Future<void> Function() onUpdated;

  const _MapPage(
      {required this.tasks,
      required this.active,
      required this.savedSession,
      required this.onUpdated});

  @override
  State<_MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<_MapPage> {
  PaymentKind? _paymentFilter;
  TaskProgress? _progressFilter;

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  bool _mapReady = false;
  bool _locating = true;
  bool _followUser = true;
  bool _hasCenteredOnUser = false;
  String? _locationError;
  final Map<String, CorrectedLocation> _corrections = {};

  String _correctionKey(TaskItem task) => task.displayReference;

  Future<void> _loadCorrections() async {
    final loaded = <String, CorrectedLocation>{};
    for (final task in widget.tasks) {
      final correction = await LocationCorrectionService.load(task);
      if (correction != null) loaded[_correctionKey(task)] = correction;
    }
    if (!mounted) return;
    setState(() {
      _corrections
        ..clear()
        ..addAll(loaded);
    });
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
    _loadCorrections();
    if (widget.active) {
      _startLiveLocation();
    } else {
      _locating = false;
    }
  }

  @override
  void didUpdateWidget(covariant _MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      _loadCorrections();
    }
    if (!oldWidget.active && widget.active) {
      _startLiveLocation();
    } else if (oldWidget.active && !widget.active) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _followUser = false;
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startLiveLocation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
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

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null && mounted) {
      setState(() {
        _currentPosition = lastKnown;
        _locating = false;
      });
      _followPosition(lastKnown, firstFix: true);
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = current;
          _locating = false;
          _locationError = null;
        });
      }
      _followPosition(current, firstFix: true);
    } catch (_) {
      if (lastKnown == null && mounted) {
        setState(() {
          _locating = false;
          _locationError =
              'تعذر تحديد موقعك الآن. تأكد أنك في مكان تصل إليه إشارة GPS.';
        });
      }
    }

    if (!mounted || !widget.active) return;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen(
      (position) {
        if (!mounted || !widget.active) return;
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
  }

  void _followPosition(Position position, {bool firstFix = false}) {
    if (!_mapReady || !_followUser) return;
    try {
      final target = LatLng(position.latitude, position.longitude);
      _mapController.move(
          target,
          (!_hasCenteredOnUser || firstFix)
              ? 16.5
              : _mapController.camera.zoom);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق الملاحة')),
      );
    }
  }

  void _showTask(TaskItem task) {
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
              onUpdated: widget.onUpdated),
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
                      onTap:
                          task.address.isEmpty ? null : () => _openTask(task),
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

  List<TaskItem> get _filteredTasks => widget.tasks.where((task) {
        final matchesPayment =
            _paymentFilter == null || task.paymentKind == _paymentFilter;
        final matchesProgress =
            _progressFilter == null || task.progress == _progressFilter;
        return matchesPayment && matchesProgress;
      }).toList();

  LatLng _initialCenter(List<TaskItem> located) {
    final position = _currentPosition;
    if (position != null) {
      return LatLng(position.latitude, position.longitude);
    }
    if (located.isEmpty) return const LatLng(24.7136, 46.6753);
    return LatLng(
      located.fold<double>(
              0, (sum, task) => sum + _effectiveLocation(task)!.latitude) /
          located.length,
      located.fold<double>(
              0, (sum, task) => sum + _effectiveLocation(task)!.longitude) /
          located.length,
    );
  }

  List<Marker> _customerMarkers(List<TaskItem> located) {
    return located.asMap().entries.map((entry) {
      final task = entry.value;
      final isCash = task.paymentKind == PaymentKind.cashOnDelivery;
      return Marker(
        point: LatLng(_effectiveLocation(task)!.latitude,
            _effectiveLocation(task)!.longitude),
        width: 48,
        height: 48,
        alignment: Alignment.topCenter,
        child: Tooltip(
          message: task.storeName.isNotEmpty
              ? task.storeName
              : task.displayReference,
          child: GestureDetector(
            onTap: () => _showTask(task),
            child: Icon(
              Icons.location_pin,
              size: 46,
              color: _corrections.containsKey(_correctionKey(task))
                  ? Colors.purple
                  : (isCash ? Colors.orange : Colors.blue),
              shadows: const [Shadow(blurRadius: 3, color: Colors.black45)],
            ),
          ),
        ),
      );
    }).toList();
  }

  Marker? _userMarker() {
    final position = _currentPosition;
    if (position == null) return null;
    final heading = position.heading.isFinite && position.heading >= 0
        ? position.heading
        : 0.0;
    return Marker(
      point: LatLng(position.latitude, position.longitude),
      width: 42,
      height: 42,
      child: Transform.rotate(
        angle: heading * math.pi / 180,
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black38, blurRadius: 6, spreadRadius: 1),
            ],
          ),
          padding: const EdgeInsets.all(5),
          child: const Icon(
            Icons.navigation,
            color: Colors.blue,
            size: 30,
          ),
        ),
      ),
    );
  }

  void _fitAll(List<TaskItem> located) {
    final points = <LatLng>[
      ...located.map((task) {
        final location = _effectiveLocation(task)!;
        return LatLng(location.latitude, location.longitude);
      }),
      if (_currentPosition != null)
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
    ];
    if (!_mapReady || points.isEmpty) return;

    setState(() => _followUser = false);
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final span = math.max(maxLat - minLat, maxLng - minLng);
    final zoom = span < 0.005
        ? 15.0
        : span < 0.02
            ? 13.5
            : span < 0.08
                ? 11.5
                : span < 0.25
                    ? 9.5
                    : 7.5;
    _mapController.move(center, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTasks;
    final located =
        filtered.where((task) => _effectiveLocation(task) != null).toList();
    final withoutCoordinates =
        filtered.where((task) => _effectiveLocation(task) == null).toList();
    final initialCenter = _initialCenter(located);
    final scheme = Theme.of(context).colorScheme;
    final markers = <Marker>[
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
              onSelected: (_) => setState(
                () => _paymentFilter = PaymentKind.cashOnDelivery,
              ),
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
              onSelected: (_) => setState(
                () => _progressFilter = TaskProgress.remaining,
              ),
            ),
            ChoiceChip(
              label: const Text('المنجز'),
              selected: _progressFilter == TaskProgress.completed,
              onSelected: (_) => setState(
                () => _progressFilter = TaskProgress.completed,
              ),
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
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: _currentPosition != null ? 15.5 : 11,
                    minZoom: 3,
                    maxZoom: 19,
                    onMapReady: () {
                      _mapReady = true;
                      if (_currentPosition != null) {
                        _centerOnUser();
                      } else if (located.isNotEmpty) {
                        Future<void>.delayed(
                          const Duration(milliseconds: 350),
                          () => _fitAll(located),
                        );
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.sls_assistant_pro',
                      maxNativeZoom: 19,
                    ),
                    MarkerLayer(markers: markers),
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
                                    'موقعك مباشر • ${located.length} عميل على الخريطة',
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
              Positioned(
                left: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (withoutCoordinates.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showWithoutCoordinates(withoutCoordinates),
                  icon: const Icon(Icons.location_off_outlined),
                  label: Text(
                    'عرض الشحنات بلا إحداثيات (${withoutCoordinates.length})',
                  ),
                ),
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
                    color: Colors.green.withValues(alpha: 0.2), width: 2),
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
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
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
