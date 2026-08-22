import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/utils/shipment_field_mapper.dart';

void main() {
  group('ShipmentFieldMapper & TaskItem Mapping', () {
    test('A. Tasks API nested JSON mapping', () {
      final json = {
        'task': {
          'id': 'T-100',
          'assignee_id': 99,
        },
        'order': {
          'order_id': 'ORD-123',
          'order_awb': 'AWB-456',
          'delivery_location_name': 'نسرين مروان',
          'delivery_phone': '0530526000',
          'collection_location_contact': 'Assaf',
          'delivery_location_address1': 'حي الواحة',
          'delivery_location_city': 'الدمام',
          'is_cod': 1,
          'cod_amount': '150.50',
        }
      };

      final task = TaskItem.fromJson(json);

      expect(task.customerName, 'نسرين مروان');
      expect(task.customerPhone, '0530526000');
      expect(task.storeName, 'Assaf');
      expect(task.address, contains('حي الواحة'));
      expect(task.address, contains('الدمام'));
      expect(task.isCashOnDelivery, isTrue);
      expect(task.codAmount, 150.50);
      expect(task.assigneeId, 99);
      expect(task.referenceNumber, 'AWB-456');
    });

    test('B. Scanner API top-level JSON mapping', () {
      final json = {
        'id': 77,
        'order_id': 'SCAN-123',
        'recipient_name': 'Ali',
        'recipient_phone': '0500000000',
        'store_name': 'Test Store',
        'cod_amount': 0,
        'is_cod': false,
      };

      final task = TaskItem.fromJson(json);

      expect(task.customerName, 'Ali');
      expect(task.customerPhone, '0500000000');
      expect(task.storeName, 'Test Store');
      expect(task.isCashOnDelivery, isFalse);
    });

    test('C. Name separation (excludes customer branch for store)', () {
      final json = {
        'collection_location_name': 'Real Store',
        'customer': {
          'name': 'Corporate Account',
        }
      };

      final store = ShipmentFieldMapper.merchantName(json);
      expect(store, 'Real Store');
      expect(store, isNot('Corporate Account'));
    });

    test('D. COD parsing variants', () {
      expect(ShipmentFieldMapper.isCod({'is_cod': 1}), isTrue);
      expect(ShipmentFieldMapper.isCod({'is_cod': '1'}), isTrue);
      expect(ShipmentFieldMapper.isCod({'is_cod': true}), isTrue);
      expect(ShipmentFieldMapper.isCod({'is_cod': 0, 'cod_amount': 50}), isTrue);
      expect(ShipmentFieldMapper.isCod({'is_cod': false, 'cod_amount': 0}), isFalse);

      expect(ShipmentFieldMapper.codAmount({'cod_amount': 100}), 100.0);
      expect(ShipmentFieldMapper.codAmount({'cod_amount': '125.75'}), 125.75);
      expect(ShipmentFieldMapper.codAmount({'amount_to_collect': '50.00'}), 50.0);
    });

    test('E. Invalid values handling', () {
      final json = {
        'cod_amount': 'null',
        'delivery_phone': null,
        'recipient_name': '',
      };

      expect(ShipmentFieldMapper.codAmount(json), 0.0);
      expect(ShipmentFieldMapper.recipientPhone(json), '');
      expect(ShipmentFieldMapper.recipientName(json), '');
      expect(ShipmentFieldMapper.isCod(json), isFalse);
    });

    test('F. Phone priority', () {
      final json = {
        'delivery_phone': 'RECIPIENT-123',
        'collection_phone': 'MERCHANT-999',
        'customer': {'phone': 'CORP-555'}
      };

      expect(ShipmentFieldMapper.recipientPhone(json), 'RECIPIENT-123');
    });

    test('G. Amount conversion for Nearpay', () {
      double sar = 10.50;
      int halalas = (sar * 100).round();
      expect(halalas, 1050);

      sar = 1.00;
      halalas = (sar * 100).round();
      expect(halalas, 100);
      
      sar = 0;
      halalas = (sar * 100).round();
      expect(halalas, 0);
    });
  });
}
