import 'package:url_launcher/url_launcher.dart';

import '../utils/phone_number_utils.dart';

class PhoneActionService {
  PhoneActionService._();

  static Future<bool> call(String? rawPhone) async {
    final uri = PhoneNumberUtils.callUri(rawPhone);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openWhatsApp(String? rawPhone) async {
    for (final uri in PhoneNumberUtils.whatsappUris(rawPhone)) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Try the next native/web WhatsApp candidate.
      }
    }
    return false;
  }
}
