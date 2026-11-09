import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../theme.dart';
import 'highway.dart';

/// Down/up arrows on the beat grid. Current strum glows, muted strums are
/// outlined, accents are bold.
class StrumLanePainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Lesson lesson;
  final Part part;
  StrumLanePainter(this.time, this.lesson, this.part) : super(repaint: time);

  static const hitWindow = 0.09; // s, "current" strum glow

  @override
  void paint(Canvas c, Size s) {
    final now = time.value;
    final h = Highway(now, s.width, lesson);
    c.drawRect(Offset.zero & s, Paint()..color = C.panel);
    h.paintGrid(c, s, lesson);

    final i0 = math.max(0, lastAtOrBefore(part.strums, now - h.secBehind, (x) => x.t));
    final mid = s.height / 2;
    for (var i = i0; i < part.strums.length; i++) {
      final st = part.strums[i];
      if (st.t > now + h.secAhead) break;
      final x = h.x(st.t);
      final current = (st.t - now).abs() < hitWindow;
      final color = (st.dir == StrumDir.down ? C.down : C.up).withValues(alpha: h.fade(st.t));
      _arrow(c, Offset(x, mid), s.height * (st.accent ? 0.72 : 0.6), st.dir, color,
          outlined: st.muted, bold: st.accent, glow: current);
    }
    h.paintNowLine(c, s);
  }

  void _arrow(Canvas c, Offset center, double len, StrumDir dir, Color color,
      {bool outlined = false, bool bold = false, bool glow = false}) {
    final w = len * 0.42;
    final sign = dir == StrumDir.down ? 1.0 : -1.0;
    final tip = center + Offset(0, sign * len / 2);
    final tail = center - Offset(0, sign * len / 2);
    final headBase = tip - Offset(0, sign * w * 0.9);
    final path = Path()
      ..moveTo(tail.dx - w * 0.18, tail.dy)
      ..lineTo(tail.dx + w * 0.18, tail.dy)
      ..lineTo(headBase.dx + w * 0.18, headBase.dy)
      ..lineTo(headBase.dx + w / 2, headBase.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(headBase.dx - w / 2, headBase.dy)
      ..lineTo(headBase.dx - w * 0.18, headBase.dy)
      ..close();
    if (glow) {
      c.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    c.drawPath(
      path,
      Paint()
        ..color = color
        ..style = outlined ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = bold ? 3 : 2,
    );
    if (bold && !outlined) {
      c.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(StrumLanePainter old) => old.part != part || old.lesson != lesson;
}
