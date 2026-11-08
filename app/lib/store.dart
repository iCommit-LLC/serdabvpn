import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The private key lives here and nowhere else: the iOS Keychain or the
/// Android keystore-backed store, never plain preferences.
class Store {
  static const _s = FlutterSecureStorage();
  static const _config = 'config';
  static const _label = 'label';
  static const _alwaysOn = 'alwaysOn';

  static Future<String?> config() => _s.read(key: _config);
  static Future<String?> label() => _s.read(key: _label);

  /// "Stay underground": connect by itself when the app opens and come back
  /// after a restart. On by default, because the person holding the phone
  /// should not have to think about it.
  static Future<bool> alwaysOn() async =>
      (await _s.read(key: _alwaysOn)) != 'false';

  static Future<void> setAlwaysOn(bool v) =>
      _s.write(key: _alwaysOn, value: v ? 'true' : 'false');

  static Future<void> save(String config, {String? label}) async {
    await _s.write(key: _config, value: config);
    if (label != null) await _s.write(key: _label, value: label);
  }

  static Future<void> rename(String label) =>
      _s.write(key: _label, value: label);

  static Future<void> forget() async {
    await _s.delete(key: _config);
    await _s.delete(key: _label);
    await _s.delete(key: _alwaysOn);
  }
}
