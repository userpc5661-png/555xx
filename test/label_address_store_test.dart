import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/models/task_item.dart';
import 'package:sls_assistant_pro/services/label_address_store.dart';
import 'package:sls_assistant_pro/services/location_correction_service.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('an address read while scanning is found from the task list', () async {
    // Real shapes: the scanner gets orders/awb (order_id, outgoing_tn,
    // reference_no); the task list row nests `order` without those extras.
    final scanned = {
      'id': 4371825852,
      'order_id': '280926067811718',
      'outgoing_tn': '280926067811718',
      'reference_no': '8005338638-24892503-1',
    };
    final store = LabelAddressStore.instance;
    await store.saveForIds(
      LabelAddressStore.idsOfOrder(scanned, '280926067811718'),
      'EHAC4301',
      location: const CorrectedLocation(26.41, 50.08),
    );

    final row = TaskItem.fromJson({
      'type': 'delivery',
      'customer_name': 'Abdullah',
      'order': {
        'id': 4371825852,
        'order_id': '280926067811718',
        'status_code': 2,
        'delivery_location_lat': '26.39055362',
        'delivery_location_lng': '49.96598844',
      },
    });
    expect(store.forTask(row), 'EHAC4301');
    expect(store.locationForTask(row)!.latitude, 26.41);

    await store.applyToTasks([row]);
    final applied = await LocationCorrectionService.load(row);
    expect(applied!.longitude, 50.08);
  });
}
