import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

// ---------------------------------------------------------------- palette

const forest = Color(0xFF0E2A1C);
const leaf = Color(0xFF2F7D4F);
const moss = Color(0xFF8CC47A);
const good = Color(0xFF1F8A4C);
const warn = Color(0xFFD08A00);
const bad = Color(0xFFC6352B);

class Palette {
  const Palette(this.dark);
  final bool dark;

  Color get page => dark ? const Color(0xFF0C120E) : const Color(0xFFF4F1E9);
  Color get card => dark ? const Color(0xFF161F19) : Colors.white;
  Color get ink => dark ? const Color(0xFFEAF0EA) : const Color(0xFF14201A);
  Color get muted => dark ? const Color(0xFF9FB0A3) : const Color(0xFF5D6A61);
  Color get line => dark ? const Color(0xFF26322A) : const Color(0xFFE6E1D5);
  Color get tile => dark ? const Color(0xFF1C2820) : const Color(0xFFEEF5EB);
  Color get accent => dark ? moss : leaf;

  static Palette of(BuildContext context) => Palette(Theme.of(context).brightness == Brightness.dark);
}

// -------------------------------------------------------------- motion

/// Fades and slides its child in, after [delay]. Used to stagger a screen.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Shrinks slightly while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

// --------------------------------------------------------------- pieces

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.line),
        boxShadow: p.dark
            ? null
            : [BoxShadow(color: forest.withValues(alpha: 0.08), blurRadius: 26, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.onSettings, required this.status, required this.statusColor});
  final VoidCallback onSettings;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [forest, leaf]),
        ),
        child: Stack(children: [
          // Soft decorative shapes.
          Positioned(right: -46, top: -30, child: _Blob(size: 170, color: Colors.white.withValues(alpha: 0.07))),
          Positioned(right: 70, bottom: -60, child: _Blob(size: 120, color: moss.withValues(alpha: 0.16))),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 8, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.eco_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CWSB Check',
                        style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    SizedBox(height: 1),
                    Text('Coffee white stem borer screening',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFFCFE6D4), fontSize: 13)),
                  ]),
                ),
                IconButton(
                  onPressed: onSettings,
                  tooltip: 'Where the model runs',
                  icon: const Icon(Icons.tune_rounded, color: Colors.white),
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.7), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Placeholder shown before a photo is chosen.
class EmptyStage extends StatefulWidget {
  const EmptyStage({super.key});

  @override
  State<EmptyStage> createState() => _EmptyStageState();
}

class _EmptyStageState extends State<EmptyStage> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CustomPaint(
      foregroundPainter: _DashedBorder(color: p.accent.withValues(alpha: 0.55), radius: 20),
      child: Container(
        color: p.tile,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -6 * Curves.easeInOut.transform(_c.value)),
              child: child,
            ),
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.accent.withValues(alpha: 0.26), p.accent.withValues(alpha: 0.10)],
                ),
              ),
              child: Icon(Icons.add_photo_alternate_rounded, size: 42, color: p.accent),
            ),
          ),
          const SizedBox(height: 18),
          Text('Add a photo of the coffee plant',
              textAlign: TextAlign.center, style: TextStyle(color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Upload one from the gallery or capture it now.',
              textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14, height: 1.35)),
        ]),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), Radius.circular(radius)));
    const dash = 9.0, gap = 7.0;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Shown over the photo while the model works: a light bar sweeping down.
class ScanOverlay extends StatefulWidget {
  const ScanOverlay({super.key, required this.text});
  final String text;

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
      if (!still) RepaintBoundary(child: CustomPaint(painter: _ScanPainter(_c))),
      Align(
        alignment: const Alignment(0, 0.86),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
            const SizedBox(width: 10),
            Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final y = Curves.easeInOut.transform(t.value) * size.height;
    const trail = 90.0;
    canvas.drawRect(
      Rect.fromLTRB(0, y - trail, size.width, y),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [moss.withValues(alpha: 0), moss.withValues(alpha: 0.34)],
        ).createShader(Rect.fromLTRB(0, y - trail, size.width, y)),
    );
    canvas.drawRect(Rect.fromLTRB(0, y - 2, size.width, y + 1), Paint()..color = const Color(0xFFD8FFCB));
    // Corner brackets.
    final b = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const m = 18.0, l = 26.0;
    for (final (dx, dy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
      final cx = dx == 1 ? m : size.width - m, cy = dy == 1 ? m : size.height - m;
      canvas.drawLine(Offset(cx, cy), Offset(cx + l * dx, cy), b);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + l * dy), b);
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) => false;
}

