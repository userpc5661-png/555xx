import 'package:flutter/foundation.dart';

import '../models/task_item.dart';

/// A request to show one shipment on the in-app map.
class MapFocusRequest {
  final TaskItem task;
  const MapFocusRequest(this.task);
}

/// Lets any screen ask the home screen to open the Map tab centred on a
/// shipment. Each call is a new request object, so asking for the same
/// shipment twice still notifies listeners.
class MapFocusService {
  MapFocusService._();

  static final ValueNotifier<MapFocusRequest?> requests =
      ValueNotifier<MapFocusRequest?>(null);

  static void show(TaskItem task) => requests.value = MapFocusRequest(task);
}
