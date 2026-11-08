import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The private key lives here and nowhere else: the iOS Keychain or the
/// Android keystore-backed store, never plain preferences.
class Store {
  static const _s = FlutterSecureStorage();
  static const _config = 'config';
  static const _label = 'label';
  static const _alwaysOn = 'alwaysOn';
  static const _me = 'me';

  static Future<String?> config() => _s.read(key: _config);
  static Future<String?> label() => _s.read(key: _label);

  /// "Stay underground": connect by itself when the app opens, come back
  /// after a restart, never close by itself. Off by default: the door opens
  /// when the app opens and closes two hours later (calls, then done).
  static Future<bool> alwaysOn() async =>
      (await _s.read(key: _alwaysOn)) == 'true';

  /// The server's last word about this device (`GET /v1/me`), kept for when
  /// the tunnel is down: role, sharing, access end, who sees the history.
  static Future<Map<String, dynamic>?> me() async {
    final raw = await _s.read(key: _me);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on FormatException {
      return null;
    }
  }

  static Future<void> setMe(Map<String, dynamic> me) =>
      _s.write(key: _me, value: jsonEncode(me));

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
    await _s.delete(key: _me);
  }
}
