import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import '../utils/phone_number_utils.dart';
import 'driver_preferences_store.dart';

class SmsLaunchResult {
  final bool success;
  final String? message;
  const SmsLaunchResult(this.success, [this.message]);
}

class SmsActionService {
  SmsActionService._();

  static const _channel = MethodChannel('sls_assistant_pro/sms');

  static Future<SmsLaunchResult> openForTask(TaskItem task) async {
    final customerNumber = PhoneNumberUtils.normalizeSaudiMobile(
      task.customerPhone,
    );
    if (customerNumber == null) {
      return const SmsLaunchResult(false, 'رقم العميل غير صالح');
    }

    final driverNumber = await DriverPreferencesStore.instance
        .readWhatsAppNumber();
    if (driverNumber == null) {
      return const SmsLaunchResult(
        false,
        'أضف رقم واتساب المندوب من الإعدادات أولاً.',
      );
    }

    final message = buildMessage(task, driverNumber);
    try {
      final opened =
          await _channel.invokeMethod<bool>('compose', {
            'recipient': customerNumber,
            'body': message,
          }) ??
          false;
      return opened
          ? const SmsLaunchResult(true)
          : const SmsLaunchResult(false, 'تعذر فتح تطبيق الرسائل');
    } on MissingPluginException {
      return _openWithSmsUri(customerNumber, message);
    } on PlatformException catch (error) {
      return SmsLaunchResult(false, error.message ?? 'تعذر فتح تطبيق الرسائل');
    } catch (_) {
      return const SmsLaunchResult(false, 'تعذر فتح تطبيق الرسائل');
    }
  }

  static Future<SmsLaunchResult> _openWithSmsUri(
    String customerNumber,
    String message,
  ) async {
    final encodedBody = Uri.encodeComponent(message);
    final uri = Uri.parse('sms:$customerNumber?body=$encodedBody');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return opened
          ? const SmsLaunchResult(true)
          : const SmsLaunchResult(false, 'تعذر فتح تطبيق الرسائل');
    } catch (_) {
      return const SmsLaunchResult(false, 'تعذر فتح تطبيق الرسائل');
    }
  }

  static String buildMessage(TaskItem task, String driverPhone) {
    final driverDigits = PhoneNumberUtils.whatsappDigits(driverPhone);
    final awb = task.realAwb.trim().isNotEmpty
        ? task.realAwb.trim()
        : task.displayReference.trim();
    final store = task.displayStoreName.trim();
    final lines = <String>[
      'السلام عليكم${task.customerName.trim().isEmpty ? '' : ' ${task.customerName.trim()}'}،',
      store.isEmpty
          ? 'لديك شحنة للتوصيل.'
          : 'لديك شحنة للتوصيل من متجر $store.',
      'رقم الشحنة: $awb',
      'فضلاً أرسل عنوانك الوطني أو شارك موقعك مع المندوب عبر واتساب:',
      if (driverDigits != null) 'https://wa.me/$driverDigits',
    ];
    return lines.join('\n');
  }
}
