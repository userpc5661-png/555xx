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

/// Reads the customer's National Address from a camera frame of the label
/// (on device). Null when it cannot be read clearly enough.
Future<LabelRead?> readCustomerShortFromFrame({
  required Uint8List jpeg,
  required Map<String, dynamic> order,
}) async {
  File? file;
  try {
    file = File(
      '${Directory.systemTemp.path}/label_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(jpeg, flush: true);
    final scan = await LabelOcrService.readLabel(file.path);
    final sender = await labelSenderShort(TaskItem.fromJson(order));
    final server = NationalAddressUtils.customerShortAddress(order);
    return LabelTextParser.customerRead(
      scan,
      senderShort: sender,
      serverCustomerShort: server,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      await file?.delete();
    } catch (_) {}
  }
}

/// Stores the label's address under all of the shipment's numbers, with
/// its location when it differs from the server's. The task list applies
/// it once the shipment appears there. Never throws.
Future<LabelCaptureResult> storeLabelAddress({
  required String code,
  required Map<String, dynamic> order,
  required String shortAddress,
}) async {
  try {
    final ids = LabelAddressStore.idsOfOrder(order, code);
    final server = NationalAddressUtils.customerShortAddress(order);
    if (shortAddress == server) {
      await LabelAddressStore.instance.saveForIds(ids, shortAddress);
      return LabelCaptureResult(LabelCaptureStatus.sameAsServer, shortAddress);
    }
    final location = await AddressGeocodingService.locate(shortAddress);
    await LabelAddressStore.instance
        .saveForIds(ids, shortAddress, location: location);
    return LabelCaptureResult(
      location == null
          ? LabelCaptureStatus.notLocated
          : LabelCaptureStatus.corrected,
      shortAddress,
    );
  } catch (_) {
    return LabelCaptureResult(LabelCaptureStatus.notLocated, shortAddress);
  }
}
