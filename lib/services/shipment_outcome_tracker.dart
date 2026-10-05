import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/task_item.dart';
import 'account_store.dart';
import 'delivery_history_store.dart';
import 'scan_api_service.dart';

enum ShipmentOutcomeKind { delivered, closed }

class ShipmentOutcome {
  final ShipmentOutcomeKind kind;
  final DateTime at;
  final String label;

  const ShipmentOutcome(this.kind, this.at, this.label);

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'at': at.toIso8601String(),
        'l': label,
      };

  static ShipmentOutcome? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['k'] == 'delivered'
        ? ShipmentOutcomeKind.delivered
        : ShipmentOutcomeKind.closed;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return ShipmentOutcome(kind, at, '${json['l'] ?? ''}');
  }

  /// How a shipment ended, from SLS's own order data (orders/awb), or null
  /// while it is still in progress. Delivered = status "Completed" /
  /// status_code 3 / "Shipment delivered"; closed = cancelled, returned,
  /// failed and similar final states.
  static ShipmentOutcome? classify(Map<String, dynamic> order) {
    final status = '${order['status'] ?? ''}'.toLowerCase();
    final label = '${order['status_label'] ?? ''}';
    final lower = label.toLowerCase();
    final code = '${order['status_code'] ?? ''}'.trim();

    DateTime? date(List<String> keys) {
      for (final key in keys) {
        final value = order[key];
        if (value == null) continue;
        final parsed = DateTime.tryParse('$value'.replaceFirst(' ', 'T'));
        if (parsed != null) return parsed.toLocal();
      }
      return null;
    }

    final negative = lower.contains('not deliver') ||
        lower.contains('undeliver') ||
        lower.contains('لم يتم');
    final delivered = !negative &&
        (status == 'completed' ||
            code == '3' ||
            lower.contains('delivered') ||
            lower.contains('تم التوصيل') ||
            lower.contains('تم التسليم'));
    if (delivered) {
      return ShipmentOutcome(
        ShipmentOutcomeKind.delivered,
        date(['actual_delivery_at', 'deliver_at', 'updated_at']) ??
            DateTime.now(),
        label.isEmpty ? 'Delivered' : label,
      );
    }

    const finals = [
      'cancel',
      'return',
      'rto',
      'fail',
      'reject',
      'closed',
      'lost',
      'damag',
      'ملغ',
      'مرتجع',
      'إرجاع',
    ];
    final text = '$status $lower';
    if (finals.any(text.contains)) {
      return ShipmentOutcome(
        ShipmentOutcomeKind.closed,
        date(['canceled_at', 'return_at', 'updated_at']) ?? DateTime.now(),
        label.isEmpty ? status : label,
      );
    }
    return null;
  }
}

class OutcomeCounts {
  final int deliveredToday;
  final int closedToday;
  final int deliveredMonth;
  final int closedMonth;

  const OutcomeCounts({
    required this.deliveredToday,
    required this.closedToday,
    required this.deliveredMonth,
    required this.closedMonth,
  });
}

/// Counts deliveries and closures from the server, including ones made in
/// the official app. /tasks only lists shipments still on hand, so the app
/// remembers every shipment it has seen there; when one disappears it reads
/// its final state from SLS (orders/awb, GET only) and records it.
class ShipmentOutcomeTracker {
  ShipmentOutcomeTracker._();

  static final instance = ShipmentOutcomeTracker._();

  static const _storage = FlutterSecureStorage();
  static const _maxLookupsPerSync = 15;
  static const _maxAttempts = 5;

  /// Bumped whenever the counts change, so screens can refresh.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _syncing = false;

  String get _key =>
      'shipment_outcomes_v1_${AccountStore.currentAccountId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  Future<Map<String, dynamic>> _read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) =>
      _storage.write(key: _key, value: jsonEncode(data));

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _awb(TaskItem task) => task.realAwb.trim().isNotEmpty
      ? task.realAwb.trim()
      : task.displayReference.trim();

  Future<Map<String, ShipmentOutcome>> outcomes() async {
    final data = await _read();
    final result = <String, ShipmentOutcome>{};
    _map(data['outcomes']).forEach((awb, value) {
      final outcome = ShipmentOutcome.fromJson(value);
      if (outcome != null) result[awb] = outcome;
    });
    return result;
  }

