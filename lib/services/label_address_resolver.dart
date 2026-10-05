import 'dart:io';
import 'dart:typed_data';

import '../models/task_item.dart';
import '../utils/label_text_parser.dart';
import '../utils/national_address_utils.dart';
import '../utils/shipment_field_mapper.dart';
import 'address_geocoding_service.dart';
import 'label_address_store.dart';
import 'label_ocr_service.dart';
import 'location_correction_service.dart';
import 'scan_api_service.dart';

/// The sender's National Address printed on the label next to the
/// customer's: the merchant for a delivery, the merchant receiving it for a
/// return. Read from the shipment data, or from orders/awb (GET) when the
/// task list does not carry it.
Future<String?> labelSenderShort(TaskItem task, {String? savedSession}) async {
  final field = ShipmentFieldMapper.isReverse(task.raw)
      ? 'delivery_location_na_short'
      : 'collection_location_na_short';
  String? read(Map<String, dynamic> raw) {
    for (final source in [raw, raw['order']]) {
      if (source is! Map) continue;
      final value = source[field];
      if (value is String) {
        final normalized = NationalAddressUtils.normalize(value);
        if (NationalAddressUtils.isValidShortAddress(normalized)) {
          return normalized;
        }
      }
    }
    return null;
  }

  final local = read(task.raw);
  if (local != null || savedSession == null || savedSession.isEmpty) {
    return local;
  }
  try {
    final shipment = await ScanApiService(savedSession: savedSession)
        .scanOrder(task.realAwb.trim());
    return read(shipment.raw);
  } catch (_) {
    return null;
  }
}

/// Saves the label's National Address for [task] and, when the phone can
/// locate it, uses it as the customer's location on this device.
Future<CorrectedLocation?> applyLabelAddress(
  TaskItem task,
  String shortAddress,
) async {
  final location = await AddressGeocodingService.locate(shortAddress);
  await LabelAddressStore.instance.save(task, shortAddress, location: location);
  if (location != null) {
    await LocationCorrectionService.save(task, location);
  }
  return location;
}

/// The customer's address on [scan], or null when the driver must choose.
Future<String?> customerShortFromLabel(
  TaskItem task,
  LabelScan scan, {
  String? savedSession,
}) async {
  if (scan.shortAddresses.isEmpty) return null;
  final sender = await labelSenderShort(task, savedSession: savedSession);
  return LabelTextParser.customerShort(scan, senderShort: sender);
}

enum LabelCaptureStatus { corrected, sameAsServer, notLocated, unreadable }

class LabelCaptureResult {
  final LabelCaptureStatus status;
  final String? shortAddress;
  const LabelCaptureResult(this.status, [this.shortAddress]);
}

/// Reads the label in a frame captured while scanning a shipment barcode
/// and stores the customer's National Address (and its location when it
/// differs from the server's) under the shipment's numbers. The task list
/// applies it once the shipment appears there. Runs in the background;
/// never throws.
Future<LabelCaptureResult> readLabelFromScanFrame({
  required Uint8List jpeg,
  required String code,
  required Map<String, dynamic> order,
}) async {
  File? file;
  try {
    file = File(
      '${Directory.systemTemp.path}/label_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(jpeg, flush: true);
    final scan = await LabelOcrService.readLabel(file.path);
    final task = TaskItem.fromJson(order);
    final sender = await labelSenderShort(task);
    final server = NationalAddressUtils.customerShortAddress(order);
    var chosen = LabelTextParser.customerShort(scan, senderShort: sender);
    if (chosen == null) {
      // Two left and one is the server's: the label's other one wins only
      // if the server's is not printed; otherwise the server's is right.
      final others = scan.shortAddresses.where((v) => v != sender).toList();
      if (server != null && others.contains(server)) chosen = server;
    }
    if (chosen == null) return const LabelCaptureResult(LabelCaptureStatus.unreadable);

    final ids = LabelAddressStore.idsOfOrder(order, code);
    if (chosen == server) {
      await LabelAddressStore.instance.saveForIds(ids, chosen);
      return LabelCaptureResult(LabelCaptureStatus.sameAsServer, chosen);
    }
    final location = await AddressGeocodingService.locate(chosen);
    await LabelAddressStore.instance.saveForIds(ids, chosen, location: location);
    return LabelCaptureResult(
      location == null
          ? LabelCaptureStatus.notLocated
          : LabelCaptureStatus.corrected,
      chosen,
    );
  } catch (_) {
    return const LabelCaptureResult(LabelCaptureStatus.unreadable);
  } finally {
    try {
      await file?.delete();
    } catch (_) {}
  }
}
