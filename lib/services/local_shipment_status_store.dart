import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'account_store.dart';

class LocalShipmentStatus {
  final String statusKey; // 'customer_cancelled', 'rescheduled', 'wrong_location', 'wrong_phone', 'no_answer', 'other'
  final String label;
  final DateTime timestamp;
  final String? note;

  const LocalShipmentStatus({
    required this.statusKey,
    required this.label,
    required this.timestamp,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'statusKey': statusKey,
        'label': label,
        'timestamp': timestamp.toIso8601String(),
        'note': note,
      };

  factory LocalShipmentStatus.fromJson(Map<String, dynamic> json) =>
      LocalShipmentStatus(
        statusKey: (json['statusKey'] ?? json['status'] ?? 'customer_cancelled').toString(),
        label: (json['label'] ?? '').toString(),
        timestamp: json['timestamp'] != null
            ? (DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now())
            : DateTime.now(),
        note: json['note']?.toString(),
      );

  static const Map<String, String> defaultLabels = {
    'customer_cancelled': 'العميل ألغى الطلبية',
    'rescheduled': 'العميل أعاد الجدولة',
    'wrong_location': 'الموقع غير صحيح',
    'wrong_phone': 'رقم الهاتف خاطئ',
    'no_answer': 'العميل لم يجب',
  };

  static String defaultLabelFor(String key) =>
      defaultLabels[key] ?? 'حالة مستبعدة محلياً';
}

class LocalShipmentStatusStore {
  static String get _key =>
      'local_shipment_statuses_v1_${AccountStore.currentAccountId}';
  static const _storage = FlutterSecureStorage();

  LocalShipmentStatusStore._();
  static final instance = LocalShipmentStatusStore._();

  Future<Map<String, LocalShipmentStatus>> getAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final Map<String, dynamic> map = jsonDecode(raw);
      return map.map((key, value) => MapEntry(
            key,
            LocalShipmentStatus.fromJson(Map<String, dynamic>.from(value as Map)),
          ));
    } catch (_) {
      return {};
    }
  }

  Future<LocalShipmentStatus?> get(String storageKey) async {
    final all = await getAll();
    return all[storageKey];
  }

  Future<void> setStatus(
    String storageKey,
    String statusKey, {
    String? label,
    String? note,
  }) async {
    final all = await getAll();
    all[storageKey] = LocalShipmentStatus(
      statusKey: statusKey,
      label: label ?? LocalShipmentStatus.defaultLabelFor(statusKey),
      timestamp: DateTime.now(),
      note: note,
    );
    await _saveAll(all);
  }

  Future<void> removeStatus(String storageKey) async {
    final all = await getAll();
    if (all.containsKey(storageKey)) {
      all.remove(storageKey);
      await _saveAll(all);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }

  Future<void> _saveAll(Map<String, LocalShipmentStatus> records) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(
        records.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }

  /// Retention & cleanup when tasks complete
  Future<void> cleanup(List<String> deliveredKeys) async {
    final records = await getAll();
    bool changed = false;
    for (final key in deliveredKeys) {
      if (records.containsKey(key)) {
        records.remove(key);
        changed = true;
      }
    }
    if (changed) {
      await _saveAll(records);
    }
  }
}
