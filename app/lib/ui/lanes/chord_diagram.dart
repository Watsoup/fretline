import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../theme.dart';
import 'highway.dart';
import '../../models/notation.dart';

/// Classic vertical chord box: strings left (low E) to right (high e),
/// nut on top, x / o above the nut.
class ChordDiagram extends StatelessWidget {
  final Chord chord;
  final double width;
  final bool highlight;
  final double opacity;
  const ChordDiagram({super.key, required this.chord, this.width = 120, this.highlight = false, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(chordName(chord.name),
              style: TextStyle(
                fontSize: width * 0.24,
                fontWeight: FontWeight.w800,
                color: highlight ? C.accent : C.text,
              )),
          if (chord.easyOf != null)
            Text('easy ${chordName(chord.easyOf!)}', style: TextStyle(fontSize: width * 0.09, color: C.dim)),
          SizedBox(height: width * 0.04),
          CustomPaint(size: Size(width, width * 1.15), painter: _ChordPainter(chord, highlight)),
        ],
      ),
    );
  }
}

class _ChordPainter extends CustomPainter {
  final Chord chord;
  final bool highlight;
  _ChordPainter(this.chord, this.highlight);

  static const frets = 4;

  @override
  void paint(Canvas c, Size s) {
    final top = s.height * 0.16;
    final left = s.width * 0.16, right = s.width * 0.9;
    final bottom = s.height * 0.98;
    final sx = (right - left) / 5;
    final fy = (bottom - top) / frets;
    final base = chord.baseFret;
    final lineP = Paint()
      ..color = C.dim
      ..strokeWidth = 1.5;

    for (var i = 0; i < 6; i++) {
      c.drawLine(Offset(left + i * sx, top), Offset(left + i * sx, bottom), lineP);
    }
    for (var f = 0; f <= frets; f++) {
      final p = f == 0 && base == 1
          ? (Paint()
            ..color = C.text
            ..strokeWidth = 5)
          : lineP;
      c.drawLine(Offset(left, top + f * fy), Offset(right, top + f * fy), p);
    }
    if (base > 1) {
      paintText(c, '${base}fr', Offset(left * 0.45, top + fy / 2),
          TextStyle(color: C.dim, fontSize: sx * 0.55, fontWeight: FontWeight.w600));
    }

    final dot = Paint()..color = highlight ? C.accent : C.text;
    for (var i = 0; i < 6; i++) {
      final f = chord.frets[i];
      final x = left + i * sx;
      if (f < 0) {
        paintText(c, '×', Offset(x, top * 0.45), TextStyle(color: C.bad, fontSize: sx * 0.8));
      } else if (f == 0) {
        c.drawCircle(
            Offset(x, top * 0.5),
            sx * 0.22,
            Paint()
              ..color = C.text
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      } else {
        final row = f - base + 1;
        final cy = top + (row - 0.5) * fy;
        c.drawCircle(Offset(x, cy), sx * 0.36, dot);
        final finger = chord.fingers?[i];
        if (finger != null && finger > 0) {
          paintText(c, '$finger', Offset(x, cy),
              TextStyle(color: C.bg, fontSize: sx * 0.42, fontWeight: FontWeight.w800));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ChordPainter old) => old.chord != chord || old.highlight != highlight;
}
