import 'package:flutter_test/flutter_test.dart';
import 'package:serdabvpn/config.dart';

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
  test('parses what serdab add prints', () {
    final c = WgConfig.parse(sample);
    expect(c.ip, '10.7.0.3');
    expect(c.host, '203.0.113.9');
    expect(c.endpoint, '203.0.113.9:51820');
    expect(c.peerPublicKey, 'U+W8fypUdC8ClVLZL1JLz3ob65qGe9yBwN5REOao6nk=');
    expect(c.dns, '1.1.1.1, 1.0.0.1');
    expect(c.raw, sample.trim());
  });

  test('refuses text that is not one interface and one peer', () {
    expect(() => WgConfig.parse('hello'), throwsFormatException);
    expect(
      () => WgConfig.parse(sample.replaceAll('PrivateKey', 'Key')),
      throwsFormatException,
    );
    expect(
      () => WgConfig.parse(sample.replaceAll('Endpoint', 'Ep')),
      throwsFormatException,
    );
    expect(
      () => WgConfig.parse('$sample\n[Peer]\nPublicKey = x\nEndpoint = y:1'),
      throwsFormatException,
    );
  });

  test('refuses keys the engines would refuse', () {
    expect(
      () => WgConfig.parse(
        sample.replaceAll('PersistentKeepalive', 'Persistent keep alive'),
      ),
      throwsFormatException,
    );
    expect(
      () => WgConfig.parse(sample.replaceAll('MTU = 1380', 'PostUp = echo hi')),
      throwsFormatException,
    );
  });

  test('ignores comments and odd casing', () {
    final c = WgConfig.parse(
      '[interface]\nprivatekey = a # mine\naddress = 10.0.0.2/32\n[PEER]\npublickey = b\nendpoint = host.example:443',
    );
    expect(c.host, 'host.example');
    expect(c.ip, '10.0.0.2');
  });
}
