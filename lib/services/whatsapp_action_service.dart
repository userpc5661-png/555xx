import 'dart:math';

import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import '../utils/phone_number_utils.dart';

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
    final uri = Uri.https(
      'wa.me',
      '/$digits',
      <String, String>{'text': message},
    );

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) return const WhatsAppLaunchResult(false, 'تعذر فتح واتساب');
      return const WhatsAppLaunchResult(true);
    } catch (_) {
      return const WhatsAppLaunchResult(false, 'تعذر فتح واتساب');
    }
  }

  static String _buildMessage(TaskItem task) {
    final random = Random();
    final greetingIndex = random.nextInt(_greetings.length);
    final closingIndex = random.nextInt(_closings.length);

    final name = task.customerName.trim();
    final greeting = _greetings[greetingIndex]
        .replaceAll('{name}', name)
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
    final lines = <String>[
      greeting,
      '',
      'شحنتك من متجر:',
      task.displayStoreName,
      '',
      'رقم الشحنة:',
      task.displayReference,
    ];
    final cod = task.codAmount;
    if (cod != null && cod > 0) {
      lines.addAll(
          ['', 'المبلغ المستحق عند الاستلام:', '${_formatAmount(cod)} ريال']);
    }
    lines.addAll([
      '',
      'فضلاً أرسل موقعك أو عنوانك الوطني لتسهيل عملية التوصيل.',
      '',
      _closings[closingIndex],
    ]);
    return lines.join('\n');
  }

  static String _formatAmount(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
}
