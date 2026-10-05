import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DiagnosticEntry {
  final DateTime timestamp;
  final String method;
  final String url;
  final int? statusCode;
  final Object? payload;
  final Object? response;
  final String? error;
  final Duration? duration;

  const DiagnosticEntry({
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    this.payload,
    this.response,
    this.error,
    this.duration,
  });

  /// The response as readable text: JSON strings are decoded and indented.
  String get prettyResponse => DeveloperDiagnosticsService.pretty(response);
  String get prettyPayload => DeveloperDiagnosticsService.pretty(payload);

  String toReport() => [
        '### $method ${statusCode ?? '-'}  $url',
        'time: ${timestamp.toIso8601String()}'
            '${duration == null ? '' : '  duration: ${duration!.inMilliseconds}ms'}',
        '--- payload ---',
        prettyPayload,
        '--- response ---',
        prettyResponse,
        if (error != null) '--- error ---\n$error',
      ].join('\n');
}

class DeveloperDiagnosticsService {
  DeveloperDiagnosticsService._();

  static final instance = DeveloperDiagnosticsService._();
  final ValueNotifier<List<DiagnosticEntry>> entries =
      ValueNotifier<List<DiagnosticEntry>>(const []);
  final ValueNotifier<Map<String, String>> context =
      ValueNotifier<Map<String, String>>(const {});

  void attach(Dio dio) {
    if (dio.interceptors.any((item) => item is _DiagnosticsInterceptor)) {
      return;
    }
    dio.interceptors.add(_DiagnosticsInterceptor(this));
  }

  void setContext(String key, Object? value) {
    context.value = {
      ...context.value,
      key: _safeText(value),
    };
  }

  void validation(String message) => setContext('Validation errors', message);

  void clear() {
    entries.value = const [];
    context.value = const {};
  }

  // ---- Log file: every request/reply of the shift, kept across restarts,
  // so the whole delivery day can be shared as one .txt file. ----

  static const _maxLogBytes = 20 * 1024 * 1024;
  Future<void> _writes = Future<void>.value();
  bool _sessionHeaderWritten = false;

  Future<Directory> _dir() async => getApplicationDocumentsDirectory();
  Future<File> _logFile() async => File('${(await _dir()).path}/diagnostics_log.txt');
  Future<File> _previousLogFile() async =>
      File('${(await _dir()).path}/diagnostics_log_prev.txt');

  void _append(String text) {
    _writes = _writes.then((_) async {
      try {
        final file = await _logFile();
        if (await file.exists() && await file.length() > _maxLogBytes) {
          await file.rename((await _previousLogFile()).path);
        }
        final header = _sessionHeaderWritten
            ? ''
            : '\n===== تشغيل البرنامج ${DateTime.now().toIso8601String()} =====\n\n';
        _sessionHeaderWritten = true;
        await (await _logFile())
            .writeAsString('$header$text\n\n', mode: FileMode.append, flush: false);
      } catch (error) {
        debugPrint('Diagnostics log write failed: $error');
      }
    });
  }

  /// Size of the saved log, for the screen.
  Future<int> logBytes() async {
    await _writes;
    var total = 0;
    for (final file in [await _previousLogFile(), await _logFile()]) {
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  /// One .txt file with the summaries and the whole saved log, streamed so
  /// a big log does not freeze the phone.
  Future<File> exportLogFile() async {
    await _writes;
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final out = File('${(await getTemporaryDirectory()).path}/sls_diagnostics_$stamp.txt');
    final sink = out.openWrite();
    sink.writeln('SLS Driver diagnostics — ${DateTime.now().toIso8601String()}');
    sink.writeln('(tokens, cookies and passwords are masked)\n');
    for (final item in context.value.entries) {
      sink.writeln('## ${item.key}\n${item.value}\n');
    }
    sink.writeln('\n########## سجل الطلبات ##########\n');
    for (final file in [await _previousLogFile(), await _logFile()]) {
      if (await file.exists()) await sink.addStream(file.openRead());
    }
    await sink.close();
    return out;
  }

  /// Deletes the saved log and the in-memory list (e.g. before a shift).
  Future<void> startNewLog() async {
    await _writes;
    for (final file in [await _previousLogFile(), await _logFile()]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _sessionHeaderWritten = false;
    clear();
  }

  void _add(DiagnosticEntry entry) {
    _append(entry.toReport());
    final next = [...entries.value, entry];
    // Kept small: it is also on in release builds (iPhone/Android).
    entries.value = next.length > 40
        ? List<DiagnosticEntry>.unmodifiable(next.sublist(next.length - 40))
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

  /// Masked, readable text. A JSON string (responses are fetched as plain
  /// text) is decoded first so it is shown indented instead of escaped.
  static String pretty(Object? value) {
    if (value == null) return '<empty>';
    Object? data = value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          data = jsonDecode(trimmed);
        } catch (_) {}
      }
    }
    return _safeText(data);
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

  static const _startKey = 'diagnostics_started_at';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();
    handler.next(options);
  }

  Duration? _elapsed(RequestOptions options) {
    final started = options.extra[_startKey];
    return started is DateTime ? DateTime.now().difference(started) : null;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final safeUrl = _safeUrl(response.requestOptions.uri);
    final safePayload = DeveloperDiagnosticsService.mask(
      response.requestOptions.data ?? response.requestOptions.queryParameters,
    );
    final safeResponse = DeveloperDiagnosticsService.mask(response.data);
    debugPrint('SLS SCAN HTTP ${response.requestOptions.method} $safeUrl');
    debugPrint('SLS SCAN PAYLOAD: ${DeveloperDiagnosticsService._safeText(safePayload)}');
    debugPrint('SLS SCAN RESPONSE HTTP ${response.statusCode}: ${DeveloperDiagnosticsService._safeText(safeResponse)}');
    service._add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        method: response.requestOptions.method,
        url: safeUrl,
        statusCode: response.statusCode,
        payload: safePayload,
        response: safeResponse,
        duration: _elapsed(response.requestOptions),
      ),
    );
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final safeUrl = _safeUrl(error.requestOptions.uri);
    final safePayload = DeveloperDiagnosticsService.mask(
      error.requestOptions.data ?? error.requestOptions.queryParameters,
    );
    final safeResponse = DeveloperDiagnosticsService.mask(error.response?.data);
    debugPrint('SLS SCAN HTTP ERROR ${error.requestOptions.method} $safeUrl');
    debugPrint('SLS SCAN PAYLOAD: ${DeveloperDiagnosticsService._safeText(safePayload)}');
    debugPrint('SLS SCAN RESPONSE HTTP ${error.response?.statusCode}: ${DeveloperDiagnosticsService._safeText(safeResponse)}');
    debugPrint('SLS SCAN EXCEPTION: ${error.message}');
    service._add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        method: error.requestOptions.method,
        url: safeUrl,
        statusCode: error.response?.statusCode,
        payload: safePayload,
        response: safeResponse,
        error: error.message,
        duration: _elapsed(error.requestOptions),
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
