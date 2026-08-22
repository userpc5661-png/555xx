import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/services/local_shipment_status_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalShipmentStatus Model', () {
    test('serializes and deserializes correctly', () {
      final now = DateTime.now();
      final status = LocalShipmentStatus(
        statusKey: 'customer_cancelled',
        label: 'العميل ألغى الطلبية',
        timestamp: now,
        note: 'اتصل العميل وطلب الإلغاء',
      );

      final json = status.toJson();
      expect(json['statusKey'], 'customer_cancelled');
      expect(json['label'], 'العميل ألغى الطلبية');
      expect(json['note'], 'اتصل العميل وطلب الإلغاء');

      final restored = LocalShipmentStatus.fromJson(json);
      expect(restored.statusKey, 'customer_cancelled');
      expect(restored.label, 'العميل ألغى الطلبية');
      expect(restored.note, 'اتصل العميل وطلب الإلغاء');
    });

    test('provides correct default Arabic labels', () {
      expect(LocalShipmentStatus.defaultLabelFor('customer_cancelled'),
          'العميل ألغى الطلبية');
      expect(LocalShipmentStatus.defaultLabelFor('rescheduled'),
          'العميل أعاد الجدولة');
      expect(LocalShipmentStatus.defaultLabelFor('wrong_location'),
          'الموقع غير صحيح');
      expect(
          LocalShipmentStatus.defaultLabelFor('wrong_phone'), 'رقم الهاتف خاطئ');
      expect(LocalShipmentStatus.defaultLabelFor('no_answer'),
          'العميل لم يجب');
      expect(LocalShipmentStatus.defaultLabelFor('unknown_key'),
          'حالة مستبعدة محلياً');
    });
  });

  group('Map Marker Grouping / Clustering Logic', () {
    test('groups tasks sharing identical coordinates accurately', () {
      final task1 = TaskItem.fromJson({
        'order_id': 1,
        'order_awb': 'AWB-1',
        'customer_name': 'عميل 1',
        'delivery_location_lat': 24.713601,
        'delivery_location_lng': 46.675302,
      });

      final task2 = TaskItem.fromJson({
        'order_id': 2,
        'order_awb': 'AWB-2',
        'customer_name': 'عميل 2',
        'delivery_location_lat': 24.713604,
        'delivery_location_lng': 46.675303,
      });

      final task3 = TaskItem.fromJson({
        'order_id': 3,
        'order_awb': 'AWB-3',
        'customer_name': 'عميل 3',
        'delivery_location_lat': 24.800000,
        'delivery_location_lng': 46.700000,
      });

      final tasks = [task1, task2, task3];

      // Simulated grouping algorithm as in HomeScreen
      final groups = <String, List<TaskItem>>{};
      for (final task in tasks) {
        if (task.latitude == null || task.longitude == null) continue;
        final key =
            '${task.latitude!.toStringAsFixed(5)}_${task.longitude!.toStringAsFixed(5)}';
        groups.putIfAbsent(key, () => []).add(task);
      }

      // Group 1 has 2 tasks in same location
      final cluster1 = groups['24.71360_46.67530'];
      expect(cluster1, isNotNull);
      expect(cluster1!.length, 2);
      expect(cluster1.map((t) => t.referenceNumber), containsAll(['AWB-1', 'AWB-2']));

      // Group 2 has 1 task
      final cluster2 = groups['24.80000_46.70000'];
      expect(cluster2, isNotNull);
      expect(cluster2!.length, 1);
      expect(cluster2.first.referenceNumber, 'AWB-3');
    });
  });
}
