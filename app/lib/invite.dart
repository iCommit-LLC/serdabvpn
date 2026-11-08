import 'dart:convert';

import 'config.dart';

/// The invitation `serdab link <device>` prints:
///
///     serdab://add?c=<base64url of the wg-quick config>&n=<device>
///
/// The whole config rides inside the link, so one tap on a phone that has the
/// app sets it up. It is as secret as the QR: whoever has it, has the key.
class Invite {
  const Invite({required this.config, this.name});

  final WgConfig config;
  final String? name;

  static const scheme = 'serdab';

  static String encode(String config, {String? name}) {
    final c = base64Url.encode(utf8.encode(config.trim())).replaceAll('=', '');
    return Uri(
      scheme: scheme,
      host: 'add',
      queryParameters: {'c': c, if (name != null && name.isNotEmpty) 'n': name},
    ).toString();
  }

  /// Reads one invitation link. Returns null when [text] is not a serdab link
  /// at all; throws [FormatException] when it is one but damaged.
  static Invite? parseLink(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != scheme) return null;
    final c = uri.queryParameters['c'];
    if (c == null || c.isEmpty) {
      throw const FormatException('the link carries no config');
    }
    final String raw;
    try {
      raw = utf8.decode(base64Url.decode(base64Url.normalize(c)));
    } on FormatException {
      throw const FormatException('the link is damaged');
    }
    final name = uri.queryParameters['n'];
    return Invite(
      config: WgConfig.parse(raw),
      name: (name == null || name.isEmpty) ? null : name,
    );
  }

  /// Finds an invitation in whatever was pasted or scanned: a bare link, a
  /// link inside a chat message, or the raw config text itself.
  static Invite? extract(String text) {
    final link = RegExp(r'serdab://[^\s<>"]+').firstMatch(text);
    if (link != null) return parseLink(link.group(0)!);
    // The tappable form sent in chats: https://<dashboard>/join#c=...&n=...
    final join = RegExp(
      r'https://[^\s<>"#]+/join#([^\s<>"]+)',
    ).firstMatch(text);
    if (join != null) return parseLink('$scheme://add?${join.group(1)}');
    final i = text.indexOf(RegExp(r'\[interface\]', caseSensitive: false));
    if (i >= 0) return Invite(config: WgConfig.parse(text.substring(i)));
    return null;
  }
}
