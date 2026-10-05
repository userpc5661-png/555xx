import '../utils/shipment_field_mapper.dart';

enum PaymentKind { cashOnDelivery, prepaid, unknown }

enum TaskProgress { completed, cancelled, remaining }

class TaskItem {
  final String id;
  final String referenceNumber;
  final String storeName;
  final String customerName;
  final String customerPhone;
  final String address;
  final double? latitude;
  final double? longitude;
  final String statusCode;
  final String statusLabel;
  final String taskType;
  final String orderType;
  final PaymentKind paymentKind;
  final double? codAmount;
  final String codPaymentMethod;
  final Object? statusId;
  final Object? statusLabelId;
  final Object? orderTypeId;
  final int isRvp;
  final Map<String, dynamic> raw;

  const TaskItem({
    required this.id,
    required this.referenceNumber,
    required this.storeName,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.statusCode,
    required this.statusLabel,
    required this.taskType,
    required this.orderType,
    required this.paymentKind,
    required this.codAmount,
    required this.codPaymentMethod,
    this.statusId,
    this.statusLabelId,
    this.orderTypeId,
    this.isRvp = 0,
    required this.raw,
  });

  TaskItem copyWith({
    String? id,
    String? referenceNumber,
    String? storeName,
    String? customerName,
    String? customerPhone,
    String? address,
    double? latitude,
    double? longitude,
    String? statusCode,
    String? statusLabel,
    String? taskType,
    String? orderType,
    PaymentKind? paymentKind,
    double? codAmount,
    String? codPaymentMethod,
    Object? statusId,
    Object? statusLabelId,
    Object? orderTypeId,
    int? isRvp,
    Map<String, dynamic>? raw,
  }) {
    return TaskItem(
      id: id ?? this.id,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      storeName: storeName ?? this.storeName,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      statusCode: statusCode ?? this.statusCode,
      statusLabel: statusLabel ?? this.statusLabel,
      taskType: taskType ?? this.taskType,
      orderType: orderType ?? this.orderType,
      paymentKind: paymentKind ?? this.paymentKind,
      codAmount: codAmount ?? this.codAmount,
      codPaymentMethod: codPaymentMethod ?? this.codPaymentMethod,
      statusId: statusId ?? this.statusId,
      statusLabelId: statusLabelId ?? this.statusLabelId,
      orderTypeId: orderTypeId ?? this.orderTypeId,
      isRvp: isRvp ?? this.isRvp,
      raw: raw ?? this.raw,
    );
  }

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasNavigableLocation => hasCoordinates || address.trim().isNotEmpty;
  bool get isCashOnDelivery => paymentKind == PaymentKind.cashOnDelivery;

  /// Official SLS assignee/driver identifier. The API may return it directly
  /// or nested inside assignee/driver/assigned_to objects.
  Object? get assigneeId {
    final direct = _findRawValue(raw, const [
      'assignee_id',
      'assigneeId',
      'driver_id',
      'driverId',
      'assigned_to_id',
      'assignedToId',
      'assigned_driver_id',
      'assignedDriverId',
    ]);
    if (_usableIdentifier(direct)) return direct;

    return _findIdentifierInside(raw, const [
      'assignee',
      'driver',
      'assigned_to',
      'assignedTo',
      'assigned_driver',
      'assignedDriver',
      'task_assignee',
      'taskAssignee',
    ]);
  }

  Object get officialOrderId {
    final value = _findRawValue(raw, const [
      'order_id',
      'orderId',
      'shipment_id',
      'shipmentId',
    ]);
    return _usableIdentifier(value) ? value! : id;
  }

  /// Returns the actual AWB/Tracking number for API calls, prioritizing
  /// official SLS fields over display references.
  String get baseAwb {
    final awb = realAwb.trim();
    final match = RegExp(r'^(.*?)[-_]\d+$').firstMatch(awb);
    if (match != null && match.group(1) != null && match.group(1)!.trim().isNotEmpty) {
      return match.group(1)!.trim();
    }
    return awb;
  }

  bool get isMultiPiece => RegExp(r'[-_]\d+$').hasMatch(realAwb.trim());

  String get realAwb {
    final value = _findRawValue(raw, const [
      'order_awb',
      'awb',
      'outgoing_tn',
      'reference_no',
      'referenceNo',
      'tracking_number',
      'trackingNumber',
    ]);
    if (value != null && value.toString().trim().isNotEmpty) {
      final text = value.toString().trim();
      if (text.toLowerCase() != 'null') return text;
    }
    return referenceNumber;
  }

