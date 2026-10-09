import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import 'scan_api_service.dart';

/// The driver's Online/Offline switch. Offline stays offline even when
/// there is internet (weak-network areas): status updates are saved on the
/// phone and sent in order when the driver switches back to Online.
class OfflineMode {
  OfflineMode._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'offline_mode_v1';

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool get isOn => enabled.value;

  static const needsInternetMessage =
      'هذي الخدمة تحتاج إنترنت، حوّل لوضع أونلاين لما يكون النت زين.';

  static Future<void> load() async {
    try {
      enabled.value = await _storage.read(key: _key) == '1';
    } catch (_) {}
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      await _storage.write(key: _key, value: on ? '1' : '0');
    } catch (_) {}
  }

  /// The request never reached SLS or got no answer (no internet, weak
  /// signal, time-out), as opposed to SLS answering with a refusal.
  static bool isNetworkError(Object? error) {
    if (error is TimeoutException || error is SocketException) return true;
    if (error is DioException) return error.response == null;
    if (error is ScanApiException) {
      return error.statusCode == null && error.responseBody.isEmpty;
    }
    if (error is ApiException) return error.statusCode == null;
    return false;
  }
}
