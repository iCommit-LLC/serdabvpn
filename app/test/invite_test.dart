import 'package:flutter_test/flutter_test.dart';
import 'package:serdabvpn/invite.dart';

const sample = '''
[Interface]
PrivateKey = uOTG7bBMd0iGxCBUmjsVPCKTgicsFOrQCVb3JECTJmE=
Address = 10.7.0.3/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1380

[Peer]
PublicKey = U+W8fypUdC8ClVLZL1JLz3ob65qGe9yBwN5REOao6nk=
PresharedKey = 6yNppTCsd/VF7U8b+KLVltWEaNfhQSVhFfr9T99mYvE=
Endpoint = 203.0.113.9:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';

void main() {
  test('a link carries the whole config and the device name', () {
    final link = Invite.encode(sample, name: 'mom');
    expect(link, startsWith('serdab://add?c='));
    expect(link, isNot(contains('=\n')));
    final back = Invite.parseLink(link)!;
    expect(back.name, 'mom');
    expect(back.config.raw, sample.trim());
    expect(back.config.host, '203.0.113.9');
  });

  test('matches what the server CLI prints (base64url, no padding)', () {
    // `serdab link` does: base64 -w0 | tr '+/' '-_' | tr -d '='
    final link = Invite.encode('[Interface]\nPrivateKey = a\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = b\nEndpoint = h:1');
    final c = Uri.parse(link).queryParameters['c']!;
    expect(c, isNot(contains('=')));
    expect(c, isNot(contains('+')));
    expect(c, isNot(contains('/')));
    expect(Invite.parseLink(link)!.config.host, 'h');
  });

  test('finds the link inside a chat message', () {
    final link = Invite.encode(sample, name: 'mom');
    final msg = 'Mama, tap this and then tap the door 🙂\n$link\nlove you';
    expect(Invite.extract(msg)!.name, 'mom');
  });

  test('accepts the raw config too, with chatter before it', () {
    final i = Invite.extract('here is your file:\n$sample')!;
    expect(i.name, isNull);
    expect(i.config.ip, '10.7.0.3');
  });

  test('says no to text that is neither', () {
    expect(Invite.extract('hello mom'), isNull);
    expect(Invite.parseLink('https://example.com/?c=abc'), isNull);
  });

  test('complains about a damaged or empty link', () {
    expect(() => Invite.parseLink('serdab://add'), throwsFormatException);
    expect(() => Invite.parseLink('serdab://add?c=%%%'), throwsFormatException);
    expect(
      () => Invite.parseLink('serdab://add?c=aGVsbG8'), // "hello"
      throwsFormatException,
    );
  });
}
