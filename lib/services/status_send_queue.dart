import 'dart:async';

import 'package:flutter/foundation.dart';

/// Result of one status update sent to SLS.
class StatusSendOutcome {
  /// The update is in SLS (reply received, or the shipment shows it).
  final bool ok;

  /// The shipment, read back from SLS, shows the new status.
  final bool confirmed;
  final Object? error;

  const StatusSendOutcome.success({required this.confirmed})
      : ok = true,
        error = null;

  const StatusSendOutcome.failure(this.error)
      : ok = false,
        confirmed = false;
}

enum StatusSendState { sending, failed }

class StatusSendJob {
  final String awb;
  final String label;
  StatusSendState state = StatusSendState.sending;
  String? message;

  /// True once the status screen has closed and the job finishes on its
  /// own; a failure then stays in the list until the driver dismisses it.
  bool detached = false;

  late final Future<StatusSendOutcome> future;

  StatusSendJob(this.awb, this.label);
}

/// Status updates still on their way to SLS, so the driver can keep
/// working while the server answers. Shown as a bar at the top of the home
/// screen; failed ones stay until dismissed. Also blocks sending the same
/// shipment twice while one send is in progress.
class StatusSendQueue {
  StatusSendQueue._();

  static final instance = StatusSendQueue._();

  final ValueNotifier<List<StatusSendJob>> jobs =
      ValueNotifier<List<StatusSendJob>>(const []);

  bool isSending(String awb) => jobs.value.any(
        (job) => job.awb == awb && job.state == StatusSendState.sending,
      );

  void _remove(StatusSendJob job) => jobs.value =
      List.unmodifiable(jobs.value.where((j) => !identical(j, job)));

  /// Starts [work] right away. [onSuccess] runs when the update is in SLS,
  /// whether or not the screen is still open.
  StatusSendJob start({
    required String awb,
    required String label,
    required Future<StatusSendOutcome> Function() work,
    FutureOr<void> Function(StatusSendOutcome outcome)? onSuccess,
  }) {
    final job = StatusSendJob(awb, label);
    jobs.value = List.unmodifiable([
      ...jobs.value.where((j) => j.awb != awb),
      job,
    ]);
    job.future = () async {
      StatusSendOutcome outcome;
      try {
        outcome = await work();
      } catch (error) {
        outcome = StatusSendOutcome.failure(error);
      }
      if (outcome.ok) {
        try {
          await onSuccess?.call(outcome);
        } catch (error) {
          debugPrint('Status send onSuccess failed: $error');
        }
        _remove(job);
      } else if (job.detached) {
        job
          ..state = StatusSendState.failed
          ..message = '${outcome.error}';
        jobs.value = List.unmodifiable(jobs.value);
      } else {
        // The screen is still open and shows the error itself.
        _remove(job);
      }
      return outcome;
    }();
    return job;
  }

  void dismiss(StatusSendJob job) => _remove(job);
}
