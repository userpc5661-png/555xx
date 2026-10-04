import '../models/task_item.dart';

/// A short, copyable description of what the server returned for /tasks:
/// its top-level fields (where counters such as "delivered" would be), how
/// many shipments came back, and their statuses. No customer data.
class TasksResponseSummary {
  TasksResponseSummary._();

  static String build(Object? body, List<TaskItem> tasks) {
    final lines = <String>[];

    void describe(Map map, String prefix, int depth) {
      for (final entry in map.entries) {
        final key = '$prefix${entry.key}';
        final value = entry.value;
        if (value is List) {
          lines.add('$key: list(${value.length})');
        } else if (value is Map) {
          if (depth < 1) {
            describe(value, '$key.', depth + 1);
          } else {
            lines.add('$key: object(${value.length} fields)');
          }
        } else {
          final text = value?.toString() ?? 'null';
          lines.add(
            '$key: ${text.length > 40 ? '${text.substring(0, 40)}…' : text}',
          );
        }
      }
    }

    if (body is Map) {
      lines.add('Top-level fields:');
      describe(body, '  ', 0);
    } else if (body is List) {
      lines.add('Top-level: list(${body.length})');
    }

    lines.add('Shipments parsed: ${tasks.length}');
    final byProgress = <TaskProgress, int>{};
    final byStatus = <String, int>{};
    for (final task in tasks) {
      byProgress[task.progress] = (byProgress[task.progress] ?? 0) + 1;
      final status = '${task.statusCode} | ${task.statusLabel}'.trim();
      byStatus[status] = (byStatus[status] ?? 0) + 1;
    }
    lines.add(
      'App view: remaining ${byProgress[TaskProgress.remaining] ?? 0}, '
      'completed ${byProgress[TaskProgress.completed] ?? 0}, '
      'cancelled ${byProgress[TaskProgress.cancelled] ?? 0}',
    );
    lines.add('Statuses (code | label: count):');
    for (final entry in byStatus.entries) {
      lines.add('  ${entry.key}: ${entry.value}');
    }
    return lines.join('\n');
  }
}
