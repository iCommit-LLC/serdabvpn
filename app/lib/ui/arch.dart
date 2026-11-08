import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tunnel.dart';

/// The logo, painted live. `glow` is 0 when the passage is shut and 1 when you
/// are underground; the lantern, the steps and the outline all follow it.
class ArchPainter extends CustomPainter {
  ArchPainter({required this.glow});

  final double glow;

  static const _vb = 1024.0;
  static final Path _door = Path()
    ..moveTo(295.9, 800)
    ..lineTo(295.9, 548.7)
    ..arcToPoint(
      const Offset(728.1, 548.7),
      radius: const Radius.circular(230),
      largeArc: true,
    )
    ..lineTo(728.1, 800);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / _vb;
    final g = glow.clamp(0.0, 1.0);
    canvas.save();
    canvas.translate((size.width - _vb * s) / 2, (size.height - _vb * s) / 2);
    canvas.scale(s);

    if (g > 0) {
      canvas.drawPath(
        _door,
        Paint()
          ..color = Palette.amber.withValues(alpha: 0.5 * g)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 28
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 40 * g),
      );
    }

    const box = Rect.fromLTWH(200, 200, 624, 600);
    canvas.save();
    canvas.clipPath(Path.from(_door)..close());
    canvas.drawRect(
      box,
      Paint()
        ..shader = ui.Gradient.linear(
          box.topCenter,
          box.bottomCenter,
          [
            Palette.amber.withValues(alpha: 0),
            Palette.amber.withValues(alpha: 0.18 * g),
            Palette.amber.withValues(alpha: 0.85 * g),
          ],
          [0, 0.55, 1],
        ),
    );
    canvas.drawRect(
      box,
      Paint()
        ..shader = ui.Gradient.radial(
          box.bottomCenter,
          470,
          [
            Palette.lamp.withValues(alpha: 0.95 * g),
            Palette.amber.withValues(alpha: 0.15 * g),
            Palette.amber.withValues(alpha: 0),
          ],
          [0, 0.6, 1],
        ),
    );
    canvas.restore();

    final step = Paint();
    for (final (y, w, a) in const [
      (598.0, 300.0, 0.45),
      (658.0, 240.0, 0.7),
      (718.0, 180.0, 1.0),
    ]) {
      step.color = Color.lerp(
        Palette.sand,
        Palette.lamp,
        g,
      )!.withValues(alpha: 0.18 + (a - 0.18) * g);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(512 - w / 2, y, w, 22),
          const Radius.circular(11),
        ),
        step,
      );
    }

    final line = Paint()
      ..color = Color.lerp(
        Palette.sand.withValues(alpha: 0.55),
        Palette.sand,
        g,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_door, line);
    canvas.drawLine(const Offset(190, 800), const Offset(834, 800), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArchPainter old) => old.glow != glow;
}

/// The door you tap. Shut, breathing while it opens, lit once you are through.
class ArchButton extends StatefulWidget {
  const ArchButton({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 280,
  });

  final TunnelState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<ArchButton> createState() => _ArchButtonState();
}

class _ArchButtonState extends State<ArchButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(ArchButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _follow();
  }

  void _follow() {
    switch (widget.state) {
      case TunnelState.connected:
        _glow.animateTo(
          1,
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
        );
      case TunnelState.connecting:
      case TunnelState.disconnecting:
        _glow.repeat(
          min: 0.2,
          max: 0.7,
          reverse: true,
          period: const Duration(milliseconds: 1400),
        );
      case TunnelState.disconnected:
      case TunnelState.denied:
        _glow.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.state == TunnelState.connected ? 'Disconnect' : 'Connect',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedBuilder(
            animation: _glow,
            builder: (_, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: ArchPainter(glow: _glow.value),
            ),
          ),
        ),
      ),
    );
  }
}
