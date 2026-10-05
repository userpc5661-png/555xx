import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';

void main() {
  group('TaskItem.fromJson', () {
    test('reads exact SLS order and location fields', () {
      final task = TaskItem.fromJson({
        'order_id': 44,
        'order_awb': 'SLS-123456',
        'merchant': {'name': 'متجر التجربة'},
        'customer_name': 'Ahmed',
        'customer_phone_with_code_multiple': '+966500000000',
        'delivery_location_address1': 'Riyadh, King Road',
        'delivery_location_lat': '24.7136',
        'delivery_location_lng': 46.6753,
        'order_status_code': 'OFD',
        'order_status_label_code': 'Out for delivery',
        'is_cod': true,
        'cod_amount': '125.50',
        'cod_payment_method': 'cash',
      });

      expect(task.referenceNumber, 'SLS-123456');
      expect(task.storeName, 'متجر التجربة');
      expect(task.latitude, 24.7136);
      expect(task.longitude, 46.6753);
      expect(task.paymentKind, PaymentKind.cashOnDelivery);
      expect(task.codAmount, 125.50);
      expect(task.hasCoordinates, isTrue);
    });

    test('reads nested order data and combined coordinates', () {
      final task = TaskItem.fromJson({
        'task': {
          'task_id': 9,
          'task_type': 'delivery',
        },
        'order': {
          'order_awb': 'SLS-NESTED-1',
          'customer_name': 'Sara',
          'task_address': 'Jeddah',
          'delivery_lat_long': '21.5433, 39.1728',
          'is_cod': false,
        },
      });

      expect(task.referenceNumber, 'SLS-NESTED-1');
      expect(task.latitude, 21.5433);
      expect(task.longitude, 39.1728);
      expect(task.paymentKind, PaymentKind.prepaid);
      expect(task.taskType, 'delivery');
    });

    test('reads store name from nested merchant full_name', () {
      final task = TaskItem.fromJson({
        'order_awb': 'SLS-STORE-1',
        'merchant': {
          'id': 77,
          'full_name': 'متجر المندوب',
        },
      });

      expect(task.storeName, 'متجر المندوب');
      expect(task.displayStoreName, 'متجر المندوب');
    });

    test('reads store name from sender company field', () {
      final task = TaskItem.fromJson({
        'order_awb': 'SLS-STORE-2',
        'sender_company_name': 'شركة المتجر',
      });

      expect(task.storeName, 'شركة المتجر');
    });

    test('reads store name from nested order client business field', () {
      final task = TaskItem.fromJson({
        'order': {
          'order_awb': 'SLS-STORE-3',
          'client': {'business_name': 'متجر العميل التجاري'},
          'customer_name': 'مستلم الشحنة',
        },
      });

      expect(task.storeName, 'متجر العميل التجاري');
      expect(task.customerName, 'مستلم الشحنة');
    });

    test('heuristically reads unknown merchant details without using customer',
        () {
      final task = TaskItem.fromJson({
        'order_awb': 'SLS-STORE-4',
        'merchant_details': {'official_display_title': 'متجر غير قياسي'},
        'customer': {'company_name': 'شركة العميل المستلم'},
      });

      expect(task.storeName, 'متجر غير قياسي');
    });

    test('rejects zero coordinates but keeps address navigation', () {
      final task = TaskItem.fromJson({
        'order_awb': 'SLS-ADDRESS-1',
        'delivery_location_address1': 'Dammam',
        'delivery_location_lat': 0,
        'delivery_location_lng': 0,
      });

      expect(task.hasCoordinates, isFalse);
      expect(task.hasNavigableLocation, isTrue);
    });

    test('extracts explicit numeric IDs and is_rvp flag', () {
      final task = TaskItem.fromJson({
        'order_status_id': 10,
        'order_status_label_id': 5,
        'order_type_id': 1,
        'current_is_rvp': '1',
      });

      expect(task.statusId, 10);
      expect(task.statusLabelId, 5);
      expect(task.orderTypeId, 1);
      expect(task.isRvp, 1);
    });

    test('uses status_code for official status discovery', () {
      final task = TaskItem.fromJson({
        'order_id': '170726197501141',
        'status': 'In Transit',
        'status_code': 2,
        'status_label': 'Out for delivery',
        'order_type': 'forward',
        'is_rto': 0,
      });

      expect(task.statusId, 2);
      expect(task.statusCode, '2');
      expect(task.statusLabel, 'Out for delivery');
      expect(task.orderType, 'forward');
      expect(task.isRvp, 0);
    });
  });

  group('real SLS shipment shape', () {
    // Trimmed from a real orders/awb response.
    Map<String, dynamic> shipment({Object? lat, Object? lng}) => {
          'id': 4371862843,
          'order_id': '11026199332639',
          'status': 'Completed',
          'status_code': 3,
          'status_label': 'Shipment delivered',
          'collection_location_lat': '24.62049597',
          'collection_location_lng': '46.8623039',
          'collection_location_na_short': 'RNMA7272',
          'delivery_location_lat': lat,
          'delivery_location_lng': lng,
          'delivery_location_na_short': 'EDJA7025',
          'customer': {'name': 'Salasah', 'lat': '24.619731', 'lng': '46.863063'},
        };

    test('uses the delivery coordinates', () {
      final task = TaskItem.fromJson(
        shipment(lat: '26.41950528', lng: '50.08020994'),
      );
      expect(task.latitude, 26.41950528);
      expect(task.longitude, 50.08020994);
      expect(task.progress, TaskProgress.completed);
    });

    test('never falls back to the merchant location', () {
      final task = TaskItem.fromJson(shipment(lat: null, lng: null));
      expect(task.latitude, isNull);
      expect(task.longitude, isNull);
    });
  });
}
