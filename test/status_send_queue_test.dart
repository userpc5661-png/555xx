import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sls_assistant_pro/services/status_send_queue.dart';

void main() {
  final queue = StatusSendQueue.instance;

  test('blocks a second send of the same shipment while sending', () async {
    final gate = Completer<StatusSendOutcome>();
    var successes = 0;
    final job = queue.start(
      awb: 'A1',
      label: 'Delivered',
      work: () => gate.future,
      onSuccess: (_) => successes++,
    );
    expect(queue.isSending('A1'), isTrue);
    gate.complete(const StatusSendOutcome.success(confirmed: true));
    await job.future;
    expect(queue.isSending('A1'), isFalse);
    expect(successes, 1);
    expect(queue.jobs.value, isEmpty);
  });

  test('a failure after the screen closed stays until dismissed', () async {
    final gate = Completer<StatusSendOutcome>();
    final job = queue.start(
      awb: 'B2',
      label: 'Delivered',
      work: () => gate.future,
    );
    job.detached = true;
    gate.complete(const StatusSendOutcome.failure('timeout'));
    await job.future;
    expect(queue.jobs.value.single.state, StatusSendState.failed);
    queue.dismiss(job);
    expect(queue.jobs.value, isEmpty);
  });

  test('a failure while the screen is open is left to the screen', () async {
    final job = queue.start(
      awb: 'C3',
      label: 'Delivered',
      work: () async => const StatusSendOutcome.failure('refused'),
    );
    final outcome = await job.future;
    expect(outcome.ok, isFalse);
    expect(queue.jobs.value, isEmpty);
  });
}
