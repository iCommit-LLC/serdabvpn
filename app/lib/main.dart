import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config.dart';
import 'invite.dart';
import 'l10n.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'store.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Palette.bg,
    ),
  );
  runApp(const SerdabApp());
}

/// Makes an invitation this phone's server: saves it, then shows the door and
/// opens it. Every way in (link, paste, QR) ends here.
Future<void> adopt(Invite invite) async {
  final label = invite.name ?? invite.config.host;
  await Store.save(invite.config.raw, label: label);
  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) =>
          HomeScreen(config: invite.config, label: label, autoConnect: true),
    ),
    (_) => false,
  );
}

void complain(String message) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class SerdabApp extends StatefulWidget {
  const SerdabApp({super.key});

  @override
  State<SerdabApp> createState() => _SerdabAppState();
}

class _SerdabAppState extends State<SerdabApp> {
  final _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _lastLink;

  @override
  void initState() {
    super.initState();
    // Depending on the version, the stream may or may not replay the link the
    // app was opened with; ask for both and ignore the duplicate.
    _links.getInitialLink().then((u) => u == null ? null : _onLink(u));
    _sub = _links.uriLinkStream.listen(_onLink);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onLink(Uri uri) async {
    final text = uri.toString();
    if (text == _lastLink) return;
    _lastLink = text;
    try {
      final invite = Invite.parseLink(text);
      if (invite != null) await adopt(invite);
    } on FormatException catch (e) {
      _notAnInvite(e.message);
    }
  }

  // Synchronous on purpose: reads the context fresh, no async gap.
  void _notAnInvite(String why) {
    final ctx = navigatorKey.currentContext;
    complain(ctx == null ? why : S.of(ctx).notAnInvite(why));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serdab',
      debugShowCheckedModeBanner: false,
      theme: serdabTheme(),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      supportedLocales: S.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Gate(),
    );
  }
}

/// Decides between the first-launch screen and the door.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([Store.config(), Store.label()]),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold();
        final [config, label] = snap.data!;
        if (config == null) return const OnboardingScreen();
        try {
          final parsed = WgConfig.parse(config);
          return HomeScreen(config: parsed, label: label ?? parsed.host);
        } on FormatException {
          return const OnboardingScreen();
        }
      },
    );
  }
}
