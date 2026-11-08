import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../invite.dart';
import '../l10n.dart';
import '../theme.dart';

/// Points the camera at the QR `serdab add` printed (a config, or an
/// invitation link) and returns what it found.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  String? _complaint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final text = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (text == null) return;
    final Invite? invite;
    try {
      invite = Invite.extract(text);
    } on FormatException catch (e) {
      setState(() => _complaint = S.of(context).notAnInvite(e.message));
      return;
    }
    if (invite == null) {
      setState(() => _complaint = S.of(context).notAnInvite(''));
      return;
    }
    _done = true;
    Navigator.of(context).pop(invite);
  }

  @override
  Widget build(BuildContext context) {
    final frame = MediaQuery.sizeOf(context).shortestSide * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: frame,
              height: frame,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Palette.sand.withValues(alpha: 0.9),
                  width: 2,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.topStart,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Palette.text),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  child: Text(
                    _complaint ?? S.of(context).pointAtQr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _complaint == null ? Palette.text : Palette.danger,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
