import '../../l10n/localized_material.dart';

import '../../core/theme/cardock_tokens.dart';
import '../../core/theme/custom_theme.dart';

/// Renders the production Cardock mark for the active theme.
///
/// All eight fixed themes and Custom use the same frozen Logo C painter
/// geometry. Android launcher aliases remain a separate packaged-asset domain.
class CardockBrandSymbol extends StatelessWidget {
  const CardockBrandSymbol({
    required this.size,
    this.family,
    this.brightness,
    this.customColors,
    this.excludeFromSemantics = true,
    super.key,
  });

  final double size;
  final CardockThemeFamily? family;
  final Brightness? brightness;
  final CardockCustomColors? customColors;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final extension = context.cardockTheme;
    final resolvedFamily = family ?? extension.family;
    final resolvedBrightness = brightness ?? Theme.of(context).brightness;
    final colors = resolvedFamily == CardockThemeFamily.custom
        ? customColors
        : null;
    final palette = resolvedFamily == extension.family
        ? extension.palette
        : CardockTokens.palette(resolvedFamily, resolvedBrightness);
    return ExcludeSemantics(
      excluding: excludeFromSemantics,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _CardockLogoCPainter(
            primary: colors?.brandPrimary ?? palette.primary,
            secondary:
                colors?.brandSecondary ?? palette.accent ?? palette.primary,
            reminder:
                colors?.renewalAccent ?? palette.accentWarm ?? palette.primary,
          ),
        ),
      ),
    );
  }
}

class _CardockLogoCPainter extends CustomPainter {
  const _CardockLogoCPainter({
    required this.primary,
    required this.secondary,
    required this.reminder,
  });

  final Color primary;
  final Color secondary;
  final Color reminder;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 1024;
    final dx = (size.width - (1024 * scale)) / 2;
    final dy = (size.height - (1024 * scale)) / 2;
    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    final logoBounds = const Rect.fromLTWH(160, 120, 640, 720);
    final dock = Path()
      ..moveTo(236, 322)
      ..lineTo(236, 574)
      ..cubicTo(236, 728, 348, 820, 486, 820)
      ..lineTo(538, 820)
      ..cubicTo(676, 820, 788, 728, 788, 574)
      ..lineTo(788, 322);
    canvas.drawPath(
      dock,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 124
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[primary, _mix(primary, secondary, 0.38)],
        ).createShader(logoBounds),
    );

    final card = Path()
      ..moveTo(400, 160)
      ..lineTo(588, 160)
      ..lineTo(680, 252)
      ..lineTo(680, 600)
      ..quadraticBezierTo(680, 652, 628, 652)
      ..lineTo(396, 652)
      ..quadraticBezierTo(344, 652, 344, 600)
      ..lineTo(344, 216)
      ..quadraticBezierTo(344, 160, 400, 160)
      ..close();
    canvas.drawPath(
      card,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_mix(primary, secondary, 0.18), primary],
        ).createShader(logoBounds),
    );

    final fold = Path()
      ..moveTo(588, 160)
      ..lineTo(588, 252)
      ..lineTo(680, 252)
      ..close();
    canvas.drawPath(fold, Paint()..color = Colors.white.withValues(alpha: 0.2));
    final foldEdge = Path()
      ..moveTo(588, 160)
      ..lineTo(588, 252)
      ..lineTo(680, 252);
    canvas.drawPath(
      foldEdge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.2),
    );

    canvas.drawPath(_diamond(512, 364, 98, 50), Paint()..color = Colors.white);
    canvas.drawPath(
      _layer(414, 404, 512, 454, 610, 404, 438, 488),
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
    canvas.drawPath(
      _layer(414, 452, 512, 502, 610, 452, 486, 536),
      Paint()..color = secondary,
    );

    canvas.drawCircle(
      const Offset(704, 204),
      50,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[_mix(reminder, Colors.white, 0.2), reminder],
            ).createShader(
              Rect.fromCircle(center: const Offset(704, 204), radius: 50),
            ),
    );
    canvas.drawCircle(
      const Offset(688, 188),
      13,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    canvas.restore();
  }

  static Path _diamond(
    double centerX,
    double centerY,
    double halfWidth,
    double halfHeight,
  ) => Path()
    ..moveTo(centerX, centerY - halfHeight)
    ..lineTo(centerX + halfWidth, centerY)
    ..lineTo(centerX, centerY + halfHeight)
    ..lineTo(centerX - halfWidth, centerY)
    ..close();

  static Path _layer(
    double leftX,
    double topY,
    double centerX,
    double centerY,
    double rightX,
    double rightY,
    double lowerTopY,
    double lowerCenterY,
  ) => Path()
    ..moveTo(leftX, topY)
    ..lineTo(centerX, centerY)
    ..lineTo(rightX, rightY)
    ..lineTo(rightX, lowerTopY)
    ..lineTo(centerX, lowerCenterY)
    ..lineTo(leftX, lowerTopY)
    ..close();

  static Color _mix(Color a, Color b, double amount) =>
      Color.lerp(a, b, amount)!;

  @override
  bool shouldRepaint(covariant _CardockLogoCPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.reminder != reminder;
}
