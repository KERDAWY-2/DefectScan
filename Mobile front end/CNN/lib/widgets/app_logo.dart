import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The app's brand mark — a magnifier inspecting a cracked wall — drawn with a
/// [CustomPainter] so it stays crisp at any size on both mobile and web with no
/// image asset or extra package.
///
/// Pass [color] to render a single-color version (e.g. white on a dark header);
/// otherwise it uses the brand blue + amber palette suited to light surfaces.
class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const AppLogo({super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(mono: color)),
    );
  }
}

/// A white rounded badge wrapping the logo — used on dark/brand backgrounds
/// (app bar, gradient hero) so the colored mark stays legible.
class AppLogoBadge extends StatelessWidget {
  final double size;
  final double padding;

  const AppLogoBadge({super.key, this.size = 40, this.padding = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppLogo(size: size - padding * 2),
    );
  }
}

/// Logo mark + app name lockup for the login / register hero.
class AppWordmark extends StatelessWidget {
  final bool onDark;
  final double logoSize;

  const AppWordmark({super.key, this.onDark = true, this.logoSize = 72});

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : kInk;
    final subColor =
        onDark ? Colors.white.withValues(alpha: 0.85) : kInkMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogoBadge(size: logoSize, padding: logoSize * 0.16),
        const SizedBox(height: 14),
        Text(
          'DefectScan',
          style: TextStyle(
            color: titleColor,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'AI building-defect inspection',
          style: TextStyle(
            color: subColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  /// When non-null, the whole mark is drawn in shades of this single color.
  final Color? mono;

  _LogoPainter({this.mono});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    final Color wallColor = mono?.withValues(alpha: 0.12) ??
        kBrandBlue.withValues(alpha: 0.10);
    final Color mortarColor = mono?.withValues(alpha: 0.35) ??
        kBrandBlue.withValues(alpha: 0.28);
    final Color crackColor = mono?.withValues(alpha: 0.95) ?? kBrandAmber;
    final Color ringColor = mono ?? kBrandBlue;
    final Color glassColor = mono?.withValues(alpha: 0.08) ??
        kBrandBlueLight.withValues(alpha: 0.12);

    // --- Wall tile (rounded square in the upper-left) ---
    final wallRect = Rect.fromLTWH(0.06 * s, 0.06 * s, 0.66 * s, 0.66 * s);
    final wallRRect =
        RRect.fromRectAndRadius(wallRect, Radius.circular(0.10 * s));
    canvas.drawRRect(wallRRect, Paint()..color = wallColor);

    // Mortar lines (brick feel), clipped to the wall tile.
    canvas.save();
    canvas.clipRRect(wallRRect);
    final mortar = Paint()
      ..color = mortarColor
      ..strokeWidth = 0.018 * s
      ..strokeCap = StrokeCap.round;
    // horizontal courses
    for (final fy in [0.30, 0.52]) {
      canvas.drawLine(Offset(0.06 * s, fy * s), Offset(0.72 * s, fy * s),
          mortar);
    }
    // staggered vertical joints
    canvas.drawLine(Offset(0.30 * s, 0.06 * s), Offset(0.30 * s, 0.30 * s),
        mortar);
    canvas.drawLine(Offset(0.52 * s, 0.30 * s), Offset(0.52 * s, 0.52 * s),
        mortar);
    canvas.drawLine(Offset(0.24 * s, 0.52 * s), Offset(0.24 * s, 0.72 * s),
        mortar);
    canvas.restore();

    // --- Crack (jagged amber polyline with a small branch) ---
    final crack = Paint()
      ..color = crackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final crackPath = Path()
      ..moveTo(0.40 * s, 0.06 * s)
      ..lineTo(0.34 * s, 0.22 * s)
      ..lineTo(0.47 * s, 0.33 * s)
      ..lineTo(0.39 * s, 0.50 * s)
      ..lineTo(0.48 * s, 0.66 * s);
    // branch
    crackPath
      ..moveTo(0.47 * s, 0.33 * s)
      ..lineTo(0.60 * s, 0.38 * s);
    canvas.drawPath(crackPath, crack);

    // --- Magnifier (overlapping the wall's lower-right) ---
    final center = Offset(0.64 * s, 0.64 * s);
    final radius = 0.22 * s;

    // Handle first so the ring sits on top of its base.
    final handle = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.11 * s
      ..strokeCap = StrokeCap.round;
    final hStart = center +
        Offset.fromDirection(0.785, radius); // 45° outward from the ring
    final hEnd = Offset(0.93 * s, 0.93 * s);
    canvas.drawLine(hStart, hEnd, handle);

    // Glass fill + subtle highlight.
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(center, radius, Paint()..color = glassColor);
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.62),
      3.6, // start angle (upper-left)
      1.2, // sweep
      false,
      highlight,
    );

    // Ring.
    final ring = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.075 * s;
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.mono != mono;
}
