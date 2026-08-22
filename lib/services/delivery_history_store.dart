import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/task_item.dart';

class DeliveryHistoryRecord {
  final String awb;
  final String customerName;
  final double codAmount;
  final bool collected;
  final DateTime completedAt;

  const DeliveryHistoryRecord({
    required this.awb,
    required this.customerName,
    required this.codAmount,
    required this.collected,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'awb': awb,
        'customer_name': customerName,
        'cod_amount': codAmount,
        'collected': collected,
        'completed_at': completedAt.toIso8601String(),
      };

  factory DeliveryHistoryRecord.fromJson(Map<String, dynamic> json) {
    return DeliveryHistoryRecord(
      awb: (json['awb'] ?? '').toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      codAmount: (json['cod_amount'] is num)
          ? (json['cod_amount'] as num).toDouble()
          : double.tryParse((json['cod_amount'] ?? '').toString()) ?? 0,
      collected: json['collected'] == true,
      completedAt: DateTime.tryParse((json['completed_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DeliveryHistoryStore {
  DeliveryHistoryStore._();
  static final instance = DeliveryHistoryStore._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'sls_delivery_history_v1';

  String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<List<DeliveryHistoryRecord>> today() async {
    final all = await _readAll();
    final today = _dayKey(DateTime.now());
    return all.where((record) => _dayKey(record.completedAt) == today).toList();
  }

  Future<void> recordCompleted(TaskItem task, {required String awb}) async {
    final normalizedAwb = awb.trim().isNotEmpty ? awb.trim() : task.displayReference;
    final all = await _readAll();
    all.removeWhere((record) => record.awb == normalizedAwb);
    all.add(DeliveryHistoryRecord(
      awb: normalizedAwb,
      customerName: task.customerName,
      codAmount: task.codAmount ?? 0,
      collected: task.isCashOnDelivery && (task.codAmount ?? 0) > 0,
      completedAt: DateTime.now(),
    ));

    final cutoff = DateTime.now().subtract(const Duration(days: 45));
    all.removeWhere((record) => record.completedAt.isBefore(cutoff));
    await _storage.write(
      key: _key,
      value: jsonEncode(all.map((record) => record.toJson()).toList()),
    );
  }

  Future<List<DeliveryHistoryRecord>> _readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) return <DeliveryHistoryRecord>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <DeliveryHistoryRecord>[];
      return decoded
          .whereType<Map>()
          .map((item) => DeliveryHistoryRecord.fromJson(
              Map<String, dynamic>.from(item)))
          .where((record) => record.awb.isNotEmpty)
          .toList();
    } catch (_) {
      return <DeliveryHistoryRecord>[];
    }
  }
}
