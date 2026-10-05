import 'package:flutter/foundation.dart';

import '../models/task_item.dart';

/// Shipments whose server address is shared by several different
/// customers: SLS falls back to one default address (e.g. 22 customers at
/// "6787, عمار ابن ياسر") when it cannot read the customer's, so such a pin
/// is not trustworthy and the label should be read instead.
class SuspiciousAddresses {
  SuspiciousAddresses._();

  static const minCustomers = 3;

  /// Keys `${referenceNumber}_${id}` of shipments with a shared address.
  static final ValueNotifier<Set<String>> keys =
      ValueNotifier<Set<String>>(const {});

  static String taskKey(TaskItem task) => '${task.referenceNumber}_${task.id}';

  static Set<String> find(List<TaskItem> tasks) {
    final groups = <String, List<TaskItem>>{};
    for (final task in tasks) {
      if (task.latitude == null || task.longitude == null) continue;
      final where =
          '${task.latitude!.toStringAsFixed(5)},${task.longitude!.toStringAsFixed(5)}';
      groups.putIfAbsent(where, () => []).add(task);
    }
    final result = <String>{};
    for (final group in groups.values) {
      final customers = group
          .map((t) => '${t.customerPhone.replaceAll(RegExp(r'\D'), '')}|${t.customerName.trim()}')
          .toSet();
      if (customers.length >= minCustomers) {
        result.addAll(group.map(taskKey));
      }
    }
    return result;
  }

  static void update(List<TaskItem> tasks) =>
      keys.value = Set.unmodifiable(find(tasks));

  static bool isSuspicious(TaskItem task) => keys.value.contains(taskKey(task));
}
