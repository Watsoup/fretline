import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../theme.dart';

/// Shared horizontal time axis for the scrolling lanes.
/// The "now" line sits at [nowFrac] of the width; events scroll in from the right.
class Highway {
  static const nowFrac = 0.22;
  static const beatsAhead = 8.0;

  final double now, width, secAhead;
  Highway(this.now, this.width, Lesson lesson) : secAhead = beatsAhead * lesson.beatLen(now);

  double get nowX => width * nowFrac;
  double get pxPerSec => (width - nowX) / secAhead;
  double get secBehind => nowX / pxPerSec;
  double x(double t) => nowX + (t - now) * pxPerSec;
  bool visible(double t, [double dur = 0]) => t + dur >= now - secBehind && t <= now + secAhead;

  /// 1 at the now line, fading the further ahead (doc: eye stays on the next 2-3).
  double fade(double t) {
    if (t < now) return 0.3; // already played
    return (1 - 0.75 * ((t - now) / secAhead)).clamp(0.2, 1.0);
  }

  void paintGrid(Canvas c, Size s, Lesson lesson) {
    final beat = Paint()..color = C.line.withValues(alpha: 0.5);
    final bar = Paint()
      ..color = C.line
      ..strokeWidth = 2;
    final downs = lesson.downbeats.toSet();
    final i0 = lastAtOrBefore(lesson.beats, now - secBehind, (b) => b).clamp(0, lesson.beats.length);
    for (var i = i0; i < lesson.beats.length; i++) {
      final b = lesson.beats[i];
      if (b > now + secAhead) break;
      final xx = x(b);
      c.drawLine(Offset(xx, 0), Offset(xx, s.height), downs.contains(b) ? bar : beat);
    }
  }

  void paintNowLine(Canvas c, Size s) {
    final p = Paint()
      ..color = C.nowLine
      ..strokeWidth = 3;
    c.drawLine(Offset(nowX, 0), Offset(nowX, s.height), p);
    // played zone, dimmed
    c.drawRect(Rect.fromLTWH(0, 0, nowX, s.height), Paint()..color = C.bg.withValues(alpha: 0.35));
  }
}

void paintText(Canvas c, String text, Offset center, TextStyle style) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}
