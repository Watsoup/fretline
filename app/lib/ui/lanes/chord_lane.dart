import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../theme.dart';
import 'chord_diagram.dart';

/// Current chord big + countdown ring (beats until change), next two smaller and dimmed.
class ChordLane extends StatelessWidget {
  final ValueNotifier<double> time;
  final Lesson lesson;
  final Part part;
  const ChordLane({super.key, required this.time, required this.lesson, required this.part});

  @override
  Widget build(BuildContext context) {
    if (part.chords.isEmpty) {
      return const Center(child: Text('No chords in this part', style: TextStyle(color: C.dim)));
    }
    return LayoutBuilder(builder: (context, box) {
      final big = math.min(box.maxHeight * 0.62, 150.0);
      return ValueListenableBuilder<double>(
        valueListenable: time,
        builder: (context, now, _) {
          final i = lastAtOrBefore(part.chords, now, (c) => c.t);
          final cur = i >= 0 ? part.chords[i] : null;
          final next = <Chord>[];
          for (var k = i + 1; k < part.chords.length && next.length < 2; k++) {
            if (part.chords[k].name != (next.isEmpty ? cur?.name : next.last.name)) next.add(part.chords[k]);
          }
          double? beatsLeft, frac;
          if (next.isNotEmpty) {
            final start = cur?.t ?? 0;
            beatsLeft = lesson.beatsBetween(now, next.first.t);
            frac = ((now - start) / (next.first.t - start)).clamp(0.0, 1.0);
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
            children: [
              const SizedBox(width: 16),
              SizedBox(
                width: big * 1.1,
                child: cur == null
                    ? const Center(child: Text('get ready', style: TextStyle(color: C.dim)))
                    : ChordDiagram(chord: cur, width: big * 0.8, highlight: true),
              ),
              const SizedBox(width: 12),
              if (beatsLeft != null) _Countdown(beats: beatsLeft, frac: frac!, size: big * 0.55),
              const SizedBox(width: 28),
              for (var k = 0; k < next.length; k++) ...[
                ChordDiagram(chord: next[k], width: big * (k == 0 ? 0.55 : 0.42), opacity: k == 0 ? 0.65 : 0.35),
                const SizedBox(width: 20),
              ],
            ],
          ));
        },
      );
    });
  }
}

class _Countdown extends StatelessWidget {
  final double beats, frac, size;
  const _Countdown({required this.beats, required this.frac, required this.size});

  @override
  Widget build(BuildContext context) {
    final n = beats.ceil();
    final urgent = beats <= 2;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: frac,
            strokeWidth: 6,
            color: urgent ? C.accent : C.dim,
            backgroundColor: C.line,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$n', style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: urgent ? C.accent : C.text)),
          Text(n == 1 ? 'beat' : 'beats', style: TextStyle(fontSize: size * 0.14, color: C.dim)),
        ]),
      ]),
    );
  }
}