  /// [localDeliveredAwbs] are deliveries made in this app that the server
  /// lookup has not recorded yet (counted as delivered at [now]).
  Future<OutcomeCounts> counts({
    Map<String, DateTime> localDelivered = const {},
  }) async {
    final all = await outcomes();
    final now = DateTime.now();
    final merged = <String, ShipmentOutcome>{
      for (final entry in localDelivered.entries)
        entry.key: ShipmentOutcome(
          ShipmentOutcomeKind.delivered,
          entry.value,
          'local',
        ),
      ...all,
    };
    bool sameDay(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    bool sameMonth(DateTime d) => d.year == now.year && d.month == now.month;
    int count(ShipmentOutcomeKind kind, bool Function(DateTime) when) =>
        merged.values.where((o) => o.kind == kind && when(o.at)).length;
    return OutcomeCounts(
      deliveredToday: count(ShipmentOutcomeKind.delivered, sameDay),
      closedToday: count(ShipmentOutcomeKind.closed, sameDay),
      deliveredMonth: count(ShipmentOutcomeKind.delivered, sameMonth),
      closedMonth: count(ShipmentOutcomeKind.closed, sameMonth),
    );
  }

  /// Counts including deliveries made in this app that are still waiting
  /// for the server lookup (not yet gone from [current]).
  Future<OutcomeCounts> countsFor(List<TaskItem> current) async {
    final onHand = {
      for (final task in current) ...[
        task.realAwb.trim(),
        task.displayReference.trim(),
      ],
    };
    final history = await DeliveryHistoryStore.instance.allRecords();
    return counts(localDelivered: {
      for (final record in history)
        if (!onHand.contains(record.awb)) record.awb: record.completedAt,
    });
  }

  /// Call after each successful /tasks fetch. Runs the lookups in the
  /// background; never throws.
  Future<void> sync(List<TaskItem> tasks, String savedSession) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final data = await _read();
      final seen = _map(data['seen']);
      final attempts = _map(data['attempts']);
      final outcomesJson = _map(data['outcomes']);
      final now = DateTime.now();

      final current = {
        for (final task in tasks)
          if (_awb(task).isNotEmpty) _awb(task),
      };
      for (final awb in current) {
        seen.putIfAbsent(awb, () => now.toIso8601String());
        attempts.remove(awb);
      }

      final gone = seen.keys
          .where((awb) =>
              !current.contains(awb) && !outcomesJson.containsKey(awb))
          .take(_maxLookupsPerSync)
          .toList();

      var changed = false;
      if (gone.isNotEmpty) {
        final api = ScanApiService(savedSession: savedSession);
        for (final awb in gone) {
          try {
            final shipment = await api.scanOrder(awb);
            final outcome = ShipmentOutcome.classify(shipment.raw);
            if (outcome != null) {
              outcomesJson[awb] = outcome.toJson();
              seen.remove(awb);
              attempts.remove(awb);
              changed = true;
              continue;
            }
          } catch (error) {
            debugPrint('Outcome lookup failed for $awb: $error');
          }
          final tries = ((attempts[awb] as num?) ?? 0) + 1;
          if (tries >= _maxAttempts) {
            seen.remove(awb);
            attempts.remove(awb);
          } else {
            attempts[awb] = tries;
          }
        }
      }

      // Keep about two months of history.
      final cutoff = now.subtract(const Duration(days: 62));
      outcomesJson.removeWhere((_, value) {
        final outcome = ShipmentOutcome.fromJson(value);
        return outcome == null || outcome.at.isBefore(cutoff);
      });
      seen.removeWhere((_, value) {
        final first = DateTime.tryParse('$value');
        return first == null ||
            first.isBefore(now.subtract(const Duration(days: 30)));
      });

      await _write({
        'seen': seen,
        'attempts': attempts,
        'outcomes': outcomesJson,
      });
      if (changed) revision.value++;
    } catch (error) {
      debugPrint('Outcome sync failed: $error');
    } finally {
      _syncing = false;
    }
  }
}
