import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/api_config.dart';
import '../models/task_item.dart';
import 'developer_diagnostics_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  final Dio _dio;

  ApiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 25),
                sendTimeout: const Duration(seconds: 20),
              ),
            ) {
    DeveloperDiagnosticsService.instance.attach(_dio);
  }

  /// Keeps the existing login flow and stores both authentication values in
  /// one opaque string. The password is never persisted.
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<String>(
      ApiConfig.login,
      data: {
        'email': email,
        'password': password,
        'app_version': '3',
      },
      options: Options(
        headers: const {'Accept': 'application/json'},
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );

    final statusCode = response.statusCode ?? 0;
    final rawBody = response.data ?? '';
    final body = _decode(rawBody);

    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        _messageFrom(body, 'فشل تسجيل الدخول'),
        statusCode: statusCode,
      );
    }

    // The official app reads response["user"]["api_token"] and persists it
    // as apiToken. Prefer that exact field before compatibility fallbacks.
    final officialApiToken = _findExactStringValue(body, 'api_token');
    final headerToken = _cleanBearerValue(
      response.headers.value('authorization'),
    );
    final token = officialApiToken ?? headerToken ?? _findToken(body);
    final cookie = _extractCookies(response.headers['set-cookie']);

    debugPrint(
      'SLS LOGIN: HTTP $statusCode, '
      'token=${_secretSummary(token)}, '
      'cookie=${_secretSummary(cookie)}, '
      'bodyShape=${_describeShape(body)}',
    );

    if ((token == null || token.isEmpty) &&
        (cookie == null || cookie.isEmpty)) {
      throw ApiException(
        'نجح تسجيل الدخول، لكن لم يتم العثور على بيانات الجلسة. '
        'شكل الرد الآمن: ${_describeShape(body)}',
      );
    }

    return jsonEncode({
      'v': 2,
      if (token != null && token.isNotEmpty) 'bearer': token,
      if (cookie != null && cookie.isNotEmpty) 'cookie': cookie,
    });
  }

  /// Matches the official SLS Driver tasks request found in the application:
  /// GET /api/mobile/tasks with api_token, filters, sort, app_version, lat,
  /// and lng as the only query parameters. Dio performs URL encoding.
  Future<List<TaskItem>> fetchTasks(String savedSession) async {
    final session = _readSavedSession(savedSession);
    final apiToken = session['bearer'];
    final cookie = session['cookie'] ?? '';

    if (apiToken == null || apiToken.isEmpty) {
      throw const ApiException(
        'جلسة الدخول لا تحتوي على api_token. سجّل الخروج ثم ادخل مرة أخرى.',
      );
    }

    final coordinates = await _currentCoordinates();
    final queryParameters = <String, dynamic>{
      'api_token': apiToken,
      'filters': jsonEncode(const {'task_type': '', 'order_type': ''}),
      'sort': jsonEncode(const {'column': '', 'order': ''}),
      'app_version': '3',
      'lat': coordinates.$1.toString(),
      'lng': coordinates.$2.toString(),
    };

    try {
      final response = await _dio.get<String>(
        ApiConfig.tasks,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            if (cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
          },
          responseType: ResponseType.plain,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (_) => true,
        ),
      );

      final rawBody = response.data ?? '';
      debugPrint(
        'SLS TASKS REQUEST: ${_redactUrl(response.requestOptions.uri)}; '
        'headers=${_redactedHeaders(response.requestOptions.headers)}',
      );
      debugPrint(
        'SLS TASKS RESPONSE: HTTP ${response.statusCode}; '
        'body=${_safePreview(rawBody)}',
      );

      final statusCode = response.statusCode ?? 0;
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      if (_looksLikeHtml(rawBody, contentType)) {
        throw ApiException(
          'رجع خادم SLS صفحة ويب بدل بيانات المهام. '
          'غالبًا انتهت الجلسة؛ سجّل الدخول مرة واحدة ثم أعد المحاولة.',
          statusCode: statusCode == 200 ? 401 : statusCode,
        );
      }
      if (statusCode >= 300 && statusCode < 400) {
        throw ApiException(
          'تم تحويل طلب المهام إلى صفحة دخول؛ انتهت الجلسة.',
          statusCode: 401,
        );
      }
      final body = _decode(rawBody);
      if (statusCode < 200 || statusCode >= 300) {
        throw ApiException(
          _messageFrom(body, 'تعذر جلب المهام من نظام الشركة'),
          statusCode: statusCode,
        );
      }

      final rows = _expandTaskRows(_findTaskRows(body));
      return rows
          .whereType<Map>()
          .map((row) => TaskItem.fromJson(Map<String, dynamic>.from(row)))
          .where((task) =>
              task.id.isNotEmpty ||
              task.referenceNumber.isNotEmpty ||
              task.customerName.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      final response = error.response;
      debugPrint(
        'SLS TASKS NETWORK ERROR: ${error.type}; ${error.message}; '
        'url=${_redactUrl(error.requestOptions.uri)}',
      );
      throw ApiException(
        'تعذر الاتصال بنظام الشركة: ${error.message ?? 'خطأ شبكة غير معروف'}',
        statusCode: response?.statusCode,
      );
    }
  }

  Map<String, String> _readSavedSession(String savedSession) {
    final value = savedSession.trim();
    if (value.startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return {
            if (decoded['bearer'] is String)
              'bearer': decoded['bearer'] as String,
            if (decoded['cookie'] is String)
              'cookie': decoded['cookie'] as String,
          };
        }
      } catch (_) {
        // Continue with compatibility formats below.
      }
    }
    if (value.startsWith('cookie:')) {
      return {'cookie': value.substring('cookie:'.length)};
    }
    if (value.startsWith('bearer:')) {
      return {'bearer': value.substring('bearer:'.length)};
    }
    return {'bearer': value};
  }

  Future<(double, double)> _currentCoordinates() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const ApiException(
        'فعّل خدمة الموقع (GPS) ثم اضغط إعادة المحاولة.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const ApiException(
        'اسمح للتطبيق بالوصول إلى الموقع حتى يتمكن من جلب المهام.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ApiException(
        'صلاحية الموقع مرفوضة نهائيًا. فعّلها من إعدادات التطبيق.',
      );
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return (current.latitude, current.longitude);
    } catch (error) {
      if (lastKnown != null) {
        debugPrint('SLS LOCATION: using the last known position ($error)');
        return (lastKnown.latitude, lastKnown.longitude);
      }
      throw const ApiException(
        'تعذر تحديد موقعك. افتح الخرائط للحظات ثم أعد المحاولة.',
      );
    }
  }

  bool _looksLikeHtml(String raw, String contentType) {
    final trimmed = raw.trimLeft().toLowerCase();
    return contentType.toLowerCase().contains('text/html') ||
        trimmed.startsWith('<!doctype html') ||
        trimmed.startsWith('<html');
  }

  dynamic _decode(String source) {
    if (source.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(source);
    } catch (_) {
      return {'message': source};
    }
  }

  String _messageFrom(dynamic body, String fallback) {
    if (body is Map) {
      for (final key in ['message', 'error', 'detail', 'errors']) {
        final value = body[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
    }
    return fallback;
  }

  String? _findToken(dynamic node) {
    if (node == null) return null;
    if (node is Map) {
      for (final entry in node.entries) {
        final key = _normalizeKey(entry.key.toString());
        if (_isTokenKey(key)) {
          final candidate = _tokenFromValue(entry.value);
          if (candidate != null) return candidate;
        }
      }
      for (final value in node.values) {
        final found = _findToken(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findToken(value);
        if (found != null) return found;
      }
    } else if (node is String) {
      return _jwtFromText(node);
    }
    return null;
  }

  String? _findExactStringValue(dynamic node, String expectedKey) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (entry.key.toString() == expectedKey && entry.value is String) {
          final value = (entry.value as String).trim();
          if (value.isNotEmpty) return value;
        }
      }
      for (final value in node.values) {
        final found = _findExactStringValue(value, expectedKey);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findExactStringValue(value, expectedKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _isTokenKey(String key) {
    const exactKeys = {
      'token',
      'accesstoken',
      'authtoken',
      'apitoken',
      'bearertoken',
      'jwt',
      'jwttoken',
      'authorization',
    };
    return exactKeys.contains(key) ||
        key.endsWith('token') ||
        key.contains('accesstoken');
  }

  String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String? _tokenFromValue(dynamic value) {
    if (value is! String) return null;
    return _cleanBearerValue(value) ?? _jwtFromText(value);
  }

  String? _cleanBearerValue(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    final match = RegExp(
      r'^Bearer\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return match.group(1)?.trim();
    if (text.length >= 20 && !text.contains(' ')) return text;
    return null;
  }

  String? _jwtFromText(String text) {
    return RegExp(
      r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
    ).firstMatch(text)?.group(0);
  }

  String? _extractCookies(List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return null;
    final cookies = <String>[];
    for (final header in setCookies) {
      for (final chunk in header.split(RegExp(r',(?=[^;,]+=)'))) {
        final first = chunk.split(';').first.trim();
        if (first.contains('=') &&
            !first.toLowerCase().startsWith('expires=')) {
          cookies.add(first);
        }
      }
    }
    return cookies.isEmpty ? null : cookies.join('; ');
  }

  List<dynamic> _findTaskRows(dynamic body) {
    if (body is List) return body;
    if (body is! Map) return const [];

    // The official response model uses a top-level `tasks` collection.
    // Prefer it over any unrelated nested lists such as status labels or
    // sub-tracking numbers.
    final directTasks = body['tasks'];
    if (directTasks is List) return directTasks;

    final data = body['data'];
    if (data is Map || data is List) {
      final nested = _findTaskRows(data);
      if (nested.isNotEmpty || (data is Map && data.containsKey('tasks'))) {
        return nested;
      }
    }

    // Compatibility fallbacks for older or wrapped API responses.
    for (final key in ['orders', 'items', 'results', 'records']) {
      final value = body[key];
      if (value is List) return value;
      if (value is Map) {
        final nested = _findTaskRows(value);
        if (nested.isNotEmpty) return nested;
      }
    }

    for (final value in body.values) {
      if (value is! Map) continue;
      final nested = _findTaskRows(value);
      if (nested.isNotEmpty) return nested;
    }
    return const [];
  }

  List<dynamic> _expandTaskRows(List<dynamic> rows) {
    final expanded = <dynamic>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final task = Map<String, dynamic>.from(row);
      final orders = task['orders'];

      // Some SLS task responses group multiple orders inside one task. Create
      // one display item per order while preserving the task-level fields.
      if (orders is List && orders.whereType<Map>().isNotEmpty) {
        final parent = Map<String, dynamic>.from(task)..remove('orders');
        for (final order in orders.whereType<Map>()) {
          expanded.add(<String, dynamic>{
            'task': parent,
            'order': Map<String, dynamic>.from(order),
          });
        }
      } else {
        expanded.add(task);
      }
    }
    return expanded;
  }

  String _safePreview(String value) {
    var preview = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    preview = preview.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '<token-hidden>',
    );
    if (preview.length > 500) preview = '${preview.substring(0, 500)}…';
    return preview.isEmpty ? '<empty response>' : preview;
  }

  String _secretSummary(String? value) {
    if (value == null || value.isEmpty) return 'missing';
    return 'present(length=${value.length})';
  }

  String _redactUrl(Uri uri) {
    final parameters = Map<String, String>.from(uri.queryParameters);
    if (parameters.containsKey('api_token')) {
      parameters['api_token'] = '<hidden>';
    }
    return uri.replace(queryParameters: parameters).toString();
  }

  Map<String, String> _redactedHeaders(Map<String, dynamic> headers) {
    return headers.map((key, value) {
      final lower = key.toLowerCase();
      if (lower == 'cookie' || lower == 'authorization') {
        return MapEntry(key, '<hidden>');
      }
      return MapEntry(key, value?.toString() ?? '');
    });
  }

  String _describeShape(dynamic node, {int depth = 0}) {
    if (depth > 3) return '…';
    if (node is Map) {
      final parts = <String>[];
      for (final entry in node.entries.take(12)) {
        final key = entry.key.toString();
        final normalized = _normalizeKey(key);
        if (_isTokenKey(normalized) || normalized.contains('password')) {
          parts.add('$key:<hidden>');
        } else {
          parts.add('$key:${_describeShape(entry.value, depth: depth + 1)}');
        }
      }
      return '{${parts.join(', ')}}';
    }
    if (node is List) {
      return node.isEmpty
          ? '[]'
          : '[${_describeShape(node.first, depth: depth + 1)}]';
    }
    if (node == null) return 'null';
    return node.runtimeType.toString();
  }
}
