import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task_item.dart';
import '../utils/status_verification.dart';
import 'account_store.dart';
import 'alert_sounds.dart';
import 'delivery_history_store.dart';
import 'offline_mode.dart';
import 'scan_api_service.dart';

enum OfflineItemState { waiting, sending, failed }

/// A status update saved on the phone in offline mode, with everything
/// needed to send it later exactly as the status screen would.
class OfflineStatusUpdate {
  final String id;
  final String awb;
  final String reference;
  final String customerName;
  final String displayLabel;
  final Object statusId;
  final String statusLabel;
  final bool delivered;
  final String? nationalAddress;
  final String? rescheduleDate;
  final String? codPaymentMethod;
  final String? customerCodPaymentId;
  final String? imagePath;
  final String? imageName;
  final Object? assigneeId;
  final double? latitude;
  final double? longitude;
  final DateTime savedAt;
  final Map<String, dynamic> taskRaw;
  OfflineItemState state;
  String? error;

  OfflineStatusUpdate({
    required this.id,
    required this.awb,
    required this.reference,
    required this.customerName,
    required this.displayLabel,
    required this.statusId,
    required this.statusLabel,
    required this.delivered,
    required this.savedAt,
    required this.taskRaw,
    this.nationalAddress,
    this.rescheduleDate,
    this.codPaymentMethod,
    this.customerCodPaymentId,
    this.imagePath,
    this.imageName,
    this.assigneeId,
    this.latitude,
    this.longitude,
    this.state = OfflineItemState.waiting,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'awb': awb,
        'reference': reference,
        'customer_name': customerName,
        'display_label': displayLabel,
        'status_id': statusId,
        'status_label': statusLabel,
        'delivered': delivered,
        'national_address': nationalAddress,
        'reschedule_date': rescheduleDate,
        'cod_payment_method': codPaymentMethod,
        'customer_cod_payment_id': customerCodPaymentId,
        'image_path': imagePath,
        'image_name': imageName,
        'assignee_id': assigneeId,
        'latitude': latitude,
        'longitude': longitude,
        'saved_at': savedAt.toIso8601String(),
        'task_raw': taskRaw,
        // A send cut off by closing the app is sent again.
        'state': state == OfflineItemState.failed ? 'failed' : 'waiting',
        'error': error,
      };

  factory OfflineStatusUpdate.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    String? text(Object? value) =>
        value == null || '$value'.isEmpty ? null : '$value';
    return OfflineStatusUpdate(
      id: '${json['id']}',
      awb: '${json['awb'] ?? ''}',
      reference: '${json['reference'] ?? ''}',
      customerName: '${json['customer_name'] ?? ''}',
      displayLabel: '${json['display_label'] ?? ''}',
      statusId: json['status_id'] as Object,
      statusLabel: '${json['status_label'] ?? ''}',
      delivered: json['delivered'] == true,
      nationalAddress: text(json['national_address']),
      rescheduleDate: text(json['reschedule_date']),
      codPaymentMethod: text(json['cod_payment_method']),
      customerCodPaymentId: text(json['customer_cod_payment_id']),
      imagePath: text(json['image_path']),
      imageName: text(json['image_name']),
      assigneeId: json['assignee_id'],
      latitude: number(json['latitude']),
      longitude: number(json['longitude']),
      savedAt: DateTime.tryParse('${json['saved_at']}') ?? DateTime.now(),
      taskRaw: json['task_raw'] is Map
          ? Map<String, dynamic>.from(json['task_raw'] as Map)
          : <String, dynamic>{},
      state: json['state'] == 'failed'
          ? OfflineItemState.failed
          : OfflineItemState.waiting,
      error: text(json['error']),
    );
  }
}

/// Result of sending the saved updates.
class OfflineSyncResult {
  final int sent;
  final int failed;
  final bool stoppedByNetwork;
  const OfflineSyncResult({
    required this.sent,
    required this.failed,
    required this.stoppedByNetwork,
  });
}

/// Status updates saved in offline mode, sent one by one, in the order
/// they were saved, when the driver switches to Online.
class OfflineQueue {
  OfflineQueue._();

