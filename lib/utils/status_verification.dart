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

  /// A field of [order], top level first, then the nested objects.
  static String? _field(Map<String, dynamic> order, String key) {
    for (final map in [
      order,
      for (final nested in const ['order', 'shipment', 'data'])
        if (order[nested] is Map) Map<String, dynamic>.from(order[nested] as Map),
    ]) {
      final value = map[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    }
    return null;
  }

  static String _normal(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// [sentStatusLabel]: the status_label sent. Not-delivered reasons
  /// (refused, not answering, reschedule…) keep the same status code as
  /// "Out for delivery" (2, In Transit), so the code alone proves nothing:
  /// the shipment must show this label. Diagnostics showed SLS writes it
  /// only when it answers the request. [sentAt]: when it was sent; a label
  /// that was already there from an earlier update (order updated_at
  /// before that) does not count.
  static bool matches(
    Map<String, dynamic> order, {
    required Object sentStatusId,
    required bool delivered,
    String? sentStatusLabel,
    DateTime? sentAt,
  }) {
    final sent = sentStatusId.toString().trim();
    final codeMatches = sent.isNotEmpty && statusCodesIn(order).contains(sent);
    final sentLabel = sentStatusLabel?.trim() ?? '';
    if (!delivered && sentLabel.isNotEmpty) {
      if (!codeMatches) return false;
      final label = _field(order, 'status_label');
      if (label == null || _normal(label) != _normal(sentLabel)) return false;
      if (sentAt == null) return true;
      final updated = DateTime.tryParse(_field(order, 'updated_at') ?? '');
      // Two minutes of slack for the phone's clock.
      return updated == null ||
          !updated.isBefore(sentAt.subtract(const Duration(minutes: 2)));
    }
    if (codeMatches) return true;
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
