import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task_item.dart';
import 'account_store.dart';

/// The last task list and status choices read from SLS, kept on the phone
/// so the app works in offline mode.
class OfflineCache {
  OfflineCache._();

  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/offline_${name}_${AccountStore.currentAccountId}.json');
  }

  static Future<void> saveTasks(List<TaskItem> tasks) async {
    try {
      final file = await _file('tasks');
      await file.writeAsString(jsonEncode([for (final t in tasks) t.raw]));
    } catch (error) {
      debugPrint('Offline cache: saving tasks failed: $error');
    }
  }

  static Future<List<TaskItem>> loadTasks() async {
    try {
      final file = await _file('tasks');
      if (!await file.exists()) return const [];
      final rows = jsonDecode(await file.readAsString()) as List;
      return [
        for (final row in rows.whereType<Map>())
          TaskItem.fromJson(Map<String, dynamic>.from(row)),
      ];
    } catch (error) {
      debugPrint('Offline cache: reading tasks failed: $error');
      return const [];
    }
  }

  /// Status choices depend on the shipment's current status and type.
  static String statusKey(TaskItem task) =>
      '${task.isRvp}|${task.statusId ?? task.statusCode}';

  static Future<void> saveStatusOptions(
    String key,
    List<Map<String, dynamic>> options,
  ) async {
    if (options.isEmpty) return;
    try {
      final file = await _file('statuses');
      final all = await _readStatuses(file);
      all[key] = options;
      await file.writeAsString(jsonEncode(all));
    } catch (error) {
      debugPrint('Offline cache: saving statuses failed: $error');
    }
  }

  static Future<List<Map<String, dynamic>>> loadStatusOptions(
    String key,
  ) async {
    try {
      final all = await _readStatuses(await _file('statuses'));
      final list = all[key];
      if (list is! List) return const [];
      return [
        for (final item in list.whereType<Map>())
          Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>> _readStatuses(File file) async {
    if (!await file.exists()) return {};
    final value = jsonDecode(await file.readAsString());
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }
}
