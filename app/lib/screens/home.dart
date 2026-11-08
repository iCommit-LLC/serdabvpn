import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../invite.dart';
import '../l10n.dart';
import '../main.dart';
import '../store.dart';
import '../theme.dart';
import '../tunnel.dart';
import '../ui/arch.dart';
import 'onboarding.dart';
import 'scan.dart';

/// One door. Tap it to go underground, tap it again to come back up.
///
/// With "stay underground" on (the default) the door opens by itself when the
/// screen appears, so the person holding the phone never has to.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.config,
    required this.label,
    this.autoConnect = false,
  });

  final WgConfig config;
  final String label;

  /// True right after an invitation was taken: open the door now.
  final bool autoConnect;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tunnel = Tunnel.instance;
  late final WgConfig _config = widget.config;
  late String _label = widget.label;
  TunnelState _state = TunnelState.disconnected;
  TunnelStats? _stats;
  DateTime? _since;
  StreamSubscription<TunnelState>? _sub;
  Timer? _tick;
  int _ticks = 0;
  bool _alwaysOn = true;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    _sub = _tunnel.states.listen(_onState, onError: (_) {});
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _start();
  }

  Future<void> _start() async {
    _alwaysOn = await Store.alwaysOn();
    TunnelState s;
    try {
      s = await _tunnel.state();
    } on PlatformException {
      s = TunnelState.disconnected;
    }
    if (!mounted) return;
    _onState(s);
    if (!_autoTried &&
        (widget.autoConnect || _alwaysOn) &&
        s == TunnelState.disconnected) {
      _autoTried = true;
      await _toggle();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _onState(TunnelState s) {
    if (!mounted) return;
    setState(() {
      if (s == TunnelState.connected && _state != TunnelState.connected) {
        _since = DateTime.now();
      }
      if (s != TunnelState.connected) {
        _since = null;
        _stats = null;
      }
      _state = s;
    });
  }

  Future<void> _onTick() async {
    if (_state != TunnelState.connected) return;
    _ticks++;
    if (_ticks % 2 == 0) {
      final s = await _tunnel.stats();
      if (mounted && s != null) setState(() => _stats = s);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.mediumImpact();
    try {
      if (_state == TunnelState.connected || _state == TunnelState.connecting) {
        await _tunnel.disconnect();
      } else {
        if (!await _tunnel.prepare()) {
          _onState(TunnelState.denied);
          return;
        }
        _onState(TunnelState.connecting);
        await _tunnel.connect(_config.raw, alwaysOn: _alwaysOn);
      }
    } on PlatformException catch (e) {
      _onState(await _tunnel.state());
      complain(e.message ?? e.code);
    }
  }

  Future<void> _setAlwaysOn(bool v) async {
    setState(() => _alwaysOn = v);
    await Store.setAlwaysOn(v);
    try {
      await _tunnel.setAlwaysOn(v);
    } on PlatformException catch (e) {
      complain(e.message ?? e.code);
    }
  }

  Future<void> _rescan() async {
    final invite = await Navigator.of(
      context,
    ).push<Invite>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (invite == null || !mounted) return;
    if (_state != TunnelState.disconnected) await _tunnel.disconnect();
    await adopt(invite);
  }

  Future<void> _rename() async {
    final s = S.of(context);
    final c = TextEditingController(text: _label);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.callThisServer),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Paris'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(s.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await Store.rename(name);
    if (mounted) setState(() => _label = name);
  }

  Future<void> _forget() async {
    final s = S.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.forgetTitle),
        content: Text('${s.forgetBody}\nsudo serdab rm <device>'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.keep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Palette.danger),
            child: Text(s.forget),
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (_state != TunnelState.disconnected) await _tunnel.disconnect();
    await Store.forget();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  /// WireGuard has no "connected" event: the interface is up the moment you ask.
  /// The handshake is the only proof the server answered, so after a few
  /// seconds without one we say so instead of pretending.
  bool get _unanswered =>
      _state == TunnelState.connected &&
      _stats?.lastHandshake == null &&
      _since != null &&
      DateTime.now().difference(_since!).inSeconds > 8;

  (String, String) _words(S s) => switch (_state) {
    TunnelState.connected when _unanswered => (
      s.noAnswer,
      s.noAnswerSub(_config.host, _config.endpoint.split(':').last),
    ),
    TunnelState.connected => (s.underground, s.leavesThrough(_label)),
    TunnelState.connecting => (s.opening, s.knocking(_config.host)),
    TunnelState.disconnecting => (s.comingUp, ''),
    TunnelState.denied => (s.denied, s.deniedSub),
    TunnelState.disconnected => (s.shut, s.shutSub),
  };

  String get _clock {
    final s = _since;
    if (s == null) return '';
    final d = DateTime.now().difference(s);
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = S.of(context);
    final (title, sub) = _words(s);
    final size = (MediaQuery.sizeOf(context).shortestSide * 0.7).clamp(
      200.0,
      300.0,
    );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('serdab', style: text.displayMedium),
                  const Spacer(),
                  _Chip(label: _label, onTap: _rename),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArchButton(state: _state, onTap: _toggle, size: size),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          key: ValueKey((_state, _unanswered)),
                          children: [
                            Text(
                              title,
                              style: text.displayMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              sub,
                              style: text.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_state == TunnelState.connected)
                _StatsRow(stats: _stats, clock: _clock)
              else
                _DeviceCard(
                  config: _config,
                  alwaysOn: _alwaysOn,
                  onAlwaysOn: _setAlwaysOn,
                  onRescan: _rescan,
                  onForget: _forget,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.public, size: 14, color: Palette.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: Palette.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.clock});

  final TunnelStats? stats;
  final String clock;

  static String bytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final hs = stats?.lastHandshake;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          _Cell(s.statUnderground, clock),
          _Cell(s.statDown, bytes(stats?.rxBytes ?? 0)),
          _Cell(s.statUp, bytes(stats?.txBytes ?? 0)),
          _Cell(
            s.statHandshake,
            hs == null ? '—' : s.ago(DateTime.now().difference(hs).inSeconds),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.titleMedium!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: text.bodySmall!.copyWith(fontSize: 11, letterSpacing: 0.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.config,
    required this.alwaysOn,
    required this.onAlwaysOn,
    required this.onRescan,
    required this.onForget,
  });

  final WgConfig config;
  final bool alwaysOn;
  final ValueChanged<bool> onAlwaysOn;
  final VoidCallback onRescan;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = S.of(context);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(k, style: text.bodySmall),
          const Spacer(),
          Text(
            v,
            textDirection: TextDirection.ltr,
            style: text.bodyMedium!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: alwaysOn,
            onChanged: onAlwaysOn,
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Palette.amber,
            title: Text(s.stayUnderground, style: text.titleMedium),
            subtitle: Text(s.stayUndergroundSub, style: text.bodySmall),
          ),
          if (Platform.isAndroid && alwaysOn)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                Icons.settings_outlined,
                color: Palette.sand,
                size: 20,
              ),
              title: Text(
                s.makePermanent,
                style: text.bodyMedium!.copyWith(color: Palette.sand),
              ),
              subtitle: Text(s.makePermanentSub, style: text.bodySmall),
              onTap: () => Tunnel.instance.openVpnSettings(),
            ),
          const Divider(color: Palette.line, height: 8),
          row(s.thisDevice, config.ip),
          row(s.server, config.endpoint),
          row(s.serverKey, '${config.peerPublicKey.substring(0, 8)}…'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextButton(onPressed: onRescan, child: Text(s.rescan)),
              ),
              Expanded(
                child: TextButton(
                  onPressed: onForget,
                  style: TextButton.styleFrom(foregroundColor: Palette.danger),
                  child: Text(s.forget),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
