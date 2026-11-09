import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../theme.dart';
import 'highway.dart';

/// Mini neck: where the fingers go now, with the next shape faded in early.
/// Shows chord shapes when [useChords], otherwise the current tab notes.
class FretboardPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final Lesson lesson;
  final Part part;
  final bool useChords;
  FretboardPainter(this.time, this.lesson, this.part, this.useChords) : super(repaint: time);

  static const visibleFrets = 12;
  static const inlays = [3, 5, 7, 9, 12];

  @override
  void paint(Canvas c, Size s) {
    final now = time.value;
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2A2018));

    final nutX = s.width * 0.05;
    final fw = (s.width - nutX) / visibleFrets;
    final gap = s.height / 7;
    double fx(int fret) => fret == 0 ? nutX * 0.5 : nutX + (fret - 0.5) * fw;
    double sy(int string) => gap * string;

    for (final f in inlays) {
      final x = nutX + (f - 0.5) * fw;
      if (f == 12) {
        c.drawCircle(Offset(x, s.height * 0.3), gap * 0.18, Paint()..color = const Color(0x33FFFFFF));
        c.drawCircle(Offset(x, s.height * 0.7), gap * 0.18, Paint()..color = const Color(0x33FFFFFF));
      } else {
        c.drawCircle(Offset(x, s.height / 2), gap * 0.18, Paint()..color = const Color(0x33FFFFFF));
      }
    }
    c.drawRect(Rect.fromLTWH(nutX - 4, 0, 5, s.height), Paint()..color = const Color(0xFFDDD5C0));
    for (var f = 1; f <= visibleFrets; f++) {
      final x = nutX + f * fw;
      c.drawLine(Offset(x, 0), Offset(x, s.height), Paint()..color = const Color(0xFF8A8A8A)..strokeWidth = 2);
    }
    for (var st = 1; st <= 6; st++) {
      c.drawLine(Offset(0, sy(st)), Offset(s.width, sy(st)),
          Paint()..color = const Color(0xFFCCCCCC)..strokeWidth = 0.8 + (st - 1) * 0.4);
    }

    final r = math.min(gap * 0.42, fw * 0.35);
    void dot(int string, int fret, Color col, {bool ghost = false, String? label}) {
      if (fret > visibleFrets) return;
      final o = Offset(fx(fret), sy(string));
      if (ghost) {
        c.drawCircle(o, r, Paint()..color = col.withValues(alpha: 0.25));
        c.drawCircle(o, r, Paint()..color = col.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 2);
      } else {
        c.drawCircle(o, r * 1.25, Paint()..color = col.withValues(alpha: 0.6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        c.drawCircle(o, r, Paint()..color = col);
      }
      if (label != null) {
        paintText(c, label, o, TextStyle(color: ghost ? col : C.bg, fontSize: r * 1.1, fontWeight: FontWeight.w800));
      }
    }

    if (useChords && part.chords.isNotEmpty) {
      final i = lastAtOrBefore(part.chords, now, (x) => x.t);
      Chord? next;
      for (var k = i + 1; k < part.chords.length; k++) {
        if (i < 0 || part.chords[k].name != part.chords[i].name) {
          next = part.chords[k];
          break;
        }
      }
      // fade the next shape in during the last 2 beats before the change
      if (next != null && lesson.beatsBetween(now, next.t) <= 2) {
        _shape(next, (st, f, fi) => dot(st, f, C.dim, ghost: true, label: fi));
      }
      if (i >= 0) _shape(part.chords[i], (st, f, fi) => dot(st, f, C.accent, label: fi));
    } else {
      final win = lesson.beatLen(now);
      final i0 = math.max(0, lastAtOrBefore(part.notes, now - 4, (n) => n.t));
      for (var k = i0; k < part.notes.length; k++) {
        final n = part.notes[k];
        if (n.t > now + win) break;
        final sounding = n.t <= now && now < n.t + math.max(n.dur, 0.1);
        final upcoming = n.t > now;
        if (sounding) {
          dot(n.string, n.fret, C.strings[n.string - 1], label: '${n.fret}');
        } else if (upcoming) {
          dot(n.string, n.fret, C.strings[n.string - 1], ghost: true);
        }
      }
    }
  }

  void _shape(Chord ch, void Function(int string, int fret, String? finger) draw) {
    for (var i = 0; i < 6; i++) {
      final f = ch.frets[i];
      if (f < 0) continue;
      final string = 6 - i; // frets[] goes low E -> high e
      final fi = ch.fingers?[i];
      draw(string, f, fi != null && fi > 0 ? '$fi' : null);
    }
  }

  @override
  bool shouldRepaint(FretboardPainter old) => old.part != part || old.useChords != useChords;
}
