// Screenshots of the home screen without a phone or a VPN:
//   SERDAB_SHOTS=1 flutter test test/visual --update-goldens
// PNGs land in test/visual/shots/. Skipped in normal test runs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serdabvpn/config.dart';
import 'package:serdabvpn/l10n.dart';
import 'package:serdabvpn/screens/home.dart';
import 'package:serdabvpn/theme.dart';

const conf = '''[Interface]
PrivateKey = uOTG7bBMd0iGxCBUmjsVPCKTgicsFOrQCVb3JECTJmE=
Address = 10.7.0.2/32
DNS = 10.7.0.1

[Peer]
PublicKey = 9XLIDKXfCrnpnGbu2AuLwUXp36vdnSsK4RIGC1hZ0VM=
Endpoint = 34.163.198.164:51820
AllowedIPs = 0.0.0.0/0
''';

Future<void> font(String family, String path) async {
  final l = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await l.load();
}

void main() {
  final on = Platform.environment['SERDAB_SHOTS'] == '1';
  setUpAll(() async {
    if (!on) return;
    final sdk = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent.parent.parent.path;
    await font('InstrumentSerif', 'assets/fonts/InstrumentSerif-Regular.ttf');
    await font('Roboto', '/System/Library/Fonts/Supplemental/Arial.ttf');
    await font(
      'MaterialIcons',
      '$sdk/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  });

  for (final (name, connected, size, locale, minutesLeft) in [
    ('shut-iphone16', false, const Size(393, 852), 'en', 0),
    ('open-iphone16', true, const Size(393, 852), 'en', 90),
    ('open-renew-window', true, const Size(393, 852), 'en', 7),
    ('open-iphoneSE', true, const Size(375, 667), 'en', 7),
    ('open-ar', true, const Size(393, 852), 'ar', 7),
  ]) {
    testWidgets(name, skip: !on, (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final m =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final state = connected ? 'connected' : 'disconnected';
      final closeAt = DateTime.now()
          .add(Duration(minutes: minutesLeft, seconds: 30))
          .millisecondsSinceEpoch;
      MockStreamHandlerEventSink? sinkRef;
      m.setMockMethodCallHandler(
        const MethodChannel('serdab/tunnel'),
        (c) async => switch (c.method) {
          'state' => state,
          'closeAt' => connected ? closeAt : null,
          'prepare' => true,
          'stats' => {
            'rxBytes': 26000,
            'txBytes': 18000,
            'lastHandshake': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2,
          },
          _ => null,
        },
      );
      m.setMockStreamHandler(
        const EventChannel('serdab/tunnel/state'),
        MockStreamHandler.inline(
          onListen: (a, sink) {
            sinkRef = sink;
            sink.success(state);
          },
        ),
      );
      final me = jsonEncode({
        'name': 'phone',
        'role': 'owner',
        'canShare': true,
        'monitored': false,
        'autoCloseMinutes': 120,
      });
      m.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (c) async => c.method == 'read' && (c.arguments as Map)['key'] == 'me'
            ? me
            : null,
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: serdabTheme(),
          locale: Locale(locale),
          supportedLocales: S.supported,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: HomeScreen(config: WgConfig.parse(conf), label: 'Paris'),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      if (!connected) sinkRef?.success('disconnected');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(HomeScreen),
        matchesGoldenFile('shots/$name.png'),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
