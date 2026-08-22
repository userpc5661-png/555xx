import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';

class NavigationService {
  NavigationService._();

  static Future<bool> openTask(TaskItem task) async {
    final query = task.hasCoordinates
        ? '${task.latitude},${task.longitude}'
        : task.address.trim();
    if (query.isEmpty) return false;

    final candidates = <Uri>[
      Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': query,
      }),
    ];
    if (defaultTargetPlatform == TargetPlatform.android && task.hasCoordinates) {
      candidates.insert(0, Uri.parse('geo:${task.latitude},${task.longitude}?q=${Uri.encodeComponent(query)}'));
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      candidates.insert(0, Uri.parse('comgooglemaps://?q=${Uri.encodeComponent(query)}'));
    }

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
      } catch (_) {}
    }
    return false;
  }
}
