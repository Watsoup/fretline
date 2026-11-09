import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fretline/data/fretpack.dart';
import 'package:fretline/data/sync.dart';
import 'package:fretline/models/lesson.dart';
import 'package:fretline/models/notation.dart';
import 'package:fretline/player/drills.dart';

void main() {
  late FretPack pack;
  setUpAll(() => pack = parseFretpack(File('assets/demo.fretpack').readAsBytesSync()));

  test('demo package parses', () {
    expect(pack.manifest.title, contains('Demo'));
    expect(pack.lesson.parts.map((p) => p.id), containsAll(['rhythm', 'lead']));
    final rhythm = pack.lesson.part('rhythm');
    expect(rhythm.chords.first.name, 'G');
    expect(rhythm.chords.first.frets, [3, 2, 0, 0, 0, 3]);
    expect(rhythm.strums, isNotEmpty);
  });

  test('chordAt and beat helpers', () {
    final r = pack.lesson.part('rhythm');
    expect(r.chordAt(0.1)!.name, 'G');
    expect(r.chordAt(2.5)!.name, 'C'); // second bar at 100 BPM starts at 2.4 s
    expect(pack.lesson.beatLen(1.0), closeTo(0.6, 0.01));
  });

  test('every skill has a playable loop', () {
    for (final p in pack.lesson.parts) {
      for (final s in p.skills) {
        final l = loopFor(pack.lesson, s, 0);
        expect(l.end, greaterThan(l.start), reason: s.id);
      }
    }
  });

  test('parseHost accepts QR url and typed address', () {
    expect(parseHost('http://192.168.1.20:8765/app/')!.address, '192.168.1.20');
    expect(parseHost('192.168.1.20')!.port, 8765);
    expect(parseHost('10.0.0.5:9000')!.port, 9000);
    expect(parseHost('https://evil.example'), isNull);
    expect(parseHost(''), isNull);
  });

  test('lastAtOrBefore', () {
    final xs = [0.0, 1.0, 2.0];
    expect(lastAtOrBefore(xs, -1, (x) => x), -1);
    expect(lastAtOrBefore(xs, 1.5, (x) => x), 1);
    expect(lastAtOrBefore(xs, 9, (x) => x), 2);
  });

  test('solfège chord names', () {
    const sol = Notation.solfege;
    expect(chordName('G', sol), 'Sol');
    expect(chordName('F#m', sol), 'Fa#m');
    expect(chordName('Am7', sol), 'Lam7');
    expect(chordName('Bb', sol), 'Sib');
    expect(chordName('C/G', sol), 'Do/Sol');
    expect(chordName('Cadd9', sol), 'Doadd9');
    expect(chordName('N', sol), 'N');
    expect(chordName('G', Notation.letters), 'G');
  });

  test('chord names inside text, English words untouched', () {
    const sol = Notation.solfege;
    expect(withChordNames('G → C', ['G', 'C'], sol), 'Sol → Do');
    expect(withChordNames('Form A, strum once. A good shape', ['A'], sol), 'Form La, strum once. La good shape');
    expect(withChordNames('Switch Am ↔ A for 60 s', ['Am', 'A'], sol), 'Switch Lam ↔ La for 60 s');
    expect(withChordNames('Bm shape', ['B'], sol), 'Bm shape'); // B alone not inside Bm
  });
}
