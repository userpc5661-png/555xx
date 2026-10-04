import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/utils/tasks_response_summary.dart';

void main() {
  test('summarizes fields, counts and statuses without customer data', () {
    final rows = [
      {'order_awb': 'A1', 'status_code': 5, 'status_label': 'Delivered', 'customer_name': 'Secret Name'},
      {'order_awb': 'A2', 'status_code': 3, 'status_label': 'Out for delivery', 'customer_name': 'Other'},
    ];
    final body = {
      'success': true,
      'delivered_count': 12,
      'tasks': rows,
      'meta': {'total': 2, 'month_delivered': 140},
    };
    final tasks = rows.map(TaskItem.fromJson).toList();
    final text = TasksResponseSummary.build(body, tasks);

    expect(text, contains('delivered_count: 12'));
    expect(text, contains('tasks: list(2)'));
    expect(text, contains('meta.month_delivered: 140'));
    expect(text, contains('Shipments parsed: 2'));
    expect(text, contains('completed 1'));
    expect(text, contains('5 | Delivered: 1'));
    expect(text, isNot(contains('Secret Name')));
  });
}
