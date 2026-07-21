import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DiagnosticEntry {
  final DateTime timestamp;
  final String method;
  final String url;
  final int? statusCode;
  final Object? payload;
  final Object? response;
  final String? error;

  const DiagnosticEntry({
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    this.payload,
    this.response,
    this.error,
  });
}

class DeveloperDiagnosticsService {
  DeveloperDiagnosticsService._();

  static final instance = DeveloperDiagnosticsService._();
  final ValueNotifier<List<DiagnosticEntry>> entries =
      ValueNotifier<List<DiagnosticEntry>>(const []);
  final ValueNotifier<Map<String, String>> context =
      ValueNotifier<Map<String, String>>(const {});

  void attach(Dio dio) {
    if (!kDebugMode ||
        dio.interceptors.any((item) => item is _DiagnosticsInterceptor)) {
      return;
    }
    dio.interceptors.add(_DiagnosticsInterceptor(this));
  }

  void setContext(String key, Object? value) {
    if (!kDebugMode) return;
    context.value = {
      ...context.value,
      key: _safeText(value),
    };
  }

  void validation(String message) => setContext('Validation errors', message);

  void clear() {
    if (!kDebugMode) return;
    entries.value = const [];
    context.value = const {};
  }

  void _add(DiagnosticEntry entry) {
    if (!kDebugMode) return;
    final next = [...entries.value, entry];
    entries.value = next.length > 100
        ? List<DiagnosticEntry>.unmodifiable(next.sublist(next.length - 100))
        : List<DiagnosticEntry>.unmodifiable(next);
  }

  static Object? mask(Object? value) {
    if (value is FormData) {
      return <String, Object?>{
        for (final field in value.fields) field.key: mask(field.value),
        for (final file in value.files)
          file.key: '<file:${file.value.filename ?? 'attachment'}>',
      };
    }
    if (value is Map) {
      return value.map((key, item) {
        final name = key.toString();
        final normalized = name.toLowerCase().replaceAll('_', '');
        if (normalized.contains('token') ||
            normalized.contains('password') ||
            normalized == 'authorization' ||
            normalized == 'cookie') {
          return MapEntry(name, '<masked>');
        }
        return MapEntry(name, mask(item));
      });
    }
    if (value is Iterable) return value.map(mask).toList(growable: false);
    if (value is String) {
      return value.replaceAll(
        RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
        '<masked-token>',
      );
    }
    return value;
  }

  static String _safeText(Object? value) {
    final masked = mask(value);
    if (masked is String) return masked;
    try {
      return const JsonEncoder.withIndent('  ').convert(masked);
    } catch (_) {
      return masked?.toString() ?? '';
    }
  }
}

class _DiagnosticsInterceptor extends Interceptor {
  final DeveloperDiagnosticsService service;
  _DiagnosticsInterceptor(this.service);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    service._add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        method: response.requestOptions.method,
        url: _safeUrl(response.requestOptions.uri),
        statusCode: response.statusCode,
        payload: DeveloperDiagnosticsService.mask(
          response.requestOptions.data ??
              response.requestOptions.queryParameters,
        ),
        response: DeveloperDiagnosticsService.mask(response.data),
      ),
    );
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    service._add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        method: error.requestOptions.method,
        url: _safeUrl(error.requestOptions.uri),
        statusCode: error.response?.statusCode,
        payload: DeveloperDiagnosticsService.mask(
          error.requestOptions.data ?? error.requestOptions.queryParameters,
        ),
        response: DeveloperDiagnosticsService.mask(error.response?.data),
        error: error.message,
      ),
    );
    handler.next(error);
  }

  String _safeUrl(Uri uri) {
    final query = Map<String, String>.from(uri.queryParameters);
    for (final key in query.keys.toList()) {
      if (key.toLowerCase().contains('token')) query[key] = '<masked>';
    }
    return uri.replace(queryParameters: query).toString();
  }
}
