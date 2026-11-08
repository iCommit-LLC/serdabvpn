import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../invite.dart';
import '../l10n.dart';
import '../main.dart';
import '../theme.dart';
import 'scan.dart';

/// First launch, no server yet. The person holding the phone was most likely
/// sent an invitation in a chat: one tap reads it from the clipboard. The QR
/// and the raw config stay for the one who runs the server.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _take(BuildContext context, String text) async {
    final s = S.of(context);
    final Invite? invite;
    try {
      invite = Invite.extract(text);
    } on FormatException catch (e) {
      complain(s.notAnInvite(e.message));
      return;
    }
    if (invite == null) {
      complain(s.notAnInvite(s.pasteHint));
      return;
    }
    await adopt(invite);
  }

  /// The clipboard first; the sheet only when it holds nothing usable.
  Future<void> _invitation(BuildContext context) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text ?? '';
    if (!context.mounted) return;
    Invite? found;
    try {
      found = Invite.extract(text);
    } on FormatException {
      found = null;
    }
    if (found != null) {
      await adopt(found);
      return;
    }
    final typed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PasteSheet(initial: text.trim().isEmpty ? '' : text),
    );
    if (typed != null && context.mounted) await _take(context, typed);
  }

  Future<void> _scan(BuildContext context) async {
    final invite = await Navigator.of(
      context,
    ).push<Invite>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (invite != null) await adopt(invite);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Center(child: SvgPicture.asset('assets/logo.svg', width: 168)),
              const SizedBox(height: 36),
              Text('serdab', style: text.displayLarge),
              const SizedBox(height: 10),
              Text(
                s.tagline,
                style: text.displayMedium!.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Palette.sand,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.taglineSub,
                style: text.bodyMedium!.copyWith(color: Palette.muted),
              ),
              const Spacer(flex: 3),
              FilledButton.icon(
                onPressed: () => _invitation(context),
                icon: const Icon(Icons.mail_outline, size: 20),
                label: Text(s.haveInvite),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => _scan(context),
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: Text(s.scanQr),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${s.onTheServer}  sudo serdab add phone',
                  style: text.bodySmall!.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Menlo', 'Courier'],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasteSheet extends StatefulWidget {
  const _PasteSheet({required this.initial});

  final String initial;

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.pasteTitle, style: theme.displayMedium),
          const SizedBox(height: 6),
          Text(
            widget.initial.isEmpty ? s.nothingToPaste : s.pasteHint,
            style: theme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 6,
            autofocus: widget.initial.isEmpty,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: ['Menlo', 'Courier'],
              fontSize: 12.5,
            ),
            decoration: InputDecoration(hintText: s.pasteField),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_text.text),
            child: Text(s.useIt),
          ),
        ],
      ),
    );
  }
}
