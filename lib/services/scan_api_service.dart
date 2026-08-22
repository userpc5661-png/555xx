import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/scan_api_config.dart';
import '../models/scan_models.dart';
import 'developer_diagnostics_service.dart';
import 'session_credentials.dart';

class ScanApiException implements Exception {
  final String message;
  final int? statusCode;
  final String responseBody;
  final ScanAttemptResult? attempt;

  const ScanApiException(
    this.message, {
    this.statusCode,
    this.responseBody = '',
    this.attempt,
  });

  @override
  String toString() => message;
}

class ScanApiService {
  final Dio _dio;
  final SessionCredentials _session;

  ScanApiService({required String savedSession, Dio? dio})
      : _session = SessionCredentials.fromSavedSession(savedSession),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 25),
                sendTimeout: const Duration(seconds: 20),
              ),
            ) {
    DeveloperDiagnosticsService.instance.attach(_dio);
  }

  Map<String, dynamic> get sessionIds => _session.ids;

  String get _apiToken {
    if (_session.apiToken.isEmpty) {
      throw const ScanApiException(
        'جلسة الدخول لا تحتوي على api_token. سجل الخروج ثم ادخل مرة أخرى.',
      );
    }
    return _session.apiToken;
  }

  Future<LinehaulGroup> scanLinehaulGroup(String groupCode) async {
    final body = await _get(
      ScanApiConfig.linehaulGroup,
      queryParameters: {'group_id': groupCode, 'api_token': _apiToken},
      rawCode: groupCode,
      attemptType: 'ROUTE',
    );
    return LinehaulGroup.fromJson(_requiredMap(body, 'group'));
  }

  Future<ScanActionResult> receiveLinehaulGroups(List<int> groupIds) async {
    return _action(
      await _post(
        ScanApiConfig.receiveLinehaul,
        data: {'group_id': groupIds, 'api_token': _apiToken},
      ),
    );
  }

  Future<ScanActionResult> dispatchLinehaulGroups(List<int> groupIds) async {
    return _action(
      await _post(
        ScanApiConfig.dispatchLinehaul,
        data: {'group_id': groupIds, 'api_token': _apiToken},
      ),
    );
  }

  Future<ScannedOrderGroup> scanOrderGroup(String groupCode) async {
    final body = await _get(
      '${ScanApiConfig.orderGroups}/$groupCode',
      queryParameters: {'api_token': _apiToken, 'app_version': '3'},
      rawCode: groupCode,
      attemptType: 'GROUP',
    );
    return ScannedOrderGroup.fromJson(_requiredMap(body, 'order_group'));
  }

  Future<ScannedShipment> scanOrder(String awb) async {
    final body = await _get(
      '${ScanApiConfig.ordersByAwb}/$awb',
      queryParameters: {'api_token': _apiToken, 'app_version': '3'},
      rawCode: awb,
      attemptType: 'SHIPMENT',
    );
    return ScannedShipment.fromJson(_requiredMap(body, 'order'), awb);
  }

  Future<ScanActionResult> confirmOrder({
    required int groupId,
    required int orderId,
    required String orderAwb,
  }) async {
    return _action(
      await _post(
        ScanApiConfig.confirmOrder,
        data: {
          'group_id': groupId,
          'order_id': orderId,
          'order_awb': orderAwb,
          'api_token': _apiToken,
        },
      ),
    );
  }

  Future<ScanActionResult> moveOrderGroupToOfd(int groupId) async {
    return _action(
      await _post(
        ScanApiConfig.ofd,
        data: {'order_group_id': groupId, 'api_token': _apiToken},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      ),
    );
  }

  Future<ScanActionResult> addPickupLocation({
    required String location,
    required double latitude,
    required double longitude,
  }) async {
    return _action(
      await _post(
        '${ScanApiConfig.addPickupLocation}/${Uri.encodeComponent(location)}',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'api_token': _apiToken,
        },
      ),
    );
  }

  Future<SubTrackingResponse> getSubTrackingNumbers(String value) async {
    final body = await _get(
      '${ScanApiConfig.subTrackingNumbers}/$value',
      options: _bearerOptions(),
    );
    return SubTrackingResponse.fromJson(body);
  }

  Future<ScanActionResult> completeSubTrackingScan(String value) async {
    return _action(
      await _post(
        '${ScanApiConfig.completeSubTrackingScan}/$value',
        options: _bearerOptions(),
      ),
    );
  }

  Future<ScanActionResult> updateDriverLocation(
    DriverLocationRequest request,
  ) async {
    return _action(
      await _post(
        ScanApiConfig.driverLocation,
        data: request.toJson(_apiToken),
      ),
    );
  }

  Future<List<SequencerOrder>> getSequencerOddOrders() async {
    final body = await _get(
      ScanApiConfig.sequencerOddOrders,
      queryParameters: {'api_token': _apiToken},
    );
    final orders = body['orders'];
    if (orders is! List) return const [];
    return orders
        .whereType<Map>()
        .map((value) => SequencerOrder.fromJson(
              Map<String, dynamic>.from(value),
            ))
        .toList();
  }


  Future<ScanActionResult> registerPosPayment({
    required Map<String, dynamic> officialBody,
  }) async {
    final body = Map<String, dynamic>.from(officialBody)
      ..['api_token'] = _apiToken;
    return _action(
      await _post(ScanApiConfig.bulkPos, data: FormData.fromMap(body)),
    );
  }

  Future<ScanActionResult> updateStatus({
    required Map<String, dynamic> officialBody,
    Object? assigneeId,
    double? latitude,
    double? longitude,
  }) async {
    Object? finalAssigneeId = assigneeId;
    String idSource = 'shipment.assignee_id';

    if (finalAssigneeId == null) {
      final ids = _session.ids;
      if (ids.containsKey('assignee_id')) {
        finalAssigneeId = ids['assignee_id'];
        idSource = 'session.assignee_id';
      } else if (ids.containsKey('driver_id')) {
        finalAssigneeId = ids['driver_id'];
        idSource = 'session.driver_id';
      } else if (ids.containsKey('id')) {
        finalAssigneeId = ids['id'];
        idSource = 'session.id';
      } else if (ids.containsKey('user_id')) {
        finalAssigneeId = ids['user_id'];
        idSource = 'session.user_id';
      }

      if (finalAssigneeId != null) {
        debugPrint(
            'SLS STATUS UPDATE: shipment.assignee_id is missing. '
            'Using fallback from $idSource: $finalAssigneeId');
      }
    }

    final body = Map<String, dynamic>.from(officialBody)
      ..['api_token'] = _apiToken
      ..['app_version'] = '3';

    if (finalAssigneeId != null) {
      body['assignee_id'] = finalAssigneeId;
    }

    if (latitude != null) body['lat'] = latitude.toString();
    if (longitude != null) body['lng'] = longitude.toString();

    return _action(
      await _post(ScanApiConfig.bulkStatus, data: FormData.fromMap(body)),
    );
  }

  Future<Map<String, dynamic>> getDriverStatuses({
    required bool withoutScan,
    required Object currentStatus,
    required Object currentStatusLabel,
    required Object currentIsRvp,
    required Object currentOrderType,
  }) async {
    final url = withoutScan
        ? ScanApiConfig.driverStatusesWithoutScan
        : ScanApiConfig.driverStatuses;

    final queryParameters = {
      'current_status': currentStatus,
      'current_status_label': currentStatusLabel,
      'current_is_rvp': currentIsRvp,
      'current_order_type': currentOrderType,
      'app_version': 3,
      'api_token': _apiToken,
    };

    final safeParams = Map<String, dynamic>.from(queryParameters);
    if (safeParams.containsKey('api_token')) {
      safeParams['api_token'] = '***';
    }

    debugPrint('SLS STATUS DISCOVERY - START REQUEST');
    debugPrint('SLS STATUS DISCOVERY URL: $url');
    debugPrint('SLS STATUS DISCOVERY PARAMS: $safeParams');
    debugPrint('SLS STATUS DISCOVERY RUNTIME - currentStatus: $currentStatus');
    debugPrint(
        'SLS STATUS DISCOVERY RUNTIME - currentStatusLabel: $currentStatusLabel');
    debugPrint('SLS STATUS DISCOVERY RUNTIME - currentIsRvp: $currentIsRvp');
    debugPrint(
        'SLS STATUS DISCOVERY RUNTIME - currentOrderType: $currentOrderType');
    debugPrint('SLS STATUS DISCOVERY RUNTIME - app_version: 3');

    try {
      final response = await _dio.get<String>(
        url,
        queryParameters: queryParameters,
        options: _plainOptions(_bearerOptions()),
      );

      final rawBody = response.data ?? '';
      debugPrint(
          'SLS STATUS DISCOVERY RESPONSE HTTP CODE: ${response.statusCode}');
      debugPrint('SLS STATUS DISCOVERY RESPONSE BODY: $rawBody');
      debugPrint('SLS STATUS DISCOVERY - END REQUEST');

      final body = _decodeMap(rawBody);
      final status = response.statusCode ?? 0;

      if (status < 200 || status >= 300) {
        throw ScanApiException(
          _message(body, 'فشل جلب الحالات المتاحة من SLS (HTTP $status).'),
          statusCode: status,
          responseBody: rawBody,
        );
      }

      final success = body['success'];
      if (success == false ||
          success == 0 ||
          success?.toString().toLowerCase() == 'false') {
        throw ScanApiException(
          _message(body, 'رفض نظام SLS تزويدنا بالحالات المتاحة لهذه الشحنة.'),
          statusCode: status,
          responseBody: rawBody,
        );
      }

      return body;
    } on DioException catch (error) {
      final raw = _asText(error.response?.data);
      final body = _decodeMap(raw);
      debugPrint(
        'SLS STATUS DISCOVERY NETWORK ERROR: ${error.type}; ${error.message}; '
        'url=$url',
      );
      throw ScanApiException(
        _message(body, error.message ?? 'تعذر الاتصال بنظام SLS لجلب الحالات.'),
        statusCode: error.response?.statusCode,
        responseBody: raw,
      );
    }
  }

  Options _bearerOptions() => Options(
        headers: {'Authorization': 'Bearer $_apiToken'},
      );

  Future<Map<String, dynamic>> _get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    String? rawCode,
    String? attemptType,
  }) async {
    return _request(
      () => _dio.get<String>(
        url,
        queryParameters: queryParameters,
        options: _plainOptions(options),
      ),
      rawCode: rawCode,
      attemptType: attemptType,
    );
  }

  Future<Map<String, dynamic>> _post(
    String url, {
    Object? data,
    Options? options,
    String? rawCode,
    String? attemptType,
  }) async {
    return _request(
      () => _dio.post<String>(
        url,
        data: data,
        options: _plainOptions(options),
      ),
      rawCode: rawCode,
      attemptType: attemptType,
    );
  }

  Options _plainOptions(Options? source) {
    final original = source ?? Options();
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      if (_session.cookie.trim().isNotEmpty) 'Cookie': _session.cookie.trim(),
      ...?original.headers,
    };
    return original.copyWith(
      headers: headers,
      responseType: ResponseType.plain,
      followRedirects: false,
      maxRedirects: 0,
      validateStatus: (_) => true,
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<String>> Function() request, {
    String? rawCode,
    String? attemptType,
  }) async {
    Response<String>? response;
    String? errorText;

    try {
      response = await request();
      final raw = response.data ?? '';
      final status = response.statusCode ?? 0;
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      final redirectLocation = response.headers.value('location') ?? '';

      if (rawCode != null && attemptType != null) {
        _logScanAttempt(
          rawCode: rawCode,
          type: attemptType,
          response: response,
        );
      }

      final attempt = (rawCode != null && attemptType != null)
          ? _createAttemptResult(
              type: attemptType,
              response: response,
              succeeded: true,
            )
          : null;

      if (_looksLikeHtml(raw, contentType)) {
        throw ScanApiException(
          'رجع خادم SLS صفحة ويب بدل استجابة API. '
          'تم منع عرض كود HTML. أعد تسجيل الدخول مرة واحدة ثم جرّب، '
          'وإذا استمرت المشكلة افتح سجل العملية لإرسال حالة الطلب فقط.',
          statusCode: status,
          responseBody: raw,
          attempt: attempt?.copyWith(
            succeeded: false,
            errorMessage: 'HTML response received',
          ),
        );
      }

      final body = _decodeMap(raw);
      if (status >= 300 && status < 400) {
        throw ScanApiException(
          redirectLocation.isEmpty
              ? 'حوّل خادم SLS الطلب إلى صفحة أخرى؛ غالبًا انتهت الجلسة.'
              : 'حوّل خادم SLS الطلب إلى $redirectLocation؛ غالبًا انتهت الجلسة.',
          statusCode: status,
          responseBody: raw,
          attempt: attempt?.copyWith(succeeded: false),
        );
      }
      if (status < 200 || status >= 300) {
        throw ScanApiException(
          _message(
            body,
            status == 404 ? 'Not Found' : 'فشل طلب المسح من نظام SLS.',
          ),
          statusCode: status,
          responseBody: raw,
          attempt: attempt?.copyWith(succeeded: false),
        );
      }
      return body;
    } on DioException catch (error) {
      response = error.response as Response<String>?;
      errorText = error.message;

      if (rawCode != null && attemptType != null) {
        _logScanAttempt(
          rawCode: rawCode,
          type: attemptType,
          response: response,
          error: errorText,
        );
      }

      final attempt = (rawCode != null && attemptType != null)
          ? _createAttemptResult(
              type: attemptType,
              response: response ?? error.response as Response<String>?,
              succeeded: false,
              error: errorText,
            )
          : null;

      final raw = _asText(response?.data);
      final body = _decodeMap(raw);
      final status = response?.statusCode;
      throw ScanApiException(
        _message(
          body,
          status == 404
              ? 'Not Found'
              : (errorText ?? 'تعذر الاتصال بنظام SLS.'),
        ),
        statusCode: status,
        responseBody: raw,
        attempt: attempt,
      );
    }
  }

  ScanAttemptResult _createAttemptResult({
    required String type,
    Response<String>? response,
    required bool succeeded,
    String? error,
  }) {
    final options = response?.requestOptions;
    return ScanAttemptResult(
      type: type,
      method: options?.method ?? 'UNKNOWN',
      sanitizedUrl: options != null ? _maskUrl(options.uri) : '',
      sanitizedQuery: options != null ? Map<String, dynamic>.from(_maskData(options.queryParameters) as Map) : {},
      sanitizedBody: options != null ? _maskData(options.data) : null,
      statusCode: response?.statusCode ?? 0,
      responseBody: response?.data ?? '',
      errorMessage: error,
      timestamp: DateTime.now(),
      succeeded: succeeded,
    );
  }

  void _logScanAttempt({
    required String rawCode,
    required String type,
    Response<String>? response,
    String? error,
  }) {
    final options = response?.requestOptions;
    if (options == null) return;

    final method = options.method;
    final url = _maskUrl(options.uri);
    final query = _maskData(options.queryParameters);
    final body = _maskData(options.data);
    final status = response?.statusCode ?? 0;
    final rawResp = response?.data ?? error ?? '';
    final safeResp = rawResp.length > 10000 
        ? '${rawResp.substring(0, 10000)} [TRUNCATED]' 
        : rawResp;

    debugPrint('================ SLS SCAN START ================');
    debugPrint('RAW CODE: $rawCode');
    debugPrint('TYPE ATTEMPT: $type');
    debugPrint('METHOD: $method');
    debugPrint('URL: $url');
    if (query is Map && query.isNotEmpty) {
      debugPrint('QUERY: ${jsonEncode(query)}');
    }
    if (body != null) {
      debugPrint('BODY: ${_safeStringify(body)}');
    }
    debugPrint('HTTP STATUS: $status');
    debugPrint('RESPONSE: $safeResp');
    debugPrint('================ SLS SCAN END ==================');
  }

  String _maskUrl(Uri uri) {
    final query = Map<String, String>.from(uri.queryParameters);
    for (final key in query.keys) {
      if (_isSensitive(key)) query[key] = '***';
    }
    return uri.replace(queryParameters: query).toString();
  }

  Object? _maskData(Object? data) {
    if (data == null) return null;
    if (data is Map) {
      return {
        for (final entry in data.entries)
          entry.key: _isSensitive(entry.key.toString()) 
              ? '***' 
              : _maskData(entry.value)
      };
    }
    if (data is List) {
      return data.map(_maskData).toList();
    }
    if (data is FormData) {
      return {
        for (final field in data.fields)
          field.key: _isSensitive(field.key) ? '***' : field.value,
        for (final file in data.files)
          file.key: '<file:${file.value.filename}>'
      };
    }
    return data;
  }

  bool _isSensitive(String key) {
    final k = key.toLowerCase().replaceAll('_', '');
    return k.contains('token') || 
           k.contains('authorization') || 
           k.contains('cookie') || 
           k.contains('password') || 
           k.contains('jwt');
  }

  String _safeStringify(Object? data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  Map<String, dynamic> _requiredMap(
    Map<String, dynamic> body,
    String key,
  ) {
    final value = body[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    throw ScanApiException(
      _message(body, 'رد SLS لا يحتوي على الحقل المطلوب: $key'),
      responseBody: jsonEncode(body),
    );
  }

  ScanActionResult _action(Map<String, dynamic> body) {
    final result = ScanActionResult.fromJson(body);
    final value = body['success'];
    final explicitlyFailed = value == false ||
        value == 0 ||
        value?.toString().trim().toLowerCase() == 'false';
    if (explicitlyFailed) {
      throw ScanApiException(
        result.message.isEmpty ? 'رفض نظام SLS تنفيذ العملية.' : result.message,
        responseBody: jsonEncode(body),
      );
    }
    return result;
  }

  bool _looksLikeHtml(String raw, String contentType) {
    final trimmed = raw.trimLeft().toLowerCase();
    return contentType.toLowerCase().contains('text/html') ||
        trimmed.startsWith('<!doctype html') ||
        trimmed.startsWith('<html');
  }

  Map<String, dynamic> _decodeMap(String raw) {
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final value = jsonDecode(raw);
      if (value is Map) return Map<String, dynamic>.from(value);
      return {'data': value};
    } catch (_) {
      return {'message': raw};
    }
  }

  String _message(Map<String, dynamic> body, String fallback) {
    for (final key in ['message', 'error', 'detail', 'success']) {
      final value = body[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  String _asText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
