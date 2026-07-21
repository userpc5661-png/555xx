import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';

class NavigationService {
  NavigationService._();

  static Future<bool> openTask(TaskItem task) async {
    final labelParts = <String>[
      if (task.storeName.trim().isNotEmpty) task.storeName.trim(),
      if (task.customerName.trim().isNotEmpty) task.customerName.trim(),
      if (task.referenceNumber.trim().isNotEmpty) task.referenceNumber.trim(),
    ];
    final label = labelParts.join(' - ');

    final candidates = <Uri>[];
    if (task.hasCoordinates) {
      final destination = '${task.latitude},${task.longitude}';
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Opens turn-by-turn navigation directly in Google Maps when installed.
        candidates.add(Uri.parse('google.navigation:q=$destination&mode=d'));
        candidates.add(
          Uri.parse(
            'geo:${task.latitude},${task.longitude}?q='
            '${Uri.encodeComponent(destination)}'
            '${label.isEmpty ? '' : '(${Uri.encodeComponent(label)})'}',
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        candidates.add(
          Uri.parse(
            'comgooglemaps://?daddr=$destination&directionsmode=driving',
          ),
        );
        candidates.add(
          Uri.parse(
            'https://maps.apple.com/?daddr=${Uri.encodeComponent(destination)}'
            '&dirflg=d',
          ),
        );
      }
      candidates.add(
        Uri.https(
          'www.google.com',
          '/maps/dir/',
          <String, String>{
            'api': '1',
            'destination': destination,
            'travelmode': 'driving',
          },
        ),
      );
    } else {
      final address = task.address.trim();
      if (address.isEmpty) return false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        candidates.add(
          Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}'),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        candidates.add(
          Uri.parse(
            'https://maps.apple.com/?daddr=${Uri.encodeComponent(address)}'
            '&dirflg=d',
          ),
        );
      }
      candidates.add(
        Uri.https(
          'www.google.com',
          '/maps/dir/',
          <String, String>{
            'api': '1',
            'destination': address,
            'travelmode': 'driving',
          },
        ),
      );
    }

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Try the next installed maps application or the web fallback.
      }
    }
    return false;
  }
}
