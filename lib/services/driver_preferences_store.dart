import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/phone_number_utils.dart';
import 'account_store.dart';

class DriverPreferencesStore {
  DriverPreferencesStore._();

  static const _storage = FlutterSecureStorage();
  static final instance = DriverPreferencesStore._();

  String get _whatsAppKey => 'driver_whatsapp_${AccountStore.currentAccountId}';

  Future<String?> readWhatsAppNumber() async {
    final raw = await _storage.read(key: _whatsAppKey);
    return PhoneNumberUtils.normalizeSaudiMobile(raw);
  }

  Future<bool> saveWhatsAppNumber(String input) async {
    final normalized = PhoneNumberUtils.normalizeSaudiMobile(input);
    if (normalized == null) return false;
    await _storage.write(key: _whatsAppKey, value: normalized);
    return true;
  }

  Future<void> clearWhatsAppNumber() => _storage.delete(key: _whatsAppKey);

  static const _satelliteKey = 'map_satellite_v1';

  /// Whether the map opens on the satellite view.
  Future<bool> readSatelliteMap() async {
    try {
      return await _storage.read(key: _satelliteKey) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> saveSatelliteMap(bool on) async {
    try {
      await _storage.write(key: _satelliteKey, value: on ? '1' : '0');
    } catch (_) {}
  }
}
