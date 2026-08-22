import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/task_item.dart';
import 'developer_diagnostics_service.dart';

class CorrectedLocation {
  final double latitude;
  final double longitude;
  const CorrectedLocation(this.latitude, this.longitude);

  Map<String, dynamic> toJson() => {'lat': latitude, 'lng': longitude};
  factory CorrectedLocation.fromJson(Map<String, dynamic> json) =>
      CorrectedLocation(
          (json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
}

class LocationCorrectionService {
  LocationCorrectionService._();

  static const _storage = FlutterSecureStorage();
  static String _key(TaskItem task) =>
      'shipment_location_${task.displayReference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  static Future<CorrectedLocation?> load(TaskItem task) async {
    final raw = await _storage.read(key: _key(task));
    if (raw == null) return null;
    try {
      return CorrectedLocation.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(TaskItem task, CorrectedLocation value) async {
    await _storage.write(
      key: _key(task),
      value: jsonEncode(value.toJson()),
    );
    DeveloperDiagnosticsService.instance.setContext(
      'Local customer location',
      '${task.displayReference}: ${value.latitude}, ${value.longitude}',
    );
  }

  static Future<void> restore(TaskItem task) async {
    await _storage.delete(key: _key(task));
  }

  static Future<CorrectedLocation?> parse(String input) async {
    final text = input.trim();
    if (text.isEmpty) return null;
    final direct = _extract(text);
    if (direct != null) return direct;
    final uri = Uri.tryParse(text);
    if (uri == null || !_isGoogleMapsUri(uri)) return null;
    try {
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        followRedirects: true,
        maxRedirects: 6,
        validateStatus: (status) => status != null && status < 500,
      )).getUri<dynamic>(uri);
      final finalUrl = response.realUri.toString();
      return _extract(finalUrl) ??
          _extract(response.headers.value('location') ?? '');
    } catch (_) {
      return null;
    }
  }

  static bool _isGoogleMapsUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'maps.app.goo.gl' ||
        host == 'goo.gl' ||
        host == 'maps.google.com' ||
        host == 'www.google.com' ||
        host.endsWith('.google.com');
  }

  static CorrectedLocation? _extract(String text) {
    final decoded = Uri.decodeFull(text);
    final patterns = <RegExp>[
      RegExp(r'@(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)'),
      RegExp(
          r'(?:[?&](?:q|query|destination|center|ll)=)(-?\d{1,2}(?:\.\d+)?)(?:%2C|,|\s+)(-?\d{1,3}(?:\.\d+)?)',
          caseSensitive: false),
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
