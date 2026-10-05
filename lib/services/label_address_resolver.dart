import '../models/task_item.dart';
import '../utils/label_text_parser.dart';
import '../utils/national_address_utils.dart';
import '../utils/shipment_field_mapper.dart';
import 'address_geocoding_service.dart';
import 'label_address_store.dart';
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
  await LabelAddressStore.instance.save(task, shortAddress);
  final location = await AddressGeocodingService.locate(shortAddress);
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
