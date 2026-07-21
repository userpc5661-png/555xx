import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalContactData {
  final String status; // 'contacted', 'not_contacted'
  final String? type; // 'call', 'whatsapp'
  final DateTime? timestamp;
  final DateTime? reminderAt;
  final int missingCount; // Used for retention logic

  LocalContactData({
    required this.status,
    this.type,
    this.timestamp,
    this.reminderAt,
    this.missingCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'type': type,
        'timestamp': timestamp?.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'missingCount': missingCount,
      };

  factory LocalContactData.fromJson(Map<String, dynamic> json) =>
      LocalContactData(
        status: json['status'] ?? 'not_contacted',
        type: json['type'],
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'])
            : null,
        reminderAt: json['reminderAt'] != null
            ? DateTime.tryParse(json['reminderAt'])
            : null,
        missingCount: json['missingCount'] ?? 0,
      );

  LocalContactData copyWith({
    String? status,
    String? type,
    DateTime? timestamp,
    DateTime? reminderAt,
    int? missingCount,
    bool clearReminder = false,
  }) =>
      LocalContactData(
        status: status ?? this.status,
        type: type ?? this.type,
        timestamp: timestamp ?? this.timestamp,
        reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
        missingCount: missingCount ?? this.missingCount,
      );
}

class LocalContactStore {
  static const _key = 'local_contact_records_v2';
  static const _storage = FlutterSecureStorage();

  LocalContactStore._();
  static final instance = LocalContactStore._();

  Future<Map<String, LocalContactData>> getAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    try {
      final Map<String, dynamic> map = jsonDecode(raw);
      return map
          .map((key, value) => MapEntry(key, LocalContactData.fromJson(value)));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String storageKey, LocalContactData data) async {
    final records = await getAll();
    records[storageKey] = data;
    await _saveAll(records);
  }

  Future<void> bulkSave(Map<String, LocalContactData> records) async {
    await _saveAll(records);
  }

  Future<void> remove(String storageKey) async {
    final records = await getAll();
    records.remove(storageKey);
    await _saveAll(records);
  }

  Future<void> _saveAll(Map<String, LocalContactData> records) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(
        records.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }

  /// Retention logic:
  /// - Reset missingCount for activeKeys.
  /// - Increment missingCount for absent keys; delete if >= 3.
  /// - Immediately delete for deliveredKeys.
  Future<void> cleanup(
      List<String> activeKeys, List<String> deliveredKeys) async {
    final records = await getAll();
    bool changed = false;

    // Remove delivered immediately
    for (final key in deliveredKeys) {
      if (records.containsKey(key)) {
        records.remove(key);
        changed = true;
      }
    }

    final toRemove = <String>[];
    final keys = records.keys.toList();

    for (final key in keys) {
      if (activeKeys.contains(key)) {
        if (records[key]!.missingCount != 0) {
          records[key] = records[key]!.copyWith(missingCount: 0);
          changed = true;
        }
      } else {
        // Not in active list and not delivered? It might be temporarily missing.
        final currentMissing = records[key]!.missingCount + 1;
        if (currentMissing >= 3) {
          toRemove.add(key);
        } else {
          records[key] = records[key]!.copyWith(missingCount: currentMissing);
          changed = true;
        }
      }
    }

    if (toRemove.isNotEmpty) {
      for (final key in toRemove) {
        records.remove(key);
      }
      changed = true;
    }

    if (changed) {
      await _saveAll(records);
    }
  }
}
