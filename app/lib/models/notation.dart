import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lesson.dart';

/// How note / chord names are shown. Lessons always store letter names
/// ("G", "F#m", "C/G"); this only changes the display.
enum Notation {
  letters('C D E', 'English letters'),
  solfege('Do Ré Mi', 'Fixed do (Europe)');

  final String sample, label;
  const Notation(this.sample, this.label);
}

final notation = ValueNotifier<Notation>(Notation.letters);

const _prefKey = 'notation';
const _solfegeLanguages = {'fr', 'it', 'es', 'pt', 'ro', 'ca'};
const _solfege = {'C': 'Do', 'D': 'Ré', 'E': 'Mi', 'F': 'Fa', 'G': 'Sol', 'A': 'La', 'B': 'Si'};

/// Saved choice, else solfège for languages that learn with it.
Future<void> loadNotation() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_prefKey);
  if (saved != null) {
    notation.value = Notation.values.firstWhere((n) => n.name == saved, orElse: () => Notation.letters);
  } else {
    final lang = PlatformDispatcher.instance.locale.languageCode;
    notation.value = _solfegeLanguages.contains(lang) ? Notation.solfege : Notation.letters;
  }
}

Future<void> setNotation(Notation n) async {
  notation.value = n;
  await (await SharedPreferences.getInstance()).setString(_prefKey, n.name);
}

final _root = RegExp(r'^([A-G])([#b♯♭]?)(.*)$');

/// "G" -> "Sol", "F#m" -> "Fa#m", "Am7" -> "Lam7", "C/G" -> "Do/Sol", "N" -> "N".
String chordName(String name, [Notation? n]) {
  if ((n ?? notation.value) == Notation.letters) return name;
  return name.split('/').map((part) {
    final m = _root.firstMatch(part);
    if (m == null) return part;
    return '${_solfege[m[1]]}${m[2]}${m[3]}';
  }).join('/');
}

/// Replace the given chord names inside free text ("Form G, strum once").
/// Only names listed in [chords] are touched, so English words stay intact.
String withChordNames(String text, Iterable<String> chords, [Notation? n]) {
  if ((n ?? notation.value) == Notation.letters || chords.isEmpty) return text;
  final names = chords.toSet().toList()..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(r'(?<![\w#♯♭])(' + names.map(RegExp.escape).join('|') + r')(?![\w#♯♭])');
  return text.replaceAllMapped(pattern, (m) => chordName(m[1]!, n));
}

String skillName(Skill s) => withChordNames(s.name, s.drill.chords);
String? drillText(Skill s) => s.drill.text == null ? null : withChordNames(s.drill.text!, s.drill.chords);
