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

  static dynamic _findRawValue(dynamic node, List<String> keys) {
    final wanted = keys.map(_normalize).toSet();
    dynamic walk(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (wanted.contains(_normalize(entry.key.toString())) &&
              entry.value != null) {
            return entry.value;
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
    final values = <String, List<dynamic>>{};

    void collect(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = _normalize(entry.key.toString());
          values.putIfAbsent(key, () => <dynamic>[]).add(entry.value);
          collect(entry.value);
        }
      } else if (node is List) {
        for (final item in node) {
          collect(item);
        }
      }
    }

    collect(json);

    String text(List<String> keys) {
      String scalar(dynamic value) {
        if (value == null || value is Map) return '';
        if (value is List) {
          for (final item in value) {
            final result = scalar(item);
            if (result.isNotEmpty) return result;
          }
          return '';
        }
        final result = value.toString().trim();
        if (result.isEmpty || result.toLowerCase() == 'null') return '';
        return result;
      }

      for (final key in keys) {
        for (final value in values[_normalize(key)] ?? const <dynamic>[]) {
          final result = scalar(value);
          if (result.isNotEmpty) return result;
        }
      }
      return '';
    }

    String textInsideParents(
      List<String> parentKeys,
      List<String> childKeys,
    ) {
      final parents = parentKeys.map(_normalize).toSet();
      final children = childKeys.map(_normalize).toSet();

      String scalar(dynamic value) {
        if (value == null || value is Map || value is List) return '';
        final result = value.toString().trim();
        if (result.isEmpty || result.toLowerCase() == 'null') return '';
        return result;
      }

      String searchInside(dynamic node) {
        if (node is Map) {
          for (final entry in node.entries) {
            if (children.contains(_normalize(entry.key.toString()))) {
              final result = scalar(entry.value);
              if (result.isNotEmpty) return result;
            }
          }
          for (final value in node.values) {
            final result = searchInside(value);
            if (result.isNotEmpty) return result;
          }
        } else if (node is List) {
          for (final value in node) {
            final result = searchInside(value);
            if (result.isNotEmpty) return result;
          }
        }
        return '';
      }

      String walk(dynamic node) {
        if (node is Map) {
          for (final entry in node.entries) {
            if (parents.contains(_normalize(entry.key.toString()))) {
              final direct = scalar(entry.value);
              if (direct.isNotEmpty) return direct;
              final nested = searchInside(entry.value);
              if (nested.isNotEmpty) return nested;
            }
          }
          for (final value in node.values) {
            final result = walk(value);
            if (result.isNotEmpty) return result;
          }
        } else if (node is List) {
          for (final value in node) {
            final result = walk(value);
            if (result.isNotEmpty) return result;
          }
        }
        return '';
      }

      return walk(json);
    }

    double? number(List<String> keys) {
      for (final key in keys) {
        for (final value in values[_normalize(key)] ?? const <dynamic>[]) {
          if (value is num) return value.toDouble();
          if (value == null || value is Map || value is List) continue;
          final cleaned = value
              .toString()
              .trim()
              .replaceAll(',', '')
              .replaceAll(RegExp(r'[^0-9+\-.]'), '');
          final parsed = double.tryParse(cleaned);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    bool? boolean(List<String> keys) {
      for (final key in keys) {
        for (final value in values[_normalize(key)] ?? const <dynamic>[]) {
          if (value is bool) return value;
          if (value is num) return value != 0;
          final normalized = value?.toString().trim().toLowerCase();
          if (normalized == 'true' ||
              normalized == 'yes' ||
              normalized == '1') {
            return true;
          }
          if (normalized == 'false' ||
              normalized == 'no' ||
              normalized == '0') {
            return false;
          }
        }
      }
      return null;
    }

    (double?, double?) coordinatesFromCombinedValue() {
      const keys = [
        'delivery_lat_long',
        'deliveryLatLong',
        'lat_lng',
        'latLng',
        'coordinates',
        'location_coordinates',
      ];
      for (final key in keys) {
        for (final value in values[_normalize(key)] ?? const <dynamic>[]) {
          if (value is Map) {
            final map = Map<String, dynamic>.from(value);
            final lat = _mapNumber(map, const [
              'lat',
              'latitude',
              'delivery_location_lat',
            ]);
            final lng = _mapNumber(map, const [
              'lng',
              'lon',
              'longitude',
              'delivery_location_lng',
            ]);
            if (_validCoordinates(lat, lng)) return (lat, lng);
          }
          if (value is List && value.length >= 2) {
            final first = _toDouble(value[0]);
            final second = _toDouble(value[1]);
            if (_validCoordinates(first, second)) return (first, second);
            if (_validCoordinates(second, first)) return (second, first);
          }
          if (value is String) {
            final matches = RegExp(r'-?\d+(?:\.\d+)?')
                .allMatches(value)
                .map((match) => double.tryParse(match.group(0)!))
                .whereType<double>()
                .toList();
            if (matches.length >= 2) {
              if (_validCoordinates(matches[0], matches[1])) {
                return (matches[0], matches[1]);
              }
              if (_validCoordinates(matches[1], matches[0])) {
                return (matches[1], matches[0]);
              }
            }
          }
        }
      }
      return (null, null);
    }

    String textAtPath(List<String> path) {
      dynamic walk(dynamic node, int index) {
        if (index >= path.length) return node;
        if (node is List) {
          for (final item in node) {
            final result = walk(item, index);
            if (result != null) return result;
          }
          return null;
        }
        if (node is! Map) return null;
        final wanted = _normalize(path[index]);
        for (final entry in node.entries) {
          if (_normalize(entry.key.toString()) == wanted) {
            final result = walk(entry.value, index + 1);
            if (result != null) return result;
          }
        }
        return null;
      }

      final value = walk(json, 0);
      if (value == null || value is Map || value is List) return '';
      final result = value.toString().trim();
      if (result.isEmpty || result.toLowerCase() == 'null') return '';
      return result;
    }

    String firstAtPaths(List<List<String>> paths) {
      for (final path in paths) {
        final result = textAtPath(path);
        if (result.isNotEmpty) return result;
      }
      return '';
    }

    String heuristicStoreName() {
      final candidates = <({int score, String value})>[];

      void walk(dynamic node, List<String> path) {
        if (node is Map) {
          for (final entry in node.entries) {
            walk(entry.value, [...path, _normalize(entry.key.toString())]);
          }
          return;
        }
        if (node is List) {
          for (final item in node) {
            walk(item, path);
          }
          return;
        }
        if (node == null || path.isEmpty) return;

        final value = node.toString().trim();
        if (value.length < 2 || value.length > 120) return;
        if (value.toLowerCase() == 'null') return;
        if (RegExp(r'^[-+() 0-9.]+$').hasMatch(value)) return;
        if (value.contains('@') || value.startsWith('http')) return;

        final joined = path.join('.');
        final leaf = path.last;
        final isNameField = leaf.contains('name') ||
            leaf.contains('title') ||
            leaf.contains('label') ||
            leaf.contains('business') ||
            leaf.contains('company') ||
            leaf.contains('commercial');
        if (!isNameField) return;

        var score = 0;
        if (joined.contains('merchant') || joined.contains('store')) {
          score += 120;
        }
        if (joined.contains('shop') || joined.contains('seller')) score += 110;
        if (joined.contains('vendor') || joined.contains('retailer')) {
          score += 100;
        }
        if (joined.contains('shipper') || joined.contains('sender')) {
          score += 85;
        }
        if (joined.contains('client') || joined.contains('brand')) score += 75;
        if (joined.contains('company') || joined.contains('business')) {
          score += 50;
        }
        if (leaf.contains('display') || leaf.contains('full')) score += 15;

        // Recipient/customer branches describe the delivery customer, not the
        // originating store. Avoid mislabeling them as the merchant.
        if (joined.contains('recipient') ||
            joined.contains('consignee') ||
            joined.contains('deliverylocation') ||
            joined.contains('customer')) {
          score -= 140;
        }
        if (score > 0) candidates.add((score: score, value: value));
      }

      walk(json, const []);
      if (candidates.isEmpty) return '';
      candidates.sort((a, b) => b.score.compareTo(a.score));
      return candidates.first.value;
    }

    final reference = text(const [
      // Exact keys observed in the SLS Driver task model.
      'order_awb',
      'orderAwb',
      'outgoing_shipper_tracking_number',
      'incoming_tracking_no',
      'customer_reference_number',
      // Compatibility fallbacks.
      'awb',
      'awb_no',
      'awbNumber',
      'tracking_number',
      'trackingNumber',
      'reference_number',
      'referenceNumber',
      'shipment_number',
      'shipmentNumber',
      'shipment_no',
      'waybill_number',
      'waybillNumber',
      'waybill_no',
      'order_number',
      'orderNumber',
      'order_no',
      'barcode',
      'code',
    ]);

    // Store/merchant data is resolved by explicit paths first. The API often
    // contains several unrelated `name` or `company_name` fields, so a global
    // recursive lookup can accidentally select the customer or warehouse.
    var storeName = firstAtPaths(const [
      ['order', 'collection_location_name'],
      ['order', 'collection_location', 'name'],
      ['order', 'collectionLocationName'],
      ['merchant_name'],
      ['merchantName'],
      ['store_name'],
      ['storeName'],
      ['shop_name'],
      ['shopName'],
      ['seller_name'],
      ['sellerName'],
      ['vendor_name'],
      ['vendorName'],
      ['shipper_name'],
      ['shipperName'],
      ['sender_company_name'],
      ['senderCompanyName'],
      ['merchant_company_name'],
      ['merchantCompanyName'],
      ['client_store_name'],
      ['clientStoreName'],
      ['client_business_name'],
      ['clientBusinessName'],
      ['order_client_name'],
      ['orderClientName'],
      ['client_name'],
      ['clientName'],
      ['account_name'],
      ['accountName'],
      ['outgoing_shipper_name'],
      ['outgoingShipperName'],
      ['outgoing_shipper_company_name'],
      ['outgoingShipperCompanyName'],
      ['merchant', 'display_name'],
      ['merchant', 'displayName'],
      ['merchant', 'full_name'],
      ['merchant', 'fullName'],
      ['merchant', 'business_name'],
      ['merchant', 'company_name'],
      ['merchant', 'name'],
      ['store', 'display_name'],
      ['store', 'full_name'],
      ['store', 'name'],
      ['shop', 'name'],
      ['seller', 'name'],
      ['vendor', 'name'],
      ['shipper', 'company_name'],
      ['shipper', 'name'],
      ['sender', 'company_name'],
      ['sender', 'business_name'],
      ['sender', 'name'],
      ['client', 'store_name'],
      ['client', 'business_name'],
      ['client', 'company_name'],
      ['client', 'name'],
      ['order', 'merchant_name'],
      ['order', 'store_name'],
      ['order', 'sender_company_name'],
      ['order', 'merchant', 'display_name'],
      ['order', 'merchant', 'full_name'],
      ['order', 'merchant', 'name'],
      ['order', 'store', 'name'],
      ['order', 'seller', 'name'],
      ['order', 'sender', 'company_name'],
      ['order', 'sender', 'name'],
      ['order', 'client', 'business_name'],
      ['order', 'client', 'name'],
      ['task', 'merchant_name'],
      ['task', 'store_name'],
      ['task', 'sender_company_name'],
      ['task', 'client', 'store_name'],
      ['task', 'client', 'business_name'],
      ['task', 'client', 'company_name'],
      ['task', 'merchant', 'name'],
      ['task', 'store', 'name'],
      ['task', 'sender', 'company_name'],
      ['task', 'customer', 'store_name'],
      ['task', 'customer', 'business_name'],
      ['task', 'customer', 'company_name'],
      ['orders', 'merchant_name'],
      ['orders', 'store_name'],
      ['orders', 'sender_company_name'],
      ['orders', 'merchant', 'display_name'],
      ['orders', 'merchant', 'full_name'],
      ['orders', 'merchant', 'name'],
      ['orders', 'store', 'name'],
      ['orders', 'seller', 'name'],
      ['orders', 'sender', 'company_name'],
      ['orders', 'sender', 'name'],
      ['orders', 'client', 'business_name'],
      ['orders', 'client', 'name'],
      ['outgoing_shipper', 'company_name'],
      ['outgoing_shipper', 'name'],
      ['pickup_location', 'store_name'],
      ['pickup_location', 'business_name'],
      ['pickup_location', 'name'],
      ['origin', 'company_name'],
      ['origin', 'name'],
    ]);

    // Prefer the path-aware heuristic before the recursive compatibility
    // fallback. Generic keys such as `company_name` may belong to the
    // recipient/customer and must not override a merchant value.
    if (storeName.isEmpty) {
      storeName = heuristicStoreName();
    }

    // Compatibility fallback for less structured API variants. Specific
    // merchant/store keys remain ahead of generic sender/company keys.
    if (storeName.isEmpty) {
      storeName = text(const [
        'merchant_name',
        'merchantName',
        'merchant_title',
        'merchantTitle',
        'merchant_display_name',
        'merchantDisplayName',
        'merchant_company_name',
        'merchantCompanyName',
        'store_name',
        'storeName',
        'shop_name',
        'shopName',
        'store_title',
        'storeTitle',
        'vendor_name',
        'vendorName',
        'seller_name',
        'sellerName',
        'client_store_name',
        'clientStoreName',
        'client_business_name',
        'clientBusinessName',
        'order_client_name',
        'orderClientName',
        'client_name',
        'clientName',
        'account_name',
        'accountName',
        'outgoing_shipper_name',
        'outgoingShipperName',
        'outgoing_shipper_company_name',
        'outgoingShipperCompanyName',
        'shipper_name',
        'shipperName',
        'sender_company_name',
        'senderCompanyName',
        'sender_name',
        'senderName',
        'business_name',
        'businessName',
        'commercial_name',
        'commercialName',
        'company_name',
        'companyName',
        'merchant',
        'store',
        'shop',
        'seller',
      ]);
    }
    if (storeName.isEmpty) {
      storeName = textInsideParents(
        const [
          'merchant',
          'order_merchant',
          'orderMerchant',
          'store',
          'shop',
          'vendor',
          'seller',
          'shipper',
          'outgoing_shipper',
          'outgoingShipper',
          'client',
          'account',
          'sender',
          'origin',
          'pickup_location',
          'pickupLocation',
        ],
        const [
          'display_name',
          'displayName',
          'full_name',
          'fullName',
          'store_name',
          'storeName',
          'merchant_name',
          'merchantName',
          'business_name',
          'businessName',
          'company_name',
          'companyName',
          'commercial_name',
          'commercialName',
          'title',
          'label',
          'name',
        ],
      );
    }

    final addressParts = <String>[
      text(const [
        'delivery_location_address1',
        'deliveryLocationAddress1',
        'delivery_address',
        'deliveryAddress',
        'task_address',
        'taskAddress',
        'customer_address',
        'customerAddress',
        'consignee_address',
        'consigneeAddress',
        'full_address',
        'fullAddress',
        'address',
      ]),
      text(const [
        'delivery_location_address2',
        'deliveryLocationAddress2',
        'address2',
      ]),
      text(const [
        'delivery_location_city',
        'deliveryLocationCity',
        'delivery_area_name',
        'city',
      ]),
    ];
    final uniqueAddressParts = <String>[];
    for (final part in addressParts) {
      final normalized = part.trim();
      if (normalized.isNotEmpty && !uniqueAddressParts.contains(normalized)) {
        uniqueAddressParts.add(normalized);
      }
    }

    var latitude = number(const [
      'delivery_location_lat',
      'deliveryLocationLat',
      'delivery_latitude',
      'deliveryLatitude',
      'customer_lat',
      'customerLat',
      'customer_latitude',
      'customerLatitude',
      'destination_latitude',
      'destinationLatitude',
      'location_latitude',
      'locationLatitude',
      'latitude',
      'lat',
    ]);
    var longitude = number(const [
      'delivery_location_lng',
      'deliveryLocationLng',
      'delivery_longitude',
      'deliveryLongitude',
      'customer_lng',
      'customerLng',
      'customer_longitude',
      'customerLongitude',
      'destination_longitude',
      'destinationLongitude',
      'location_longitude',
      'locationLongitude',
      'longitude',
      'lng',
      'lon',
      'long',
    ]);
    if (!_validCoordinates(latitude, longitude)) {
      final combined = coordinatesFromCombinedValue();
      latitude = combined.$1;
      longitude = combined.$2;
    }
    if (!_validCoordinates(latitude, longitude)) {
      latitude = null;
      longitude = null;
    }

    final cod = number(const [
      'cod_amount',
      'codAmount',
      'cod_cost',
      'codCost',
      'cash_on_delivery_amount',
      'cashOnDeliveryAmount',
      'collectable_amount',
      'collectableAmount',
      'amount_to_collect',
      'amountToCollect',
      'due_amount',
      'dueAmount',
    ]);
    final codFlag = boolean(const ['is_cod', 'isCod']);
    final codPaymentMethod = text(const [
      'cod_payment_method',
      'codPaymentMethod',
      'payment_method',
      'paymentMethod',
    ]);
    final paymentText = text(const [
      'payment_type',
      'paymentType',
      'payment_method',
      'paymentMethod',
      'payment_status',
      'paymentStatus',
      'english_payment_text',
      'arabic_payment_text',
      'is_cod',
      'isCod',
      'cod',
      'paid',
    ]).toLowerCase();

    PaymentKind paymentKind = PaymentKind.unknown;
    if (codFlag == true ||
        (cod ?? 0) > 0 ||
        _containsAny(paymentText, const [
          'cod',
          'cash',
          'collect',
          'دفع عند الاستلام',
          'عند الاستلام',
          'كاش',
          'نقد',
        ])) {
      paymentKind = PaymentKind.cashOnDelivery;
    } else if (codFlag == false ||
        _containsAny(paymentText, const [
          'paid',
          'prepaid',
          'online',
          'card',
          'مدفوع',
          'مسبق',
        ])) {
      paymentKind = PaymentKind.prepaid;
    } else if (cod != null && cod <= 0) {
      paymentKind = PaymentKind.prepaid;
    }

    return TaskItem(
      id: text(const [
        'order_id',
        'orderId',
        'task_id',
        'taskId',
        'shipment_id',
        'shipmentId',
        'id',
      ]),
      referenceNumber: reference,
      storeName: storeName,
      customerName: text(const [
        'customer_name',
        'customerName',
        'delivery_location_contact',
        'deliveryLocationContact',
        'consignee_name',
        'consigneeName',
        'recipient_name',
        'recipientName',
        'contact_name',
        'contactName',
        'delivery_location_name',
        'name',
      ]),
      customerPhone: text(const [
        'customer_phone_with_code_multiple',
        'customerPhoneWithCodeMultiple',
        'customer_phone',
        'customerPhone',
        'delivery_phone',
        'deliveryPhone',
        'delivery_location_contact_phone',
        'consignee_phone',
        'consigneePhone',
        'recipient_phone',
        'recipientPhone',
        'mobile',
        'phone',
      ]),
      address: uniqueAddressParts.join('، '),
      latitude: latitude,
      longitude: longitude,
      statusCode: text(const [
        'order_status_code',
        'orderStatusCode',
        'status_code',
        'statusCode',
        'status',
      ]),
      statusLabel: text(const [
        'order_status_label_code',
        'orderStatusLabelCode',
        'status_label_3pl',
        'statusLabel3pl',
        'status_label',
        'statusLabel',
        'status_name',
        'statusName',
      ]),
      taskType: text(const ['task_type', 'taskType', 'task_name', 'taskName']),
      orderType: text(const ['order_type', 'orderType']),
      paymentKind: paymentKind,
      codAmount: cod,
      codPaymentMethod: codPaymentMethod,
      statusId:
          number(const ['status_id', 'order_status_id', 'current_status']),
      statusLabelId: number(
        const [
          'status_label_id',
          'order_status_label_id',
          'current_status_label'
        ],
      ),
      orderTypeId: number(
        const ['order_type_id', 'current_order_type', 'order_type_id'],
      ),
      isRvp: boolean(const ['is_rvp', 'current_is_rvp']) == true ? 1 : 0,
      raw: Map<String, dynamic>.from(json),
    );
  }

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _containsAny(String value, List<String> candidates) =>
      candidates.any(value.contains);

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static double? _mapNumber(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      for (final entry in map.entries) {
        if (_normalize(entry.key) == _normalize(key)) {
          final result = _toDouble(entry.value);
          if (result != null) return result;
        }
      }
    }
    return null;
  }

  static bool _validCoordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    if (latitude.abs() < 0.000001 && longitude.abs() < 0.000001) return false;
    return true;
  }
}
