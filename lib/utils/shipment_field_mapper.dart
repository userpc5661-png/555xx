class ShipmentFieldMapper {
  const ShipmentFieldMapper._();

  static String firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      return text;
    }
    return '';
  }

  /// Recursively searches for the first occurring value from [keys].
  /// [excludePaths] allows skipping branches (e.g., skip "customer" for store names).
  static dynamic _findRawValue(dynamic node, List<String> keys, {List<String>? excludePaths}) {
    final wanted = keys.map((k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toSet();
    final excluded = excludePaths?.map((k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toSet() ?? {};

    dynamic walk(dynamic value, String currentPath) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (excluded.contains(key)) continue;
          if (wanted.contains(key) && entry.value != null) {
            final val = entry.value.toString().trim();
            if (val.isNotEmpty && val.toLowerCase() != 'null') return entry.value;
          }
        }
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (excluded.contains(key)) continue;
          final found = walk(entry.value, key);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final item in value) {
          final found = walk(item, currentPath);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(node, '');
  }

  /// A return (reverse pickup): the driver collects the parcel from the
  /// customer, so the customer is in the `collection_location_*` fields and
  /// the merchant is in `delivery_location_*` (the opposite of a normal
  /// delivery). SLS marks it with order_type "reverse".
  static bool isReverse(Map<String, dynamic> json) {
    final type = _findRawValue(json, ['order_type'])?.toString().trim().toLowerCase() ?? '';
    if (type == 'reverse' || type == 'return' || type == 'rvp') return true;
    final rvp = _findRawValue(json, ['is_rvp', 'current_is_rvp'])?.toString().trim().toLowerCase();
    return rvp == '1' || rvp == 'true';
  }

  /// For a return: the customer the driver visits.
  static String reverseCustomerName(Map<String, dynamic> json) => firstNonEmpty([
        _findRawValue(json, ['collection_location_contact']),
        _findRawValue(json, ['collection_location_name']),
      ]);

  static String reverseCustomerPhone(Map<String, dynamic> json) =>
      firstNonEmpty([_findRawValue(json, ['collection_phone'])]);

  /// For a return: the merchant the parcel goes back to.
  static String reverseMerchantName(Map<String, dynamic> json) {
    final customer = json['customer'];
    return firstNonEmpty([
      _findRawValue(json, ['delivery_location_name']),
      _findRawValue(json, ['delivery_location_contact']),
      customer is Map ? customer['name'] : null,
      json['requested_by'],
    ]);
  }

  static String reverseCustomerAddress(Map<String, dynamic> json) {
    final parts = <String>[];
    for (final key in const [
      'collection_location_address1',
      'collection_location_address2',
      'collection_location_area',
      'collection_location_city',
    ]) {
      final text = _findRawValue(json, [key])?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      final normalized = _normalize(text);
      if (parts.any((p) => _normalize(p).contains(normalized))) continue;
      parts.add(text);
    }
    return parts.join('، ');
  }

  static String recipientName(Map<String, dynamic> json) {
    return firstNonEmpty([
      json['delivery_location_name'],
      json['delivery_location_contact'],
      json['consignee_name'],
      json['recipient_name'],
      json['customer_name'],
      _findRawValue(json, ['delivery_location_name', 'delivery_location_contact', 'consignee_name', 'recipient_name', 'customer_name']),
    ]);
  }

  static String recipientPhone(Map<String, dynamic> json) {
    return firstNonEmpty([
      json['delivery_phone'],
      json['consignee_phone'],
      json['recipient_phone'],
      _findRawValue(json, ['delivery_phone', 'consignee_phone', 'recipient_phone', 'mobile', 'phone']),
    ]);
  }

  static String merchantName(Map<String, dynamic> json) {
    // 1. Top-level simple fields (highest priority).
    final base = firstNonEmpty([
      json['collection_location_contact'],
      json['collection_location_name'],
      json['requested_by'],
      json['store_name'],
      json['merchant_name'],
    ]);
    if (base.isNotEmpty) return base;

    // 1b. Same top-level fields searched recursively (e.g., nested inside 'order').
    const exclude = ['customer', 'recipient', 'consignee', 'delivery'];
    final baseNested = _findRawValue(json, ['collection_location_contact', 'collection_location_name', 'requested_by', 'store_name', 'merchant_name'], excludePaths: exclude)?.toString() ?? '';
    if (baseNested.isNotEmpty) return baseNested;

    if (json['merchant'] is Map) {
      final m = json['merchant'] as Map<String, dynamic>;
      final val = firstNonEmpty([m['name'], m['full_name'], m['business_name'], m['company_name'], m['store_name'], m['merchant_name']]);
      if (val.isNotEmpty) return val;
    }

    if (json['merchant_details'] is Map) {
      final md = json['merchant_details'] as Map<String, dynamic>;
      final val = firstNonEmpty([md['official_display_title'], md['display_name'], md['title'], md['name'], md['full_name']]);
      if (val.isNotEmpty) return val;
    }

    final senderVal = firstNonEmpty([json['sender_company_name'], json['sender_name'], json['sender_business_name']]);
    if (senderVal.isNotEmpty) return senderVal;

    if (json['order'] is Map) {
      final order = json['order'] as Map<String, dynamic>;
      if (order['client'] is Map) {
        final client = order['client'] as Map<String, dynamic>;
        final val = firstNonEmpty([client['business_name'], client['company_name'], client['name']]);
        if (val.isNotEmpty) return val;
      }
    }

    const genericKeys = ['store_name', 'merchant_name', 'name', 'full_name', 'business_name', 'company_name', 'official_display_title', 'display_name', 'title'];
    return _findRawValue(json, genericKeys, excludePaths: exclude)?.toString() ?? '';
  }

  static List<double?> extractCoordinates(Map<String, dynamic> json) {
    // Search for delivery_lat_long at any nesting level.
    final combined = _findRawValue(json, ['delivery_lat_long']);
    if (combined is String && combined.contains(',')) {
      final parts = combined.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) return [lat, lng];
      }
    }
    return [null, null];
  }

  static String shipmentNumber(Map<String, dynamic> json) {
    // Priority 1: human-readable AWB references (searched recursively, separately to maintain order)
    final awb = firstNonEmpty([
      json['order_awb'],
      json['awb'],
      _findRawValue(json, ['order_awb', 'awb'])?.toString(),
    ]);
    if (awb.isNotEmpty) return awb;

    // Priority 2: numeric/fallback IDs
    return firstNonEmpty([
      json['order_id'],
      json['outgoing_tn'],
      json['reference_no'],
      _findRawValue(json, ['order_id', 'outgoing_tn', 'reference_no'])?.toString(),
    ]);
  }

  static String shipmentStatus(Map<String, dynamic> json) {
    return firstNonEmpty([
      json['status_label'],
      json['status'],
      _findRawValue(json, ['status_label', 'status', 'order_status_label']),
    ]);
  }

  static String recipientAddress(Map<String, dynamic> json) {
    final parts = <String>[];
    final addr1 = _findRawValue(json, ['delivery_location_address1', 'address1', 'address']);
    final addr2 = _findRawValue(json, ['delivery_location_address2', 'address2']);
    final area = _findRawValue(json, ['delivery_area_name', 'area_name', 'district']);
    final city = _findRawValue(json, ['delivery_location_city', 'city']);
    final zip = _findRawValue(json, ['delivery_postal_code', 'postal_code', 'zip_code']);

    for (final candidate in [addr1, addr2, area, city, zip]) {
      if (candidate == null) continue;
      final text = candidate.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      final normalizedText = _normalize(text);
      final isDuplicate = parts.any((existing) {
        final normalizedExisting = _normalize(existing);
        return normalizedExisting == normalizedText || normalizedExisting.contains(normalizedText);
      });
      if (!isDuplicate) parts.add(text);
    }

    return parts.join('، ');
  }

  static double codAmount(Map<String, dynamic> json) {
    final value = _findRawValue(json, ['cod_amount', 'amount_to_collect', 'collect_amount', 'collectable_amount']);
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim().replaceAll(',', '')) ?? 0;
  }

  static bool isCod(Map<String, dynamic> json) {
    final value = _findRawValue(json, ['is_cod']);
    final enabled = value == true ||
        value == 1 ||
        value?.toString().trim().toLowerCase() == '1' ||
        value?.toString().trim().toLowerCase() == 'true';
    return enabled || codAmount(json) > 0;
  }

  static String formatAmount(double value) {
    if (!value.isFinite) return '0';
    if (value == value.truncateToDouble()) return value.toInt().toString();
    var result = value.toStringAsFixed(2);
    result = result.replaceFirst(RegExp(r'0+$'), '');
    result = result.replaceFirst(RegExp(r'\.$'), '');
    return result;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll('،', ',');
  }
}
