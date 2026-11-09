import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../theme.dart';
import 'highway.dart';

/// Six string lines (high e on top, like printed tab) with fret numbers
/// flowing toward the now line, and technique marks on the notes.
class TabLanePainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Lesson lesson;
  final Part part;
  TabLanePainter(this.time, this.lesson, this.part) : super(repaint: time);

  // longest note we expect; used to start the scan early enough
  static const maxDur = 4.0;

  @override
  void paint(Canvas c, Size s) {
    final now = time.value;
    final h = Highway(now, s.width, lesson);
    c.drawRect(Offset.zero & s, Paint()..color = C.panel);
    h.paintGrid(c, s, lesson);

    final gap = s.height / 7;
    double y(int string) => gap * string; // string 1 at top
    for (var st = 1; st <= 6; st++) {
      c.drawLine(
        Offset(0, y(st)),
        Offset(s.width, y(st)),
        Paint()
          ..color = C.strings[st - 1].withValues(alpha: 0.35)
          ..strokeWidth = 1 + (st - 1) * 0.35,
      );
    }

    final box = math.min(gap * 0.95, 30.0);
    final i0 = math.max(0, lastAtOrBefore(part.notes, now - h.secBehind - maxDur, (n) => n.t));
    for (var i = i0; i < part.notes.length; i++) {
      final n = part.notes[i];
      if (n.t > now + h.secAhead) break;
      if (!h.visible(n.t, n.dur)) continue;
      final x = h.x(n.t);
      final yy = y(n.string);
      final col = C.strings[n.string - 1];
      final a = h.fade(n.t);
      final current = n.t <= now && now < n.t + math.max(n.dur, 0.08);

      // sustain tail
      final tailEnd = h.x(n.t + n.dur);
      if (tailEnd - x > box * 0.6) {
        c.drawRRect(
          RRect.fromLTRBR(x, yy - box * 0.14, tailEnd, yy + box * 0.14, const Radius.circular(4)),
          Paint()..color = col.withValues(alpha: 0.35 * a),
        );
      }

      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, yy), width: box * 1.15, height: box), const Radius.circular(6));
      if (current) {
        c.drawRRect(
            r.inflate(3),
            Paint()
              ..color = col
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      }
      c.drawRRect(r, Paint()..color = (current ? col : C.bg).withValues(alpha: current ? 1 : 0.9 * a));
      c.drawRRect(
          r,
          Paint()
            ..color = col.withValues(alpha: a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      paintText(
        c,
        '${n.fret}',
        Offset(x, yy),
        TextStyle(
          color: (current ? C.bg : C.text).withValues(alpha: current ? 1 : a),
          fontSize: box * 0.62,
          fontWeight: FontWeight.w700,
        ),
      );
      if (n.tech != null) _tech(c, n, Offset(x, yy), box, col.withValues(alpha: a), h);
    }
    h.paintNowLine(c, s);
  }

  void _tech(Canvas c, TabNote n, Offset at, double box, Color col, Highway h) {
    final label = switch (n.tech) {
      'hammer_on' => 'h',
      'pull_off' => 'p',
      'slide' => '/',
      'bend' => '↑${n.techToFret ?? ''}',
      'harmonic' => '◇',
      'vibrato' => '~',
      'palm_mute' => 'PM',
      _ => '?',
    };
    paintText(c, label, at + Offset(0, -box * 0.85),
        TextStyle(color: col, fontSize: box * 0.42, fontWeight: FontWeight.w600));
    if (n.tech == 'slide' && n.techToFret != null) {
      final end = Offset(h.x(n.t + n.dur), at.dy - (n.techToFret! > n.fret ? box * 0.3 : -box * 0.3));
      c.drawLine(
          at + Offset(box * 0.6, 0),
          end,
          Paint()
            ..color = col
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(TabLanePainter old) => old.part != part || old.lesson != lesson;
}
