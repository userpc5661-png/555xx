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
  final String referenceNumber;
  final String statusCode;
  final String statusLabelCode;
  final Map<String, dynamic> raw;

  const ScannedShipment({
    required this.id,
    required this.referenceNumber,
    required this.statusCode,
    required this.statusLabelCode,
    required this.raw,
  });

  factory ScannedShipment.fromJson(Map<String, dynamic> json) {
    return ScannedShipment(
      id: _asInt(json['id']),
      referenceNumber: (json['reference_no'] ?? '').toString(),
      statusCode: (json['order_status_code'] ?? '').toString(),
      statusLabelCode: (json['order_status_label_code'] ?? '').toString(),
      raw: json,
    );
  }
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
