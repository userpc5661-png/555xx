import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/utils/suspicious_addresses.dart';

TaskItem task(String id, String name, String phone, String lat, String lng) =>
    TaskItem.fromJson({
      'order_id': id,
      'order_awb': id,
      'delivery_location_name': name,
      'delivery_phone': phone,
      'delivery_location_lat': lat,
      'delivery_location_lng': lng,
    });

void main() {
  test('flags an address shared by 3+ different customers', () {
    final tasks = [
      task('1', 'رجاء', '0590999007', '26.39055362', '49.96598844'),
      task('2', 'محمد', '0566367070', '26.39055362', '49.96598844'),
      task('3', 'Madawi', '0501308599', '26.39055362', '49.96598844'),
      task('4', 'خالد', '0554356655', '26.34129853', '50.00313024'),
    ];
    final found = SuspiciousAddresses.find(tasks);
    expect(found, hasLength(3));
    expect(found.contains(SuspiciousAddresses.taskKey(tasks[3])), isFalse);
  });

  test('several parcels of the same customer are not flagged', () {
    final tasks = [
      task('1', 'رجاء', '0590999007', '26.39', '49.96'),
      task('2', 'رجاء', '0590999007', '26.39', '49.96'),
      task('3', 'رجاء', '0590999007', '26.39', '49.96'),
    ];
    expect(SuspiciousAddresses.find(tasks), isEmpty);
  });
}
