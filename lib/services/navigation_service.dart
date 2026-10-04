import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_item.dart';
import 'location_correction_service.dart';

class NavigationService {
  NavigationService._();

  /// Opens the customer's location in the maps app. A location the driver
  /// corrected on this device always wins over the server coordinates.
  static Future<bool> openTask(TaskItem task) async {
    final effective = await LocationCorrectionService.effectiveLocation(task);
    if (effective != null) {
      return openLocation(effective, label: _label(task));
    }

    final address = task.address.trim();
    if (address.isEmpty) return false;
    return _launchFirst([
      Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': address,
      }),
    ]);
  }

  /// Drops a pin at [location] in the maps app.
  static Future<bool> openLocation(
    CorrectedLocation location, {
    String label = '',
  }) {
    final coordinates = '${location.latitude},${location.longitude}';
    final name = label.trim();
    final candidates = <Uri>[];

    if (defaultTargetPlatform == TargetPlatform.android) {
      // "q=lat,lng(label)" pins the exact coordinates; a plain text query
      // would make Maps search and could land on a different place.
      final query = name.isEmpty ? coordinates : '$coordinates($name)';
      candidates.add(
        Uri.parse('geo:$coordinates?q=${Uri.encodeComponent(query)}'),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      candidates.add(
        Uri.parse(
          'comgooglemaps://?q=$coordinates&center=$coordinates&zoom=17',
        ),
      );
      // With "ll", Apple Maps uses "q" only as the pin label.
      candidates.add(
        Uri.https('maps.apple.com', '/', <String, String>{
          'll': coordinates,
          'q': name.isEmpty ? coordinates : name,
        }),
      );
    }
    candidates.add(
      Uri.https('www.google.com', '/maps/search/', <String, String>{
        'api': '1',
        'query': coordinates,
      }),
    );
    return _launchFirst(candidates);
  }

  static String _label(TaskItem task) {
    final name = task.customerName.trim();
    if (name.isNotEmpty) return name;
    return task.displayReference.trim();
  }

  static Future<bool> _launchFirst(List<Uri> candidates) async {
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
