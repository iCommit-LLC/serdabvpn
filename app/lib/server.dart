import 'dart:convert';
import 'dart:io';

/// What the server says about this device (serdabd `GET /v1/me`).
class Me {
  const Me({
    required this.name,
    required this.role,
    required this.canShare,
    this.expiresAt,
    this.visibleTo,
    this.autoCloseMinutes = 120,
  });

  final String name;
  final String role;
  final bool canShare;
  final DateTime? expiresAt;

  /// Who can see the sites this device visits (null: nobody).
  final String? visibleTo;
  final int autoCloseMinutes;

  bool get isGuest => role == 'guest';
  bool get mayStayOpen => role == 'owner' || role == 'family';
  bool get expired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  static Me? fromJson(Map<String, dynamic>? j) {
    if (j == null || j['name'] is! String) return null;
    final exp = (j['expiresAt'] as num?)?.toInt();
    return Me(
      name: j['name'] as String,
      role: (j['role'] as String?) ?? 'guest',
      canShare: j['canShare'] == true,
      expiresAt: exp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      visibleTo: j['visibleTo'] as String?,
      autoCloseMinutes: (j['autoCloseMinutes'] as num?)?.toInt() ?? 120,
    );
  }
}

class Invitation {
  const Invitation(this.name, this.link, this.expiresAt);
  final String name;
  final String link;
  final DateTime? expiresAt;
}

class ServerError implements Exception {
  const ServerError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// serdabd's device API. It only exists inside the tunnel, at the server's
/// tunnel address: the source address of the request is the device's identity,
/// so there is no password. Plain HTTP is fine here, the tunnel encrypts it.
class Server {
  Server._();
  static final Server instance = Server._();

  static const _base = 'http://10.7.0.1:8800';
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Object? body,
  ]) async {
    final req = await _http.openUrl(method, Uri.parse('$_base$path'));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 8));
    final text = await res.transform(utf8.decoder).join();
    final j = (text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map)
        .cast<String, dynamic>();
    if (res.statusCode >= 400) {
      throw ServerError((j['error'] as String?) ?? 'HTTP ${res.statusCode}');
    }
    return j;
  }

  /// Null when the server cannot be reached (tunnel down, old server).
  Future<Map<String, dynamic>?> me() async {
    try {
      return await _call('GET', '/v1/me');
    } on Exception {
      return null;
    }
  }

  Future<Invitation> invite(String name) async {
    final j = await _call('POST', '/v1/invites', {'name': name});
    final exp = (j['expiresAt'] as num?)?.toInt();
    return Invitation(
      j['name'] as String,
      j['link'] as String,
      exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
    );
  }

  Future<List<Map<String, dynamic>>> invites() async {
    final j = await _call('GET', '/v1/invites');
    return ((j['invites'] as List?) ?? const [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }
}
