import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/task_item.dart';
import 'account_store.dart';
import 'location_correction_service.dart';

/// The customer's National Address read from the shipment label (and its
/// location), per shipment. SLS often sends a wrong, shared address; the
/// label is right. Saved under every number the shipment is known by
/// (barcode, order_id, outgoing_tn, reference_no…), because the scanner and
/// the task list do not always use the same one.
class LabelAddressStore {
  LabelAddressStore._();

  static final instance = LabelAddressStore._();
  static const _storage = FlutterSecureStorage();

  /// id -> short National Address from the label.
  final ValueNotifier<Map<String, String>> values =
      ValueNotifier<Map<String, String>>(const {});
  Map<String, String> _locations = {}; // id -> "lat,lng"
  Set<String> _applied = {}; // shipment keys whose location was applied
  bool _loaded = false;

  String get _key =>
      'label_na_v2_${AccountStore.currentAccountId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  static String normalizeId(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static Set<String> idsOfTask(TaskItem task) => {
        LocationCorrectionService.shipmentKey(task),
        task.realAwb,
        task.displayReference,
        task.referenceNumber,
        task.id,
      }.map(normalizeId).where((id) => id.length >= 5).toSet();

  static Set<String> idsOfOrder(Map<String, dynamic> order, String code) => {
        code,
        for (final key in const [
          'order_id',
          'order_awb',
          'outgoing_tn',
          'reference_no',
          'awb',
        ])
          if (order[key] != null) '${order[key]}',
      }.map(normalizeId).where((id) => id.length >= 5).toSet();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      Map<String, String> strings(Object? value) => value is Map
          ? value.map((k, v) => MapEntry('$k', '$v'))
          : <String, String>{};
      values.value = Map.unmodifiable(strings(decoded['na']));
      _locations = strings(decoded['loc']);
      final applied = decoded['applied'];
      _applied = applied is List ? applied.map((e) => '$e').toSet() : {};
    } catch (_) {}
  }

  Future<void> _persist() => _storage.write(
        key: _key,
        value: jsonEncode({
          'na': values.value,
          'loc': _locations,
          'applied': _applied.toList(),
        }),
      );

  String? _first(Iterable<String> ids, Map<String, String> map) {
    for (final id in ids) {
      final value = map[id];
      if (value != null) return value;
    }
    return null;
  }

  String? forTask(TaskItem task) => _first(idsOfTask(task), values.value);

  CorrectedLocation? locationForTask(TaskItem task) {
    final text = _first(idsOfTask(task), _locations);
    if (text == null) return null;
    final parts = text.split(',');
    final lat = double.tryParse(parts.first);
    final lng = parts.length > 1 ? double.tryParse(parts[1]) : null;
    return lat == null || lng == null ? null : CorrectedLocation(lat, lng);
  }

  Future<void> saveForIds(
    Set<String> ids,
    String shortAddress, {
    CorrectedLocation? location,
  }) async {
    await load();
    final na = {...values.value};
    for (final id in ids) {
      na[id] = shortAddress;
      if (location != null) {
        _locations[id] = '${location.latitude},${location.longitude}';
      } else {
        _locations.remove(id);
      }
    }
    values.value = Map.unmodifiable(na);
    await _persist();
  }

  Future<void> save(
    TaskItem task,
    String shortAddress, {
    CorrectedLocation? location,
  }) async {
    await saveForIds(idsOfTask(task), shortAddress, location: location);
    if (location != null) {
      _applied.add(LocationCorrectionService.shipmentKey(task));
      await _persist();
    }
  }

  /// Uses label locations read while scanning (before the shipment was in
  /// the task list) as the customer's location, once per shipment, unless
  /// the driver already set one.
  Future<void> applyToTasks(List<TaskItem> tasks) async {
    await load();
    var changed = false;
    for (final task in tasks) {
      final key = LocationCorrectionService.shipmentKey(task);
      if (_applied.contains(key)) continue;
      final location = locationForTask(task);
      if (location == null) continue;
      _applied.add(key);
      changed = true;
      if (await LocationCorrectionService.load(task) != null) continue;
      await LocationCorrectionService.save(task, location);
    }
    if (changed) await _persist();
  }
}
