// Dart mirror of the .fretpack schema (backend/src/fretline/models.py,
// exported as JSON Schema in /schema). Times in seconds.
// Strings: 1 = high e ... 6 = low E. Chord `frets`: low E -> high e, -1 = muted.

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;
List<double> _dl(Object? v) => (v as List? ?? const []).map(_d).toList();
List<T> _ol<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

/// Index of the last item with t <= time, or -1. Items must be sorted by t.
int lastAtOrBefore<T>(List<T> items, double time, double Function(T) t) {
  var lo = 0, hi = items.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (t(items[mid]) <= time) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

class Manifest {
  final int schemaVersion;
  final String id, title, artist, sourceHash, createdAt, backingStem;
  final double duration, bpm;
  final String? key, cover;
  final List<int> tuning;
  final int capo;
  final bool aiDraft;

  Manifest.fromJson(Map<String, dynamic> j)
      : schemaVersion = j['schema_version'] as int? ?? 1,
        id = j['id'] as String,
        title = j['title'] as String? ?? 'Untitled',
        artist = j['artist'] as String? ?? '',
        duration = _d(j['duration']),
        bpm = _d(j['bpm']),
        key = j['key'] as String?,
        tuning = (j['tuning'] as List? ?? const [40, 45, 50, 55, 59, 64]).cast<int>(),
        capo = j['capo'] as int? ?? 0,
        sourceHash = j['source_hash'] as String? ?? '',
        createdAt = j['created_at'] as String? ?? '',
        aiDraft = j['ai_draft'] as bool? ?? true,
        backingStem = j['backing_stem'] as String? ?? 'stems/backing.opus',
        cover = j['cover'] as String?;
}

class Section {
  final String name;
  final double start, end;
  Section.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        start = _d(j['start']),
        end = _d(j['end']);
}

class Chord {
  final double t;
  final String name;
  final List<int> frets;
  final List<int>? fingers;
  final String? easyOf;
  Chord.fromJson(Map<String, dynamic> j)
      : t = _d(j['t']),
        name = j['name'] as String,
        frets = (j['frets'] as List).cast<int>(),
        fingers = (j['fingers'] as List?)?.cast<int>(),
        easyOf = j['easy_of'] as String?;

  /// Lowest fretted position > 0, for drawing the diagram window.
  int get baseFret {
    final fretted = frets.where((f) => f > 0);
    if (fretted.isEmpty) return 1;
    final hi = fretted.reduce((a, b) => a > b ? a : b);
    return hi <= 4 ? 1 : fretted.reduce((a, b) => a < b ? a : b);
  }
}

enum StrumDir { down, up }

class Strum {
  final double t;
  final StrumDir dir;
  final bool muted, accent;
  Strum.fromJson(Map<String, dynamic> j)
      : t = _d(j['t']),
        dir = j['dir'] == 'up' ? StrumDir.up : StrumDir.down,
        muted = j['muted'] as bool? ?? false,
        accent = j['accent'] as bool? ?? false;
}

class TabNote {
  final double t, dur;
  final int string, fret;
  final int? pitch, techToFret;
  final String? tech;
  TabNote.fromJson(Map<String, dynamic> j)
      : t = _d(j['t']),
        dur = _d(j['dur']),
        string = j['string'] as int,
        fret = j['fret'] as int,
        pitch = j['pitch'] as int?,
        tech = j['tech'] as String?,
        techToFret = j['tech_to_fret'] as int?;
}

enum SkillType { shape, change, strum, riff, section, song }

class Drill {
  final String kind;
  final List<String> chords;
  final List<StrumDir?> pattern;
  final double? loopStart, loopEnd, targetBpm, durationS;
  final String? text;
  Drill.fromJson(Map<String, dynamic> j)
      : kind = j['kind'] as String,
        chords = (j['chords'] as List? ?? const []).cast<String>(),
        pattern = (j['pattern'] as List? ?? const [])
            .map((e) => e == null ? null : (e == 'up' ? StrumDir.up : StrumDir.down))
            .toList(),
        loopStart = (j['loop_start'] as num?)?.toDouble(),
        loopEnd = (j['loop_end'] as num?)?.toDouble(),
        targetBpm = (j['target_bpm'] as num?)?.toDouble(),
        durationS = (j['duration_s'] as num?)?.toDouble(),
        text = j['text'] as String?;
}

class Skill {
  final String id, name;
  final SkillType type;
  final List<String> needs;
  final List<double> occurs;
  final double weight;
  final Drill drill;
  Skill.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        type = SkillType.values.byName(j['type'] as String),
        needs = (j['needs'] as List? ?? const []).cast<String>(),
        occurs = _dl(j['occurs']),
        weight = _d(j['weight'] ?? 1),
        drill = Drill.fromJson(j['drill'] as Map<String, dynamic>);
}

class Part {
  final String id, name, stem;
  final List<Chord> chords;
  final List<Strum> strums;
  final List<TabNote> notes;
  final List<Skill> skills;
  Part.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? j['id'] as String,
        stem = j['stem'] as String,
        chords = _ol(j['chords'], Chord.fromJson)..sort((a, b) => a.t.compareTo(b.t)),
        strums = _ol(j['strums'], Strum.fromJson)..sort((a, b) => a.t.compareTo(b.t)),
        notes = _ol(j['notes'], TabNote.fromJson)..sort((a, b) => a.t.compareTo(b.t)),
        skills = _ol(j['skills'], Skill.fromJson);

  Chord? chordAt(double t) {
    final i = lastAtOrBefore(chords, t, (c) => c.t);
    return i < 0 ? null : chords[i];
  }

  Skill? skill(String id) {
    for (final s in skills) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class Lesson {
  final List<double> beats, downbeats;
  final List<Section> sections;
  final List<Part> parts;
  Lesson.fromJson(Map<String, dynamic> j)
      : beats = _dl(j['beats']),
        downbeats = _dl(j['downbeats']),
        sections = _ol(j['sections'], Section.fromJson),
        parts = _ol(j['parts'], Part.fromJson);

  Part part(String id) => parts.firstWhere((p) => p.id == id, orElse: () => parts.first);

  /// Seconds per beat around time t (falls back to 0.5 s).
  double beatLen(double t) {
    if (beats.length < 2) return 0.5;
    final i = lastAtOrBefore(beats, t, (b) => b).clamp(0, beats.length - 2);
    return beats[i + 1] - beats[i];
  }

  /// Beats from t until `until` (fractional).
  double beatsBetween(double t, double until) => (until - t) / beatLen(t);

  Section? sectionAt(double t) {
    for (final s in sections) {
      if (t >= s.start && t < s.end) return s;
    }
    return null;
  }

  /// Start of the bar containing t (or t itself if no downbeats).
  double barStart(double t) {
    final i = lastAtOrBefore(downbeats, t, (b) => b);
    return i < 0 ? 0 : downbeats[i];
  }

  double barLen(double t) => 4 * beatLen(t);
}
