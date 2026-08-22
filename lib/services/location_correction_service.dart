import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/task_item.dart';
import 'account_store.dart';
import 'developer_diagnostics_service.dart';

class CorrectedLocation {
  final double latitude;
  final double longitude;
  const CorrectedLocation(this.latitude, this.longitude);

  Map<String, dynamic> toJson() => {'lat': latitude, 'lng': longitude};
  factory CorrectedLocation.fromJson(Map<String, dynamic> json) =>
      CorrectedLocation(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      );
}

class LocationCorrectionService {
  LocationCorrectionService._();

  static const _storage = FlutterSecureStorage();
  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _key(TaskItem task) {
    final shipmentKey = task.realAwb.trim().isNotEmpty
        ? task.realAwb.trim()
        : task.displayReference.trim();
    return 'shipment_location_v2_${_safe(AccountStore.currentAccountId)}_${_safe(shipmentKey)}';
  }

  // Kept for a transparent one-time migration of locations saved by older
  // releases. Removing it would make existing driver corrections disappear.
  static String _legacyKey(TaskItem task) =>
      'shipment_location_${_safe(task.displayReference)}';

  static Future<CorrectedLocation?> load(TaskItem task) async {
    var raw = await _storage.read(key: _key(task));
    final loadedFromLegacy = raw == null;
    raw ??= await _storage.read(key: _legacyKey(task));
    if (raw == null) return null;
    try {
      final value = CorrectedLocation.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (loadedFromLegacy) {
        await save(task, value);
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  static Future<CorrectedLocation?> effectiveLocation(TaskItem task) async {
    final corrected = await load(task);
    if (corrected != null) return corrected;
    if (task.latitude == null || task.longitude == null) return null;
    return CorrectedLocation(task.latitude!, task.longitude!);
  }

  static Future<void> save(TaskItem task, CorrectedLocation value) async {
    await _storage.write(key: _key(task), value: jsonEncode(value.toJson()));
    DeveloperDiagnosticsService.instance.setContext(
      'Local customer location',
      '${task.displayReference}: ${value.latitude}, ${value.longitude}',
    );
  }

  static Future<void> restore(TaskItem task) async {
    await _storage.delete(key: _key(task));
    await _storage.delete(key: _legacyKey(task));
  }

  static Future<CorrectedLocation?> parse(String input, {Dio? client}) async {
    final text = input.trim();
    if (text.isEmpty) return null;
    final direct = _extract(text);
    if (direct != null) return direct;
    final uri = Uri.tryParse(text);
    if (uri == null || !_isSupportedMapsUri(uri)) return null;
    try {
      final dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              followRedirects: true,
              maxRedirects: 10,
              validateStatus: (status) => status != null && status < 500,
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Mobile Safari/537.36',
              },
            ),
          );
      final response = await dio.getUri<dynamic>(
        uri,
        options: Options(responseType: ResponseType.plain),
      );
      final finalUrl = response.realUri.toString();
      return _extract(finalUrl) ??
          _extract(response.headers.value('location') ?? '') ??
          _extract(response.data?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  static bool _isSupportedMapsUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'maps.app.goo.gl' ||
        host == 'goo.gl' ||
        host == 'maps.google.com' ||
        host == 'www.google.com' ||
        host.endsWith('.google.com') ||
        host == 'maps.apple.com' ||
        host == 'waze.com' ||
        host == 'www.waze.com';
  }

  static CorrectedLocation? _extract(String text) {
    var decoded = text;
    try {
      decoded = Uri.decodeFull(text);
    } catch (_) {
      // Keep parsing the original input when a copied URL contains an
      // incomplete percent escape instead of failing the correction dialog.
    }
    final patterns = <RegExp>[
      RegExp(r'@(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)'),
      RegExp(
        r'!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:[?&](?:q|query|destination|center|ll)=)(-?\d{1,2}(?:\.\d+)?)(?:%2C|,|\s+)(-?\d{1,3}(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(r'(?<!\d)(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)(?!\d)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(decoded);
      if (match == null) continue;
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null &&
          lng != null &&
          lat.isFinite &&
          lng.isFinite &&
          lat >= -90 &&
          lat <= 90 &&
          lng >= -180 &&
          lng <= 180 &&
          !(lat == 0 && lng == 0)) {
        return CorrectedLocation(lat, lng);
      }
    }
    return null;
  }
}
