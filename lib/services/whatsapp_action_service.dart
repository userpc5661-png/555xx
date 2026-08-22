import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import '../utils/phone_number_utils.dart';
import '../utils/shipment_field_mapper.dart';

class WhatsAppLaunchResult {
  final bool success;
  final String? message;
  const WhatsAppLaunchResult(this.success, [this.message]);
}

class WhatsAppActionService {
  WhatsAppActionService._();

  static const _greetings = <String>[
    'السلام عليكم {name} 🌹',
    'السلام عليكم ورحمة الله وبركاته {name}',
    'مرحبًا {name} 👋',
    'أهلًا وسهلًا {name}',
    'يا هلا {name}',
    'أهلين {name}',
    'حياك الله {name}',
    'صباح الخير {name} ☀️',
    'مساء الخير {name} 🌷',
    'أسعد الله يومك {name}',
  ];

  static const _closings = <String>[
    'شكرًا لك 🌹',
    'يعطيك العافية.',
    'بارك الله فيك.',
    'شاكر تعاونك.',
    'بانتظار موقعك أو عنوانك الوطني.',
  ];

  static Future<WhatsAppLaunchResult> openForTask(TaskItem task) async {
    final digits = PhoneNumberUtils.whatsappDigits(task.customerPhone);
    if (digits == null) {
      return const WhatsAppLaunchResult(false, 'رقم العميل غير متوفر');
    }

    final message = _buildMessage(task);
    final candidates = <Uri>[
      Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: <String, String>{'phone': digits, 'text': message},
      ),
      Uri.https(
        'api.whatsapp.com',
        '/send',
        <String, String>{'phone': digits, 'text': message},
      ),
      Uri.https(
        'wa.me',
        '/$digits',
        <String, String>{'text': message},
      ),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return const WhatsAppLaunchResult(true);
        }
      } catch (_) {
        // Try the next official WhatsApp deep-link format.
      }
    }
    return const WhatsAppLaunchResult(false, 'تعذر فتح واتساب');
  }

  static String _buildMessage(TaskItem task) {
    final name = task.customerName.trim();
    final store = task.storeName.trim();
    
    final lines = <String>[
      'السلام عليكم${name.isEmpty ? '' : ' $name'}',
      '',
      store.isEmpty 
          ? 'معك مندوب توصيل طلبك.' 
          : 'معك مندوب توصيل طلبك من متجر $store.',
      'رقم الشحنة: ${task.displayReference}',
    ];
    
    final cod = task.codAmount;
    if (task.isCashOnDelivery && cod != null && cod > 0) {
      lines.add('المبلغ المطلوب عند الاستلام: ${ShipmentFieldMapper.formatAmount(cod)} ريال');
    }
    return lines.join('\n');
  }
}
