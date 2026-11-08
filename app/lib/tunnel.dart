import 'package:flutter/services.dart';

/// What the engine underneath is doing. Android maps WireGuard's UP/DOWN onto
/// this; iOS maps the system NEVPNStatus.
enum TunnelState { disconnected, connecting, connected, disconnecting, denied }

class TunnelStats {
  const TunnelStats({
    required this.rxBytes,
    required this.txBytes,
    this.lastHandshake,
  });
  final int rxBytes;
  final int txBytes;
  final DateTime? lastHandshake;
}

/// The one platform channel of the app. Both native sides implement the same
/// six calls on top of the official WireGuard libraries.
class Tunnel {
  Tunnel._();
  static final Tunnel instance = Tunnel._();

  static const _methods = MethodChannel('serdab/tunnel');
  static const _events = EventChannel('serdab/tunnel/state');

  Stream<TunnelState>? _states;
  Stream<TunnelState> get states => _states ??= _events
      .receiveBroadcastStream()
      .map((e) => _parse(e as String?))
      .asBroadcastStream();

  /// Android asks the user once to allow a VPN; iOS asks on the first connect.
  Future<bool> prepare() async =>
      await _methods.invokeMethod<bool>('prepare') ?? true;

  /// [alwaysOn] arms the platform's own comeback: Android keeps the config
  /// for the boot receiver and the system's Always-on VPN, iOS turns on
  /// on-demand so the tunnel rises whenever there is a network.
  ///
  /// Without [alwaysOn], the native side closes the door [closeAfterMinutes]
  /// after it opened, with a notification five minutes before ("+1 hour").
  Future<void> connect(
    String wgQuickConfig, {
    required bool alwaysOn,
    int closeAfterMinutes = 0,
  }) => _methods.invokeMethod<void>('connect', {
    'config': wgQuickConfig,
    'alwaysOn': alwaysOn,
    'closeAfterMinutes': closeAfterMinutes,
  });

  /// Moves the auto-close deadline; returns the new one.
  Future<DateTime?> extend({int minutes = 60}) async =>
      _ms(await _methods.invokeMethod<int>('extend', {'minutes': minutes}));

  /// When the door closes by itself, or null when it stays open.
  Future<DateTime?> closeAt() async =>
      _ms(await _methods.invokeMethod<int>('closeAt'));

  /// The warning needs notifications: Android 13+ and iOS ask once.
  Future<void> requestNotifications() =>
      _methods.invokeMethod<void>('requestNotifications');

  static DateTime? _ms(int? ms) =>
      ms == null || ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  /// A deliberate disconnect also disarms the comeback until the next connect,
  /// otherwise iOS on-demand would reopen the door the moment it shut.
  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');

  Future<void> setAlwaysOn(bool enabled) =>
      _methods.invokeMethod<void>('setAlwaysOn', {'enabled': enabled});

  /// Android only: the system's own VPN settings page, where "Always-on VPN"
  /// makes the OS itself start the tunnel at boot, seconds after power-on.
  Future<void> openVpnSettings() =>
      _methods.invokeMethod<void>('openVpnSettings');

  /// Android: another app's VPN is up (an Always-on ExpressVPN, say), which
  /// makes Android refuse ours. Always false on iOS, where VPNs take turns.
  Future<bool> otherVpn() async {
    try {
      return await _methods.invokeMethod<bool>('otherVpn') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<TunnelState> state() async =>
      _parse(await _methods.invokeMethod<String>('state'));

  Future<TunnelStats?> stats() async {
    final m = await _methods.invokeMapMethod<String, dynamic>('stats');
    if (m == null) return null;
    final hs = (m['lastHandshake'] as num?)?.toInt() ?? 0;
    return TunnelStats(
      rxBytes: (m['rxBytes'] as num?)?.toInt() ?? 0,
      txBytes: (m['txBytes'] as num?)?.toInt() ?? 0,
      lastHandshake: hs > 0
          ? DateTime.fromMillisecondsSinceEpoch(hs * 1000)
          : null,
    );
  }

  static TunnelState _parse(String? s) => switch (s) {
    'connected' => TunnelState.connected,
    'connecting' => TunnelState.connecting,
    'disconnecting' => TunnelState.disconnecting,
    'denied' => TunnelState.denied,
    _ => TunnelState.disconnected,
  };
}
