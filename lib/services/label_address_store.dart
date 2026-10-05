import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/task_item.dart';
import 'account_store.dart';
import 'location_correction_service.dart';

/// The customer's National Address read from the shipment label, per
/// shipment. SLS often sends a wrong, shared address; the label is right.
class LabelAddressStore {
  LabelAddressStore._();

  static final instance = LabelAddressStore._();
  static const _storage = FlutterSecureStorage();

  /// shipment key -> short National Address from the label.
  final ValueNotifier<Map<String, String>> values =
      ValueNotifier<Map<String, String>>(const {});
  bool _loaded = false;

  String get _key =>
      'label_na_v1_${AccountStore.currentAccountId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        values.value = Map.unmodifiable(
          decoded.map((k, v) => MapEntry('$k', '$v')),
        );
      }
    } catch (_) {}
  }

  String? forTask(TaskItem task) =>
      values.value[LocationCorrectionService.shipmentKey(task)];

  Future<void> save(TaskItem task, String shortAddress) async {
    await load();
    final next = {
      ...values.value,
      LocationCorrectionService.shipmentKey(task): shortAddress,
    };
    values.value = Map.unmodifiable(next);
    await _storage.write(key: _key, value: jsonEncode(next));
  }
}
