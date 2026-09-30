import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import 'location_correction_service.dart';

class NavigationService {
  NavigationService._();

  static Future<bool> openTask(TaskItem task) async {
    final effective = await LocationCorrectionService.effectiveLocation(task);
    final query = effective != null
        ? '${effective.latitude},${effective.longitude}'
        : task.address.trim();
    if (query.isEmpty) return false;

    final candidates = <Uri>[];

    if (effective != null) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        candidates.add(
          Uri.parse('geo:${effective.latitude},${effective.longitude}?q=${Uri.encodeComponent(query)}'),
        );
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        candidates.add(
          Uri.parse('comgooglemaps://?q=${Uri.encodeComponent(query)}'),
        );
        candidates.add(
          Uri.parse('https://maps.apple.com/?q=${Uri.encodeComponent(task.customerName.isEmpty ? query : task.customerName)}&ll=${effective.latitude},${effective.longitude}'),
        );
      }
      // Universal Google Maps search pin location URL
      candidates.add(
        Uri.https('www.google.com', '/maps/search/', <String, String>{
          'api': '1',
          'query': query,
        }),
      );
    } else {
      candidates.add(
        Uri.https('www.google.com', '/maps/search/', <String, String>{
          'api': '1',
          'query': query,
        }),
      );
    }

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