class ActionTile extends StatelessWidget {
  const ActionTile(
      {super.key, required this.icon, required this.title, required this.caption, required this.onTap, this.filled = false});
  final IconData icon;
  final String title, caption;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: title,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: filled
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [forest, leaf])
                : null,
            color: filled ? null : p.tile,
            border: filled ? null : Border.all(color: p.line),
            boxShadow: filled && !p.dark
                ? [BoxShadow(color: leaf.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))]
                : null,
          ),
          child: Column(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: filled ? Colors.white.withValues(alpha: 0.16) : p.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: filled ? Colors.white : p.accent),
            ),
            const SizedBox(height: 10),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: filled ? Colors.white : p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: filled ? const Color(0xFFCFE6D4) : p.muted, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onPressed, this.icon, this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onPressed != null;
    final fg = primary ? Colors.white : p.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Pressable(
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.55,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 58,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: primary
                  ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [leaf, Color(0xFF1F5E3A)])
                  : null,
              color: primary ? null : p.card,
              border: primary ? null : Border.all(color: p.line, width: 1.5),
              boxShadow: primary && enabled && !p.dark
                  ? [BoxShadow(color: leaf.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 8))]
                  : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20, color: fg)],
            ]),
          ),
        ),
      ),
    );
  }
}

class TipRow extends StatelessWidget {
  const TipRow({super.key, required this.icon, required this.title, required this.text, this.last = false});
  final IconData icon;
  final String title, text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: p.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(text, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}

class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = error ? bad : warn;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.dark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.error_rounded : Icons.info_rounded, color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: p.ink, fontSize: 14, height: 1.35))),
      ]),
    );
  }
}

class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
      child: Row(children: [
        Icon(icon, size: 18, color: p.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5)),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }
}

/// Segmented switch with a sliding thumb.
class SegmentSwitch extends StatelessWidget {
  const SegmentSwitch({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(22), border: Border.all(color: p.line)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [leaf, Color(0xFF1F5E3A)]),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(
                            color: i == index ? Colors.white : p.muted, fontSize: 13.5, fontWeight: FontWeight.w700),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// The photo and its heatmap: 0 = heatmap, 1 = photo, 2 = drag to compare.
class HeatView extends StatefulWidget {
  const HeatView({super.key, required this.photo, required this.heatmap, required this.mode});
  final Uint8List photo, heatmap;
  final int mode;

  @override
  State<HeatView> createState() => _HeatViewState();
}

class _HeatViewState extends State<HeatView> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    final photo = Image.memory(widget.photo, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    final heat = Image.memory(widget.heatmap, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          if (widget.mode != 2) {
            return Stack(fit: StackFit.expand, children: [
              photo,
              AnimatedOpacity(
                opacity: widget.mode == 0 ? 1 : 0,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                child: heat,
              ),
            ]);
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() => _split = (_split + d.delta.dx / w).clamp(0.04, 0.96)),
            onTapDown: (d) => setState(() => _split = (d.localPosition.dx / w).clamp(0.04, 0.96)),
            child: Stack(fit: StackFit.expand, children: [
              heat,
              ClipRect(clipper: _LeftClip(_split), child: photo),
              const Positioned(left: 10, top: 10, child: _Tag('Photo')),
              const Positioned(right: 10, top: 10, child: _Tag('Heatmap')),
              Positioned(
                left: w * _split - 1.5,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: Colors.white),
              ),
              Positioned(
                left: w * _split - 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8)],
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: forest, size: 24),
                  ),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

class _LeftClip extends CustomClipper<Rect> {
  _LeftClip(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClip old) => old.fraction != fraction;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// Circular gauge with the score as a number out of 100.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({super.key, required this.score, required this.color});
  final double score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.clamp(0.0, 1.0)),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 104,
        height: 104,
        child: CustomPaint(
          painter: _GaugePainter(value: v, color: color, track: p.line),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(v * 100).round()}',
                  style: TextStyle(color: p.ink, fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
              Text('of 100', style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color, required this.track});
  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final arc = (Offset.zero & size).deflate(stroke / 2);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, start, sweep, false, base..color = track);
    if (value > 0.005) {
      canvas.drawArc(
        arc,
        start,
        sweep * value,
        false,
        base
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: math.pi * 2,
            transform: const GradientRotation(start - 0.2),
            colors: [Color.lerp(color, Colors.white, 0.35)!, color],
            stops: const [0, 0.75],
          ).createShader(arc),
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color || old.track != track;
}

/// Green / amber / red bar with a marker at the model's score.
class BandBar extends StatelessWidget {
  const BandBar({super.key, required this.score, required this.low, required this.high});
  final double score, low, high;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final labels = TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600);
    return Column(children: [
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: score.clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => SizedBox(
            height: 22,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 10,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: w * low, child: const ColoredBox(color: good)),
                      SizedBox(width: w * (high - low), child: const ColoredBox(color: warn)),
                      const Expanded(child: ColoredBox(color: bad)),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: (w * v - 3).clamp(0.0, w - 6),
                top: 0,
                child: Container(
                  width: 6,
                  height: 22,
                  decoration: BoxDecoration(
                    color: p.ink,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: p.card, width: 1.5),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Healthy', style: labels),
        Text('Unsure', style: labels),
        Text('Unhealthy', style: labels),
      ]),
    ]);
  }
}