  static bool _usableIdentifier(dynamic value) {
    if (value == null || value is Map || value is List) return false;
    final text = value.toString().trim().toLowerCase();
    return text.isNotEmpty && text != 'null' && text != '0';
  }

  static Object? _findIdentifierInside(dynamic node, List<String> parentKeys) {
    final parents = parentKeys.map(_normalize).toSet();

    Object? identifier(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = _normalize(entry.key.toString());
          if (const {'id', 'userid', 'driverid', 'assigneeid'}.contains(key) &&
              _usableIdentifier(entry.value)) {
            return entry.value;
          }
        }
      }
      return null;
    }

    Object? walk(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (parents.contains(_normalize(entry.key.toString()))) {
            final found = identifier(entry.value);
            if (found != null) return found;
          }
        }
        for (final child in value.values) {
          final found = walk(child);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final child in value) {
          final found = walk(child);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(node);
  }

  /// True only when the SLS task payload explicitly indicates that a delivery
  /// OTP / verification code is required. Payment type is deliberately not
  /// used here because COD/prepaid and OTP are separate business rules.
  bool get requiresDeliveryOtp {
    final explicit = _findRawValue(raw, const [
      'requires_otp',
      'requiresOtp',
      'otp_required',
      'otpRequired',
      'is_otp_required',
      'isOtpRequired',
      'requires_delivery_code',
      'requiresDeliveryCode',
      'delivery_code_required',
      'deliveryCodeRequired',
      'verification_required',
      'verificationRequired',
      'has_otp',
      'hasOtp',
      'has_delivery_code',
      'hasDeliveryCode',
    ]);
    final parsed = _rawBool(explicit);
    if (parsed != null) return parsed;

    // Some SLS variants send the code itself without a separate boolean flag.
    final code = deliveryOtpValue;
    return code.isNotEmpty;
  }

  /// OTP value returned by SLS when present. It is used only to detect that an
  /// OTP exists; the UI never exposes it to the driver.
  String get deliveryOtpValue {
    final value = _findRawValue(raw, const [
      'delivery_otp',
      'deliveryOtp',
      'otp_code',
      'otpCode',
      'delivery_code',
      'deliveryCode',
      'verification_code',
      'verificationCode',
      'consignee_otp',
      'consigneeOtp',
      'pod_code',
      'podCode',
    ]);
    if (value == null || value is Map || value is List) return '';
    final text = value.toString().trim();
    return text.toLowerCase() == 'null' ? '' : text;
  }

  static bool? _rawBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (const {'true', '1', 'yes', 'required', 'enabled'}.contains(text)) {
      return true;
    }
    if (const {'false', '0', 'no', 'not_required', 'disabled'}.contains(text)) {
      return false;
    }
    return null;
  }

  String get displayStoreName =>
      storeName.trim().isNotEmpty ? storeName.trim() : 'غير متوفر';

  String get displayReference {
    if (referenceNumber.trim().isNotEmpty) return referenceNumber.trim();
    if (id.trim().isNotEmpty) return id.trim();
    return 'بدون رقم شحنة';
  }

  String get paymentLabel {
    switch (paymentKind) {
      case PaymentKind.cashOnDelivery:
        return 'دفع عند الاستلام';
      case PaymentKind.prepaid:
        return 'مدفوعة مسبقًا';
      case PaymentKind.unknown:
        return 'الدفع غير محدد';
    }
  }

  TaskProgress get progress {
    final value = '$statusCode $statusLabel'.toLowerCase();
    if (_containsAny(value, const [
      'cancel',
      'canceled',
      'cancelled',
      'failed',
      'rejected',
      'ملغي',
      'ملغى',
      'إلغاء',
      'الغاء',
      'مرفوض',
      'فشل',
    ])) {
      return TaskProgress.cancelled;
    }
    if (_containsAny(value, const [
      'delivered',
      'complete',
      'completed',
      'done',
      'success',
      'pod',
      'تم التسليم',
      'تم التوصيل',
      'مسلّم',
      'مسلم',
      'مكتمل',
      'منجز',
    ])) {
      return TaskProgress.completed;
    }
    return TaskProgress.remaining;
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final reference = ShipmentFieldMapper.shipmentNumber(json);
    final storeName = ShipmentFieldMapper.merchantName(json);
    final customerName = ShipmentFieldMapper.recipientName(json);
    final customerPhone = ShipmentFieldMapper.recipientPhone(json);
    final address = ShipmentFieldMapper.recipientAddress(json);

    // Coordinate mapping fallbacks
    double? getCoord(List<String> keys) {
      for (final key in keys) {
        final val = _findRawValue(json, [key]);
        if (val is num && val != 0) return val.toDouble();
        if (val is String) {
          final p = double.tryParse(val.trim());
          if (p != null && p != 0) return p;
        }
      }
      return null;
    }

    // Generic "lat"/"lng" are read only at the top level of the shipment.
    // Searched recursively they matched nested objects such as `customer`
    // (the merchant, e.g. a Riyadh warehouse) and put the customer's pin at
    // the merchant when the delivery coordinates were missing.
    double? topLevelCoord(List<String> keys) {
      for (final key in keys) {
        final val = json[key];
        if (val is num && val != 0) return val.toDouble();
        if (val is String) {
          final p = double.tryParse(val.trim());
          if (p != null && p != 0) return p;
        }
      }
      return null;
    }

    var latitude = getCoord(['delivery_location_lat', 'delivery_latitude']) ??
        topLevelCoord(['lat', 'latitude']);
    var longitude = getCoord(['delivery_location_lng', 'delivery_longitude']) ??
        topLevelCoord(['lng', 'longitude']);

    // Fallback: parse combined "lat, lng" string from delivery_lat_long
    if (latitude == null || longitude == null) {
      final coords = ShipmentFieldMapper.extractCoordinates(json);
      latitude ??= coords[0];
      longitude ??= coords[1];
    }

    final cod = ShipmentFieldMapper.codAmount(json);
    final isCodFlag = ShipmentFieldMapper.isCod(json);

    final codPaymentMethod = _findRawValue(json, ['cod_payment_method', 'payment_method'])?.toString() ?? '';
    final paymentText = _findRawValue(json, ['payment_type', 'payment_method', 'payment_status', 'is_cod', 'cod'])?.toString().toLowerCase() ?? '';

    PaymentKind paymentKind = PaymentKind.unknown;
    if (isCodFlag || _containsAny(paymentText, const ['cod', 'cash', 'collect', 'دفع عند الاستلام', 'عند الاستلام'])) {
      paymentKind = PaymentKind.cashOnDelivery;
    } else if (_containsAny(paymentText, const ['paid', 'prepaid', 'online', 'card'])) {
      paymentKind = PaymentKind.prepaid;
    } else if (cod <= 0) {
      paymentKind = PaymentKind.prepaid;
    }

    // The status-discovery API expects the shipment's current status code.
    // Prefer the real status_code from the order payload and only fall back to
    // legacy keys. Using a recursively found status_id can accidentally pick a
    // nested status-label id and makes the server return the wrong status list.
    final statusId = _toInt(_findTopLevelOrNestedValue(
      json,
      const ['status_code', 'order_status_code', 'current_status'],
      fallbackKeys: const ['status_id', 'order_status_id'],
    ));
    final statusLabelId = _toDouble(_findRawValue(json, ['status_label_id', 'order_status_label_id', 'current_status_label']));
    final orderTypeId = _toDouble(_findRawValue(json, ['order_type_id', 'current_order_type']));

    // ---- Status extraction ----
    final dynamic statusCodeRaw = json['status_code'] ?? json['order_status_code'] ?? json['status'];
    final String statusCode = statusCodeRaw?.toString() ?? '';

    return TaskItem(
      id: _findRawValue(json, ['order_id', 'task_id', 'shipment_id', 'id'])?.toString() ?? '',
      referenceNumber: reference,
      storeName: storeName,
      customerName: customerName,
      customerPhone: customerPhone,
      address: address,
      latitude: latitude,
      longitude: longitude,
      statusCode: statusCode,
      statusLabel: ShipmentFieldMapper.shipmentStatus(json),
      taskType: _findRawValue(json, ['task_type', 'task_name'])?.toString() ?? '',
      orderType: _findRawValue(json, ['order_type'])?.toString() ?? '',
      paymentKind: paymentKind,
      codAmount: cod,
      codPaymentMethod: codPaymentMethod,
      statusId: statusId,
      statusLabelId: statusLabelId,
      orderTypeId: orderTypeId,
      isRvp: _rawBool(_findRawValue(json, ['is_rvp', 'current_is_rvp'])) == true ? 1 : 0,
      raw: Map<String, dynamic>.from(json),
    );
  }


  static dynamic _findTopLevelOrNestedValue(
    Map<String, dynamic> json,
    List<String> preferredKeys, {
    List<String> fallbackKeys = const [],
  }) {
    for (final key in preferredKeys) {
      final value = json[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    final preferred = _findRawValue(json, preferredKeys);
    if (preferred != null) return preferred;
    for (final key in fallbackKeys) {
      final value = json[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return _findRawValue(json, fallbackKeys);
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
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

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _containsAny(String value, List<String> candidates) =>
      candidates.any(value.contains);

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }
}
