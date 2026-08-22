import 'dart:convert';
import '../utils/shipment_field_mapper.dart';

class ScanActionResult {
  final bool success;
  final String message;
  final Map<String, dynamic> raw;

  const ScanActionResult({
    required this.success,
    required this.message,
    required this.raw,
  });

  factory ScanActionResult.fromJson(Map<String, dynamic> json) {
    final value = json['success'];
    final success = value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
    return ScanActionResult(
      success: success,
      message: (json['message'] ?? json['success'] ?? '').toString(),
      raw: json,
    );
  }
}

class ScanAttemptResult {
  final String type;
  final String method;
  final String sanitizedUrl;
  final Map<String, dynamic> sanitizedQuery;
  final dynamic sanitizedBody;
  final int statusCode;
  final String responseBody;
  final String? errorMessage;
  final DateTime timestamp;
  final bool succeeded;

  const ScanAttemptResult({
    required this.type,
    required this.method,
    required this.sanitizedUrl,
    required this.sanitizedQuery,
    required this.sanitizedBody,
    required this.statusCode,
    required this.responseBody,
    this.errorMessage,
    required this.timestamp,
    required this.succeeded,
  });

  ScanAttemptResult copyWith({
    String? type,
    String? method,
    String? sanitizedUrl,
    Map<String, dynamic>? sanitizedQuery,
    dynamic sanitizedBody,
    int? statusCode,
    String? responseBody,
    String? errorMessage,
    DateTime? timestamp,
    bool? succeeded,
  }) {
    return ScanAttemptResult(
      type: type ?? this.type,
      method: method ?? this.method,
      sanitizedUrl: sanitizedUrl ?? this.sanitizedUrl,
      sanitizedQuery: sanitizedQuery ?? this.sanitizedQuery,
      sanitizedBody: sanitizedBody ?? this.sanitizedBody,
      statusCode: statusCode ?? this.statusCode,
      responseBody: responseBody ?? this.responseBody,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
      succeeded: succeeded ?? this.succeeded,
    );
  }
}

class DriverLocationRequest {
  final Object userId;
  final double latitude;
  final double longitude;

