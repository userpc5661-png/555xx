import 'dart:async';
import 'local_contact_store.dart';
import 'phone_action_service.dart';

class LocalContactController {
  final LocalContactStore _store = LocalContactStore.instance;

  // Callback to refresh UI
  void Function()? onUpdate;

  // Storage for keys of shipments that are currently visible/active in the UI
  // This helps prevent transitioning shipments that were removed during the 5s window.
  List<String> _currentActiveKeys = [];

  Timer? _reminderTimer;
  final Map<String, Timer> _pendingTransitions = {};
  bool _disposed = false;

  LocalContactController({this.onUpdate});

  void updateActiveKeys(List<String> keys) {
    _currentActiveKeys = keys;
  }

  void dispose() {
    _disposed = true;
    _reminderTimer?.cancel();
    for (final t in _pendingTransitions.values) {
      t.cancel();
    }
    _pendingTransitions.clear();
  }

  Future<bool> handleCall(String storageKey, String? phone) async {
    final success = await PhoneActionService.call(phone);
    if (success) {
      _startTransitionTimer(storageKey, 'call');
    }
    return success;
  }

  Future<bool> handleWhatsApp(String storageKey, String? phone) async {
    final success = await PhoneActionService.openWhatsApp(phone);
    if (success) {
      _startTransitionTimer(storageKey, 'whatsapp');
    }
    return success;
  }

  void _startTransitionTimer(String storageKey, String type) {
    _pendingTransitions[storageKey]?.cancel();

    _pendingTransitions[storageKey] =
        Timer(const Duration(seconds: 5), () async {
      _pendingTransitions.remove(storageKey);

      if (_disposed) return;
      if (!_currentActiveKeys.contains(storageKey)) return;

      final records = await _store.getAll();
      final current =
          records[storageKey] ?? LocalContactData(status: 'not_contacted');

      if (current.status == 'contacted') return;

      await _store.save(
          storageKey,
          current.copyWith(
            status: 'contacted',
            type: type,
            timestamp: DateTime.now(),
            clearReminder: true,
          ));

      onUpdate?.call();
      scheduleNextReminder();
    });
  }

  Future<void> setReminder(String storageKey, Duration duration) async {
    final records = await _store.getAll();
    final current =
        records[storageKey] ?? LocalContactData(status: 'contacted');

    await _store.save(
        storageKey,
        current.copyWith(
          reminderAt: DateTime.now().add(duration),
        ));
    onUpdate?.call();
    scheduleNextReminder();
  }

  Future<void> setCustomReminder(String storageKey, DateTime time) async {
    final records = await _store.getAll();
    final current =
        records[storageKey] ?? LocalContactData(status: 'contacted');

    await _store.save(
        storageKey,
        current.copyWith(
          reminderAt: time,
        ));
    onUpdate?.call();
    scheduleNextReminder();
  }

  Future<void> cancelReminder(String storageKey) async {
    final records = await _store.getAll();
    final current = records[storageKey];
    if (current != null) {
      await _store.save(storageKey, current.copyWith(clearReminder: true));
      onUpdate?.call();
      scheduleNextReminder();
    }
  }

  Future<void> moveToNotContacted(String storageKey) async {
    final records = await _store.getAll();
    final current = records[storageKey];
    if (current != null) {
      await _store.save(
          storageKey,
          current.copyWith(
            status: 'not_contacted',
            clearReminder: true,
          ));
      onUpdate?.call();
      scheduleNextReminder();
    }
  }

  /// Schedules a single timer for the next expiring reminder.
  Future<void> scheduleNextReminder() async {
    _reminderTimer?.cancel();
    if (_disposed) return;

    final records = await _store.getAll();
    DateTime? soonest;

    for (final data in records.values) {
      if (data.status == 'contacted' && data.reminderAt != null) {
        if (soonest == null || data.reminderAt!.isBefore(soonest)) {
          soonest = data.reminderAt;
        }
      }
    }

    if (soonest != null) {
      final now = DateTime.now();
      var diff = soonest.difference(now);
      if (diff.isNegative) diff = Duration.zero;

      // Buffer of 500ms to ensure we are past the target time
      _reminderTimer = Timer(diff + const Duration(milliseconds: 500), () {
        _checkAndExpireReminders();
      });
    }
  }

  Future<void> _checkAndExpireReminders() async {
    if (_disposed) return;

    final records = await _store.getAll();
    bool changed = false;
    final now = DateTime.now();

    for (final entry in records.entries) {
      final data = entry.value;
      if (data.status == 'contacted' && data.reminderAt != null) {
        if (!data.reminderAt!.isAfter(now)) {
          records[entry.key] = data.copyWith(
            status: 'not_contacted',
            clearReminder: true,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await _store.bulkSave(records);
      onUpdate?.call();
    }

    // Reschedule for the next one if any
    scheduleNextReminder();
  }
}
