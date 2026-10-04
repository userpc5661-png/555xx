import '../models/task_item.dart';

/// Decides from the server's own shipment data whether a status update has
/// really been applied. Used after bulk/status succeeds, so the driver only
/// sees "confirmed by the server" when the server reports the new status.
class StatusVerification {
  StatusVerification._();

  static const _statusKeys = [
    'status_code',
    'order_status_code',
    'current_status',
    'status_id',
    'order_status_id',
    'status',
  ];

  /// The status codes present in [order] (top level first, then nested
  /// `order`/`shipment` objects).
  static Set<String> statusCodesIn(Map<String, dynamic> order) {
    final codes = <String>{};
    void collect(Map<String, dynamic> map) {
      for (final key in _statusKeys) {
        final value = map[key];
        if (value is num || value is String) {
          final text = value.toString().trim();
          if (text.isNotEmpty) codes.add(text);
        }
      }
    }

    collect(order);
    for (final nested in const ['order', 'shipment', 'data']) {
      final value = order[nested];
      if (value is Map) collect(Map<String, dynamic>.from(value));
    }
    return codes;
  }

  static bool matches(
    Map<String, dynamic> order, {
    required Object sentStatusId,
    required bool delivered,
  }) {
    final sent = sentStatusId.toString().trim();
    if (sent.isNotEmpty && statusCodesIn(order).contains(sent)) return true;
    if (delivered) {
      final task = TaskItem.fromJson(order);
      final label = '${task.statusCode} ${task.statusLabel}'.toLowerCase();
      // "Not delivered" / "لم يتم التوصيل" also contain the delivered words.
      final negative = label.contains('not deliver') ||
          label.contains('undeliver') ||
          label.contains('لم يتم') ||
          label.contains('غير مسلم');
      return !negative && task.progress == TaskProgress.completed;
    }
    return false;
  }
}