  const DriverLocationRequest({
    required this.userId,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson(String apiToken) => {
        'api_token': apiToken,
        'user_id': userId,
        'app_version': '3',
        'lat': latitude,
        'lng': longitude,
      };
}

class SubTrackingResponse {
  final bool success;
  final bool needsSubTrackingScan;
  final List<SubTrackingNumber> numbers;
  final Map<String, dynamic> raw;

  const SubTrackingResponse({
    required this.success,
    required this.needsSubTrackingScan,
    required this.numbers,
    required this.raw,
  });

  factory SubTrackingResponse.fromJson(Map<String, dynamic> json) {
    return SubTrackingResponse(
      success: _asBool(json['success']),
      needsSubTrackingScan: _asBool(json['is_need_sub_tracking_scan']),
      numbers: _maps(json['sub_tracking_numbers'])
          .map(SubTrackingNumber.fromJson)
          .toList(),
      raw: json,
    );
  }
}

class SubTrackingNumber {
  final int? id;
  final int? orderId;
  final String number;
  final bool isSortedScan;
  final bool isCompletedScan;
  final Map<String, dynamic> raw;

  const SubTrackingNumber({
    required this.id,
    required this.orderId,
    required this.number,
    required this.isSortedScan,
    required this.isCompletedScan,
    required this.raw,
  });

  factory SubTrackingNumber.fromJson(Map<String, dynamic> json) {
    return SubTrackingNumber(
      id: _asNullableInt(json['id']),
      orderId: _asNullableInt(json['order_id']),
      number: (json['sub_tracking_number'] ?? '').toString(),
      isSortedScan: _asBool(json['is_sorted_scan']),
      isCompletedScan: _asBool(json['is_completed_scan']),
      raw: json,
    );
  }
}

class SequencerOrder {
  final String orderId;
  final int? id;
  final double? latitude;
  final double? longitude;
  final String city;
  final String address1;
  final String address2;
  final String status;
  final String statusLabel;
  final String customerName;
  final String customerPhone;
  final Map<String, dynamic> raw;

  const SequencerOrder({
    required this.orderId,
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.address1,
    required this.address2,
    required this.status,
    required this.statusLabel,
    required this.customerName,
    required this.customerPhone,
    required this.raw,
  });

  factory SequencerOrder.fromJson(Map<String, dynamic> json) {
    return SequencerOrder(
      orderId: (json['order_id'] ?? '').toString(),
      id: _asNullableInt(json['id']),
      latitude: _asNullableDouble(json['lat']),
      longitude: _asNullableDouble(json['lng']),
      city: (json['city'] ?? '').toString(),
      address1: (json['address1'] ?? '').toString(),
      address2: (json['address2'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      statusLabel: (json['status_label'] ?? '').toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      customerPhone: (json['customer_phone'] ?? '').toString(),
      raw: json,
    );
  }
}

class LinehaulGroup {
  final int id;
  final String status;
  final HubSummary? originHub;
  final HubSummary? destinationHub;
  final List<LinehaulOrder> orders;
  final Map<String, dynamic> raw;

  const LinehaulGroup({
    required this.id,
    required this.status,
    required this.originHub,
    required this.destinationHub,
    required this.orders,
    required this.raw,
  });

  factory LinehaulGroup.fromJson(Map<String, dynamic> json) {
    return LinehaulGroup(
      id: _asInt(json['id']),
      status: (json['status'] ?? '').toString(),
      originHub: HubSummary.fromValue(json['origin_hub']),
      destinationHub: HubSummary.fromValue(json['destination_hub']),
      orders: _maps(json['orders']).map(LinehaulOrder.fromJson).toList(),
      raw: json,
    );
  }
}

class HubSummary {
  final int? id;
  final String name;
  final Map<String, dynamic> raw;

  const HubSummary({required this.id, required this.name, required this.raw});

  static HubSummary? fromValue(dynamic value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    return HubSummary(
      id: _asNullableInt(json['id']),
      name: (json['name'] ?? '').toString(),
      raw: json,
    );
  }
}

class LinehaulOrder {
  final int? id;
  final String orderId;
  final String status;
  final String statusLabel;
  final String referenceNumber;
  final Map<String, dynamic> raw;

  const LinehaulOrder({
    required this.id,
    required this.orderId,
    required this.status,
    required this.statusLabel,
    required this.referenceNumber,
    required this.raw,
  });

  factory LinehaulOrder.fromJson(Map<String, dynamic> json) {
    return LinehaulOrder(
      id: _asNullableInt(json['id']),
      orderId: (json['order_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      statusLabel: (json['status_label'] ?? '').toString(),
      referenceNumber: (json['reference_no'] ?? '').toString(),
      raw: json,
    );
  }
}

class ScannedOrderGroup {
  final int id;
  final List<GroupOrder> orders;
  final Map<String, dynamic> raw;

  const ScannedOrderGroup({
    required this.id,
    required this.orders,
    required this.raw,
  });

  factory ScannedOrderGroup.fromJson(Map<String, dynamic> json) {
    return ScannedOrderGroup(
      id: _asInt(json['id']),
      orders: _maps(json['orders']).map(GroupOrder.fromJson).toList(),
      raw: json,
    );
  }
}

class GroupOrder {
  final int? id;
  final String orderId;
  final String referenceNumber;
  final String confirmStatus;
  final Map<String, dynamic> raw;

  const GroupOrder({
    required this.id,
    required this.orderId,
    required this.referenceNumber,
    required this.confirmStatus,
    required this.raw,
  });

  bool get isConfirmed {
    final value = confirmStatus.trim().toLowerCase();
    return value == '1' ||
        value == 'true' ||
        value == 'yes' ||
        value.contains('confirm') ||
        value.contains('تم التأكيد');
  }

  factory GroupOrder.fromJson(Map<String, dynamic> json) {
    final pivot = json['pivot'];
    final pivotJson = pivot is Map
        ? Map<String, dynamic>.from(pivot)
        : const <String, dynamic>{};
    return GroupOrder(
      id: _asNullableInt(json['id']),
      orderId: (json['order_id'] ?? '').toString(),
      referenceNumber:
          (json['order_awb'] ?? json['reference_no'] ?? json['awb'] ?? '')
              .toString(),
      confirmStatus:
          (pivotJson['confirm_status'] ?? json['confirm_status'] ?? '')
              .toString(),
      raw: json,
    );
  }
}

class ScannedShipment {
  final int id;
  final String actualAwb;
  final String referenceNumber;
  final String statusCode;
  final String statusLabelCode;
  final String statusText;
  final String customerName;
  final String customerPhone;
  final String storeName;
  final String paymentMethod;
  final String amount;
  final String address;
  final Map<String, dynamic> raw;

  const ScannedShipment({
    required this.id,
    required this.actualAwb,
    required this.referenceNumber,
    required this.statusCode,
    required this.statusLabelCode,
    required this.statusText,
    required this.customerName,
    required this.customerPhone,
    required this.storeName,
    required this.paymentMethod,
    required this.amount,
    required this.address,
    required this.raw,
  });

  factory ScannedShipment.fromJson(Map<String, dynamic> json, String actualAwb) {
    return ScannedShipment(
      id: _asInt(_findRawValue(json, ['id', 'order_id'])),
      actualAwb: actualAwb,
      referenceNumber: ShipmentFieldMapper.shipmentNumber(json),
      statusCode: _findRawValue(json, ['order_status_code', 'status_code', 'status'])?.toString() ?? '',
      statusLabelCode: _findRawValue(json, ['order_status_label_code', 'status_label_code'])?.toString() ?? '',
      statusText: ShipmentFieldMapper.shipmentStatus(json),
      customerName: ShipmentFieldMapper.recipientName(json),
      customerPhone: ShipmentFieldMapper.recipientPhone(json),
      storeName: ShipmentFieldMapper.merchantName(json),
      paymentMethod: _findRawValue(json, ['cod_payment_method', 'payment_method'])?.toString() ?? '',
      amount: ShipmentFieldMapper.formatAmount(ShipmentFieldMapper.codAmount(json)),
      address: ShipmentFieldMapper.recipientAddress(json),
      raw: json,
    );
  }

  static dynamic _findRawValue(dynamic node, List<String> keys) {
    final wanted = keys.map((k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toSet();
    dynamic walk(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (wanted.contains(key) && entry.value != null) {
            final val = entry.value.toString().trim();
            if (val.isNotEmpty && val.toLowerCase() != 'null') return entry.value;
          }
        }
        for (final entry in value.entries) {
          final found = walk(entry.value);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final item in value) {
          final found = walk(item);
          if (found != null) return found;
        }
      }
      return null;
    }
    return walk(node);
  }
}

dynamic _deepValue(Map<String, dynamic> source, String path) {
  dynamic current = source;
  for (final part in path.split('.')) {
    if (current is Map) {
      current = current[part];
    } else {
      return null;
    }
  }
  if (current is Map) {
    for (final key in const ['text', 'name', 'label', 'value', 'code']) {
      final value = current[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
  }
  return current;
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

int _asInt(dynamic value) => _asNullableInt(value) ?? 0;

int? _asNullableInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

double? _asNullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _asBool(dynamic value) {
  return value == true ||
      value == 1 ||
      value?.toString().toLowerCase() == 'true';
}
