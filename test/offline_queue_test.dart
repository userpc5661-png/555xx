import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/offline_mode.dart';
import 'package:sls_assistant_pro/services/offline_queue.dart';
import 'package:sls_assistant_pro/services/scan_api_service.dart';

void main() {
  test('a saved update keeps every field after a restart', () {
    final saved = OfflineStatusUpdate(
      id: '1',
      awb: 'SLS123',
      reference: 'SLS123',
      customerName: 'محمد',
      displayLabel: 'تم التسليم',
      statusId: 3,
      statusLabel: 'Delivered',
      delivered: true,
      savedAt: DateTime(2026, 10, 9, 14, 30),
      taskRaw: const {'awb': 'SLS123', 'status_code': 2},
      nationalAddress: 'RRRD2929',
      rescheduleDate: '2026-10-10 09:00:00',
      codPaymentMethod: 'cash',
      imagePath: '/docs/offline_queue/photo_1.jpg',
      imageName: 'proof.jpg',
      assigneeId: 77,
      latitude: 24.7,
      longitude: 46.6,
    );

    final restored = OfflineStatusUpdate.fromJson(saved.toJson());

    expect(restored.awb, 'SLS123');
    expect(restored.customerName, 'محمد');
    expect(restored.statusId, 3);
    expect(restored.statusLabel, 'Delivered');
    expect(restored.delivered, isTrue);
    expect(restored.nationalAddress, 'RRRD2929');
    expect(restored.rescheduleDate, '2026-10-10 09:00:00');
    expect(restored.codPaymentMethod, 'cash');
    expect(restored.customerCodPaymentId, isNull);
    expect(restored.imagePath, '/docs/offline_queue/photo_1.jpg');
    expect(restored.assigneeId, 77);
    expect(restored.latitude, 24.7);
    expect(restored.longitude, 46.6);
    expect(restored.savedAt, DateTime(2026, 10, 9, 14, 30));
    expect(restored.taskRaw['awb'], 'SLS123');
    expect(restored.state, OfflineItemState.waiting);
  });

  test('a send cut off by closing the app waits to be sent again', () {
    final item = OfflineStatusUpdate(
      id: '2',
      awb: 'A',
      reference: 'A',
      customerName: '',
      displayLabel: 'العميل لا يجيب',
      statusId: '2',
      statusLabel: 'Consignee is not answering',
      delivered: false,
      savedAt: DateTime(2026),
      taskRaw: const {},
      state: OfflineItemState.sending,
    );
    expect(
      OfflineStatusUpdate.fromJson(item.toJson()).state,
      OfflineItemState.waiting,
    );
    item
      ..state = OfflineItemState.failed
      ..error = 'رمز OTP غير صحيح';
    final failed = OfflineStatusUpdate.fromJson(item.toJson());
    expect(failed.state, OfflineItemState.failed);
    expect(failed.error, 'رمز OTP غير صحيح');
    expect(failed.statusId, '2');
  });

  test('no connection counts as a network error, a refusal does not', () {
    expect(OfflineMode.isNetworkError(TimeoutException('slow')), isTrue);
    expect(
      OfflineMode.isNetworkError(
        DioException(requestOptions: RequestOptions(path: '/')),
      ),
      isTrue,
    );
    expect(
      OfflineMode.isNetworkError(const ScanApiException('connection error')),
      isTrue,
    );
    expect(
      OfflineMode.isNetworkError(
        const ScanApiException('refused', statusCode: 422),
      ),
      isFalse,
    );
    expect(
      OfflineMode.isNetworkError(
        const ScanApiException('رفض', responseBody: '{"success":false}'),
      ),
      isFalse,
    );
  });
}
