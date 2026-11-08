/// A wg-quick config exactly as `serdab add` prints it in the QR.
///
/// The raw text goes to the WireGuard engine untouched; we only pull out the
/// few fields the screens show and refuse anything that is not one interface
/// and one peer.
class WgConfig {
  WgConfig._(
    this.raw,
    this.address,
    this.endpoint,
    this.peerPublicKey,
    this.dns,
  );

  final String raw;
  final String address; // 10.7.0.2/32
  final String endpoint; // 34.155.1.2:51820
  final String peerPublicKey;
  final String dns;

  String get host {
    final i = endpoint.lastIndexOf(':');
    return i < 0 ? endpoint : endpoint.substring(0, i);
  }

  String get ip => address.split('/').first;

  /// The keys both engines accept. wireguard-android and WireGuardKit refuse a
  /// config with anything else, so we refuse it first, with a readable reason.
  static const _interfaceKeys = {
    'privatekey',
    'address',
    'dns',
    'mtu',
    'listenport',
  };
  static const _peerKeys = {
    'publickey',
    'presharedkey',
    'allowedips',
    'endpoint',
    'persistentkeepalive',
  };

  static WgConfig parse(String text) {
    final t = text.trim();
    String? section;
    final iface = <String, String>{};
    final peer = <String, String>{};
    var peers = 0;
    for (final rawLine in t.split('\n')) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[')) {
        section = line.toLowerCase();
        if (section == '[peer]') peers++;
        if (section != '[interface]' && section != '[peer]') {
          throw FormatException('unknown section $line');
        }
        continue;
      }
      final eq = line.indexOf('=');
      if (eq < 0) throw FormatException('not a "key = value" line: $line');
      final k = line.substring(0, eq).trim().toLowerCase();
      final v = line.substring(eq + 1).trim();
      switch (section) {
        case '[interface]':
          if (!_interfaceKeys.contains(k)) {
            throw FormatException('unknown key in [Interface]: $k');
          }
          iface[k] = v;
        case '[peer]':
          if (!_peerKeys.contains(k)) {
            throw FormatException('unknown key in [Peer]: $k');
          }
          peer[k] = v;
        default:
          throw FormatException('line before any section: $line');
      }
    }
    if (iface['privatekey'] == null) {
      throw const FormatException('no PrivateKey in [Interface]');
    }
    if (iface['address'] == null) {
      throw const FormatException('no Address in [Interface]');
    }
    if (peers != 1) throw FormatException('expected one [Peer], found $peers');
    if (peer['publickey'] == null) {
      throw const FormatException('no PublicKey in [Peer]');
    }
    if (peer['endpoint'] == null) {
      throw const FormatException('no Endpoint in [Peer]');
    }
    return WgConfig._(
      t,
      iface['address']!,
      peer['endpoint']!,
      peer['publickey']!,
      iface['dns'] ?? '',
    );
  }
}
