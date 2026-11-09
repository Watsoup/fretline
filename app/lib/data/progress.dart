import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';

/// Design doc rules implemented here:
///  2. Tempo is its own dial: start at 65 %, +5 % after clean passes.
///  3. Prerequisites: a skill unlocks when all `needs` are mastered.
///  5. Spaced review: mastered skills come back after a few days.
const startTempo = 0.65;
const tempoStep = 0.05;
const passesPerStep = 2; // clean passes needed before tempo goes up
const passesToMaster = 3; // clean passes at 100 % (shape: at any tempo)
const reviewAfter = Duration(days: 3);

class SkillProgress {
  double tempo;
  int clean;
  bool mastered;
  DateTime? masteredAt;
  DateTime? lastPlayed;

  SkillProgress({this.tempo = startTempo, this.clean = 0, this.mastered = false, this.masteredAt, this.lastPlayed});

  Map<String, dynamic> toJson() => {
        'tempo': tempo,
        'clean': clean,
        'mastered': mastered,
        'masteredAt': masteredAt?.toIso8601String(),
        'lastPlayed': lastPlayed?.toIso8601String(),
      };

  factory SkillProgress.fromJson(Map<String, dynamic> j) => SkillProgress(
        tempo: (j['tempo'] as num?)?.toDouble() ?? startTempo,
        clean: j['clean'] as int? ?? 0,
        mastered: j['mastered'] as bool? ?? false,
        masteredAt: DateTime.tryParse(j['masteredAt'] as String? ?? ''),
        lastPlayed: DateTime.tryParse(j['lastPlayed'] as String? ?? ''),
      );

  bool get dueForReview =>
      mastered && (lastPlayed ?? masteredAt ?? DateTime.now()).isBefore(DateTime.now().subtract(reviewAfter));
}

enum PassResult { clean, miss }

class ProgressStore {
  final SharedPreferences _prefs;
  ProgressStore._(this._prefs);
  static Future<ProgressStore> open() async => ProgressStore._(await SharedPreferences.getInstance());

  String _key(String songId, String partId) => 'progress.$songId.$partId';

  Map<String, SkillProgress> part(String songId, String partId) {
    final raw = _prefs.getString(_key(songId, partId));
    if (raw == null) return {};
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return j.map((k, v) => MapEntry(k, SkillProgress.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> _save(String songId, String partId, Map<String, SkillProgress> m) =>
      _prefs.setString(_key(songId, partId), jsonEncode(m.map((k, v) => MapEntry(k, v.toJson()))));

  SkillProgress skill(String songId, String partId, Skill s) =>
      part(songId, partId)[s.id] ?? SkillProgress(tempo: s.type == SkillType.shape ? 1.0 : startTempo);

  bool unlocked(String songId, Part p, Skill s) {
    final prog = part(songId, p.id);
    return s.needs.every((n) => prog[n]?.mastered ?? false);
  }

  /// Record one attempt. Rule 1 (one new variable at a time) holds because
  /// tempo only moves after clean passes on an already-unlocked skill.
  Future<SkillProgress> record(String songId, String partId, Skill s, PassResult r) async {
    final m = part(songId, partId);
    final p = m[s.id] ?? SkillProgress(tempo: s.type == SkillType.shape ? 1.0 : startTempo);
    p.lastPlayed = DateTime.now();
    if (r == PassResult.miss) {
      p.clean = 0;
    } else {
      p.clean++;
      final atFull = p.tempo >= 0.999;
      if (!atFull && p.clean >= passesPerStep) {
        p.tempo = (p.tempo + tempoStep).clamp(0.5, 1.0);
        p.clean = 0;
      } else if (atFull && p.clean >= passesToMaster && !p.mastered) {
        p.mastered = true;
        p.masteredAt = DateTime.now();
      }
    }
    m[s.id] = p;
    await _save(songId, partId, m);
    return p;
  }

  Future<void> reset(String songId, String partId, Skill s) async {
    final m = part(songId, partId)..remove(s.id);
    await _save(songId, partId, m);
  }

  /// Song mastery % for one part: weighted share of mastered skills.
  double mastery(String songId, Part p) {
    final prog = part(songId, p.id);
    var total = 0.0, done = 0.0;
    for (final s in p.skills) {
      total += s.weight;
      if (prog[s.id]?.mastered ?? false) done += s.weight;
    }
    return total == 0 ? 0 : done / total;
  }

  /// Weakest unlocked, unmastered skill = what to practise next.
  Skill? suggest(String songId, Part p) {
    final prog = part(songId, p.id);
    Skill? review;
    for (final s in p.skills) {
      final sp = prog[s.id];
      if (sp != null && sp.dueForReview) review ??= s;
      if (!(sp?.mastered ?? false) && unlocked(songId, p, s)) return s;
    }
    return review;
  }

  // --- per-song mastery cache for the library screen (no lesson loaded there)
  Future<void> cacheMastery(String songId, Map<String, double> byPart) =>
      _prefs.setString('mastery.$songId', jsonEncode(byPart));

  Map<String, double> cachedMastery(String songId) {
    final raw = _prefs.getString('mastery.$songId');
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  String? get lastHost => _prefs.getString('lan.lastHost');
  Future<void> setLastHost(String h) => _prefs.setString('lan.lastHost', h);
  String? get lastPlayedSong => _prefs.getString('lastPlayedSong');
  Future<void> setLastPlayedSong(String id) => _prefs.setString('lastPlayedSong', id);
}
