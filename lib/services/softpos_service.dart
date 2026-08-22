import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SoftPosPaymentResult {
  final bool success;
  final bool cancelled;
  final String message;
  final String? transactionId;
  final String? cardScheme;
  final num? amount;
  final String? udid;
  final Map<String, dynamic> gatewayResponse;
  final String? cardName;
  final String? cardNumber;
  final String? tid;
  final String? qrCode;
  final bool? isApproved;

  const SoftPosPaymentResult({
    required this.success,
    required this.cancelled,
    required this.message,
    this.transactionId,
    this.cardScheme,
    this.amount,
    this.udid,
    this.gatewayResponse = const {},
    this.cardName,
    this.cardNumber,
    this.tid,
    this.qrCode,
    this.isApproved,
  });

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }

  static bool? _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (const {'true', '1', 'yes', 'approved'}.contains(text)) return true;
    if (const {'false', '0', 'no', 'declined'}.contains(text)) return false;
    return null;
  }

  factory SoftPosPaymentResult.fromMap(Map<dynamic, dynamic> map) {
    return SoftPosPaymentResult(
      success: map['success'] == true,
      cancelled: map['cancelled'] == true,
      message: (map['message'] ?? '').toString(),
      transactionId: map['transaction_id']?.toString(),
      cardScheme: map['card_scheme']?.toString(),
      amount: map['amount'] is num
          ? map['amount'] as num
          : num.tryParse(map['amount']?.toString() ?? ''),
      udid: map['udid']?.toString(),
      gatewayResponse: _map(map['gateway_response']),
      cardName: map['card_name']?.toString(),
      cardNumber: map['card_number']?.toString(),
      tid: map['tid']?.toString(),
      qrCode: map['qr_code']?.toString(),
      isApproved: _bool(map['is_approved']),
    );
  }

  Map<String, dynamic> toOfficialPosPayload({
    required Object? userId,
    required String awb,
    required int requestedAmountHalalas,
  }) {
    final officialAmount = amount ?? requestedAmountHalalas;
    return <String, dynamic>{
      'card_scheme': cardScheme ?? '',
      'user_id': userId,
      'amount': officialAmount,
      'udid': udid ?? '',
      'gateway_response': jsonEncode(gatewayResponse),
      'card_name': cardName ?? '',
      'card_number': cardNumber ?? '',
      'tid': tid ?? transactionId ?? '',
      'qr_code': qrCode ?? '',
      'is_approved': isApproved ?? success,
      'message': 'Payment Success',
      'awbs': awb,
    };
  }
}

/// Android bridge for NearPay/SoftPOS.
///
/// The native side must return the receipt fields used by the official SLS
/// `/orders/bulk/pos` request. A payment is not considered collected until
/// both NearPay and the SLS POS endpoint succeed.
class SoftPosService {
  static const MethodChannel _channel =
      MethodChannel('sls_assistant_pro/softpos');

  Future<SoftPosPaymentResult> purchase({
    required int amountHalalas,
    required String orderReference,
  }) async {
    if (amountHalalas <= 0) {
      debugPrint('SoftPosService: purchase rejected - amount $amountHalalas is <= 0');
      return const SoftPosPaymentResult(
        success: false,
        cancelled: false,
        message: 'مبلغ الدفع غير صالح.',
      );
    }

    try {
      debugPrint('Nearpay purchase started');
      final result = await _channel.invokeMapMethod<dynamic, dynamic>(
        'purchase',
        <String, dynamic>{
          'amount_halalas': amountHalalas,
          'order_reference': orderReference,
        },
      );
      if (result == null) {
        debugPrint('Nearpay purchase result: null');
        return const SoftPosPaymentResult(
          success: false,
          cancelled: false,
          message: 'لم ترجع خدمة SoftPOS نتيجة دفع.',
        );
      }
      final posResult = SoftPosPaymentResult.fromMap(result);
      debugPrint('Nearpay purchase result: success=${posResult.success}, cancelled=${posResult.cancelled}');
      return posResult;
    } on PlatformException catch (error) {
      debugPrint('Nearpay error type: ${error.code}');
      debugPrint('Nearpay error message: ${error.message}');
      return SoftPosPaymentResult(
        success: false,
        cancelled: error.code == 'cancelled',
        message: error.message ?? 'تعذر تشغيل SoftPOS.',
      );
    } on MissingPluginException {
      debugPrint('Nearpay error: MissingPluginException');
      return const SoftPosPaymentResult(
        success: false,
        cancelled: false,
        message: 'تكامل SoftPOS غير مهيأ في نسخة Android الحالية.',
      );
    }
  }
}
