import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../server.dart';
import '../theme.dart';

/// "Invite someone": the server makes a brand-new device (its own key, role
/// guest, three weeks), and this screen shows it as a QR for a phone in the
/// room and a link for a phone far away. Only owner and family devices get here.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _name = TextEditingController();
  Invitation? _made;
  String? _error;
  bool _busy = false;
  List<Map<String, dynamic>> _guests = const [];

  @override
  void initState() {
    super.initState();
    _loadGuests();
  }

  Future<void> _loadGuests() async {
    try {
      final g = await Server.instance.invites();
      if (mounted) setState(() => _guests = g);
    } on Exception {
      // tunnel down: the create button explains it
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inv = await Server.instance.invite(name);
      if (!mounted) return;
      setState(() => _made = inv);
      _loadGuests();
    } on ServerError catch (e) {
      setState(() => _error = e.message);
    } on Exception {
      if (mounted) setState(() => _error = S.of(context).connectFirst);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(BuildContext context, DateTime? d) =>
      d == null ? '' : MaterialLocalizations.of(context).formatMediumDate(d);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final made = _made;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(s.invite, style: text.titleMedium),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            if (made == null) ...[
              TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: InputDecoration(
                  labelText: s.inviteName,
                  hintText: s.inviteNameHint,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.createInvite),
              ),
            ] else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: made.link,
                    size: 260,
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                made.name,
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                s.inviteNote(_date(context, made.expiresAt)),
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(s.sendIt),
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: s.shareMessage(made.joinUrl ?? made.link)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.inviteWarn,
                style: text.bodySmall!.copyWith(color: Palette.sand),
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => setState(() {
                  _made = null;
                  _name.clear();
                }),
                child: Text(s.inviteAgain),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: text.bodySmall!.copyWith(color: Palette.danger),
              ),
            ],
            if (_guests.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(s.yourGuests, style: text.bodySmall),
              const SizedBox(height: 6),
              for (final g in _guests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(g['name'] as String, style: text.bodyMedium),
                  subtitle: Text(
                    [
                      s.guestStatus((g['status'] as String?) ?? ''),
                      if (g['expiresAt'] is num)
                        s.until(
                          _date(
                            context,
                            DateTime.fromMillisecondsSinceEpoch(
                              (g['expiresAt'] as num).toInt() * 1000,
                            ),
                          ),
                        ),
                    ].join(' · '),
                    style: text.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
