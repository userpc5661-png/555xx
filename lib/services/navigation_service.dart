import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import 'location_correction_service.dart';

class NavigationService {
  NavigationService._();

  static Future<bool> openTask(TaskItem task) async {
    final effective = await LocationCorrectionService.effectiveLocation(task);
    final destination = effective != null
        ? '${effective.latitude},${effective.longitude}'
        : task.address.trim();
    if (destination.isEmpty) return false;

    final candidates = <Uri>[];

    if (effective != null) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        candidates.add(
          Uri.parse('google.navigation:q=${effective.latitude},${effective.longitude}'),
        );
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        candidates.add(
          Uri.parse('comgooglemaps://?daddr=${effective.latitude},${effective.longitude}&directionsmode=driving'),
        );
        candidates.add(
          Uri.parse('https://maps.apple.com/?daddr=${effective.latitude},${effective.longitude}&dirflg=d'),
        );
      }
      // Universal Google Maps directions URL (direct driving navigation mode)
      candidates.add(
        Uri.https('www.google.com', '/maps/dir/', <String, String>{
          'api': '1',
          'destination': destination,
          'travelmode': 'driving',
        }),
      );
    } else {
      // Fallback for address text search if no coordinates exist
      candidates.add(
        Uri.https('www.google.com', '/maps/dir/', <String, String>{
          'api': '1',
          'destination': destination,
          'travelmode': 'driving',
        }),
      );
      candidates.add(
        Uri.https('www.google.com', '/maps/search/', <String, String>{
          'api': '1',
          'query': destination,
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