  static final instance = OfflineQueue._();

  final ValueNotifier<List<OfflineStatusUpdate>> items =
      ValueNotifier<List<OfflineStatusUpdate>>(const []);
  final ValueNotifier<bool> syncing = ValueNotifier<bool>(false);
  String? _loadedFor;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_queue');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file() async => File(
        '${(await _dir()).path}/queue_${AccountStore.currentAccountId}.json',
      );

  Future<void> load() async {
    if (_loadedFor == AccountStore.currentAccountId) return;
    try {
      final file = await _file();
      final list = await file.exists()
          ? jsonDecode(await file.readAsString()) as List
          : const [];
      items.value = List.unmodifiable([
        for (final row in list.whereType<Map>())
          OfflineStatusUpdate.fromJson(Map<String, dynamic>.from(row)),
      ]);
      _loadedFor = AccountStore.currentAccountId;
    } catch (error) {
      debugPrint('Offline queue: reading failed: $error');
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode([for (final item in items.value) item.toJson()]),
      );
    } catch (error) {
      debugPrint('Offline queue: saving failed: $error');
    }
  }

  void _publish() => items.value = List.unmodifiable(items.value);

  /// The newest saved update for [awb], if any.
  OfflineStatusUpdate? pendingFor(String awb) {
    final key = awb.trim();
    if (key.isEmpty) return null;
    for (final item in items.value.reversed) {
      if (item.awb == key || item.reference == key) return item;
    }
    return null;
  }

  /// Saves an update. The photo is copied next to the queue, so it is
  /// still there when the update is sent.
  Future<OfflineStatusUpdate> add({
    required String awb,
    required TaskItem task,
    required String displayLabel,
    required Object statusId,
    required String statusLabel,
    required bool delivered,
    String? nationalAddress,
    String? rescheduleDate,
    String? codPaymentMethod,
    String? customerCodPaymentId,
    String? imagePath,
    String? imageName,
    Object? assigneeId,
    double? latitude,
    double? longitude,
  }) async {
    await load();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    String? storedImage;
    if (imagePath != null) {
      final ext = imagePath.contains('.')
          ? imagePath.substring(imagePath.lastIndexOf('.'))
          : '.jpg';
      final copy = await File(imagePath)
          .copy('${(await _dir()).path}/photo_$id$ext');
      storedImage = copy.path;
    }
    final item = OfflineStatusUpdate(
      id: id,
      awb: awb,
      reference: task.displayReference,
      customerName: task.customerName,
      displayLabel: displayLabel,
      statusId: statusId,
      statusLabel: statusLabel,
      delivered: delivered,
      nationalAddress: nationalAddress,
      rescheduleDate: rescheduleDate,
      codPaymentMethod: codPaymentMethod,
      customerCodPaymentId: customerCodPaymentId,
      imagePath: storedImage,
      imageName: imageName,
      assigneeId: assigneeId,
      latitude: latitude,
      longitude: longitude,
      savedAt: DateTime.now(),
      taskRaw: task.raw,
    );
    items.value = List.unmodifiable([...items.value, item]);
    await _save();
    return item;
  }

  Future<void> remove(OfflineStatusUpdate item) async {
    items.value = List.unmodifiable(
      items.value.where((other) => other.id != item.id),
    );
    await _save();
    final path = item.imagePath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// Sends every saved update, oldest first, one at a time. Each one is
  /// confirmed on the server the same way as a normal send. A refused
  /// update stays in red with the server's reason; losing the connection
  /// stops the sending, and the rest stay waiting.
  Future<OfflineSyncResult> sync(String savedSession) async {
    await load();
    if (syncing.value) {
      return const OfflineSyncResult(
        sent: 0,
        failed: 0,
        stoppedByNetwork: false,
      );
    }
    syncing.value = true;
    var sent = 0;
    var failed = 0;
    var deliveredSent = false;
    var stoppedByNetwork = false;
    try {
      final api = ScanApiService(savedSession: savedSession);
      for (final item in List.of(items.value)) {
        if (OfflineMode.isOn) break;
        if (!items.value.any((other) => other.id == item.id)) continue;
        item
          ..state = OfflineItemState.sending
          ..error = null;
        _publish();
        Object? error;
        try {
          await _send(api, item);
        } catch (e) {
          error = e;
        }
        if (error == null) {
          sent++;
          if (item.delivered) {
            deliveredSent = true;
            try {
              await DeliveryHistoryStore.instance.recordCompleted(
                TaskItem.fromJson(item.taskRaw),
                awb: item.awb,
              );
            } catch (_) {}
          }
          await remove(item);
          continue;
        }
        if (OfflineMode.isNetworkError(error)) {
          // No point trying the rest without a connection; this one and
          // the rest stay waiting.
          item
            ..state = OfflineItemState.waiting
            ..error = null;
          stoppedByNetwork = true;
          break;
        }
        item
          ..state = OfflineItemState.failed
          ..error = '$error';
        _publish();
        await _save();
        failed++;
      }
    } finally {
      for (final item in items.value) {
        if (item.state == OfflineItemState.sending) {
          item.state = OfflineItemState.waiting;
        }
      }
      _publish();
      syncing.value = false;
    }
    if (deliveredSent) AlertSounds.delivered();
    return OfflineSyncResult(
      sent: sent,
      failed: failed,
      stoppedByNetwork: stoppedByNetwork,
    );
  }

  /// Sends one update and waits until SLS shows it, like the status screen:
  /// SLS applies a delivery within ~1s but can reply after a minute, so the
  /// shipment is read back while the reply is pending.
  Future<void> _send(ScanApiService api, OfflineStatusUpdate item) async {
    Future<bool> shows(DateTime since) async {
      try {
        final shipment = await api.scanOrder(item.awb);
        return StatusVerification.matches(
          shipment.raw,
          sentStatusId: item.statusId,
          delivered: item.delivered,
          sentStatusLabel: item.statusLabel,
          sentAt: since,
        );
      } catch (error) {
        if (OfflineMode.isNetworkError(error)) rethrow;
        return false;
      }
    }

    // A delivery may already be on the server (e.g. sent earlier from the
    // official app); then it is not sent twice.
    if (item.delivered && await shows(item.savedAt)) return;

    final image = item.imagePath;
    final body = <String, dynamic>{
      'status': item.statusId,
      'status_label': item.statusLabel,
      'awbs': [item.awb],
      // The official SLS app (1.9.13) sends the new National Address in
      // its form field "location".
      if (item.nationalAddress != null) 'location': item.nationalAddress,
      if (image != null)
        'poc_attachment': await MultipartFile.fromFile(
          image,
          filename: item.imageName ?? image.split('/').last,
        ),
      if (item.rescheduleDate != null) 'reschedule_date': item.rescheduleDate,
      if (item.codPaymentMethod != null)
        'cod_payment_method': item.codPaymentMethod,
      if (item.customerCodPaymentId != null)
        'customer_cod_payment_id': item.customerCodPaymentId,
    };

    final sentAt = DateTime.now();
    Object? postError;
    var postDone = false;
    unawaited(
      api
          .updateStatus(
            officialBody: body,
            assigneeId: item.assigneeId,
            latitude: item.latitude,
            longitude: item.longitude,
          )
          .then(
            (_) => postDone = true,
            onError: (Object error) {
              postError = error;
              postDone = true;
            },
          ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 700));
    while (true) {
      if (postDone) {
        final error = postError;
        if (error == null) return;
        // A 4xx answer is a real refusal; a 5xx or no answer may still
        // have been applied, so the shipment decides.
        final status = error is ScanApiException ? error.statusCode : null;
        if (status != null && status < 500) throw error;
        bool applied;
        try {
          applied = await shows(sentAt);
          if (!applied) {
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            applied = await shows(sentAt);
          }
        } catch (_) {
          applied = false;
        }
        if (applied) return;
        throw error;
      }
      bool confirmed;
      try {
        confirmed = await shows(sentAt);
      } catch (_) {
        confirmed = false;
      }
      if (confirmed) return;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }
}
