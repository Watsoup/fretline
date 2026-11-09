import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/fretpack.dart';
import '../models/lesson.dart';

enum DisplayMode { rhythm, lead, full }

class Loop {
  final double start, end;
  final String label;
  const Loop(this.start, this.end, this.label);
}

/// Owns the stems and the song clock.
///
/// Three just_audio players (backing, rhythm stem, lead stem) run together;
/// backing is the master clock and the others are nudged back if they drift.
/// Speed changes keep pitch (ExoPlayer on Android, preservesPitch on web).
/// If audio fails to load, a stopwatch clock keeps the highway running.
class PlayerController extends ChangeNotifier {
  final LoadedSong song;
  PlayerController(this.song) : partId = song.lesson.parts.first.id;

  Lesson get lesson => song.lesson;
  Manifest get manifest => song.manifest;

  String partId;
  Part get part => lesson.part(partId);
  DisplayMode mode = DisplayMode.full;
  double speed = 1.0;
  Loop? loop;
  bool playing = false;
  String? audioError;

  // mixer
  double backingVol = 1.0;
  double guideVol = 0.8; // the part you are learning
  double otherVol = 0.6; // the other guitar part
  bool muteMyPart = false;

  final _backing = AudioPlayer();
  final _stems = <String, AudioPlayer>{};
  bool _audioReady = false;
  Timer? _watch;

  // fallback clock
  final _sw = Stopwatch();
  double _swBase = 0;

  Future<void> init() async {
    try {
      await _backing.setAudioSource(AudioSource.uri(song.stemUri(manifest.backingStem)));
      for (final p in lesson.parts) {
        final pl = AudioPlayer();
        await pl.setAudioSource(AudioSource.uri(song.stemUri(p.stem)));
        _stems[p.id] = pl;
      }
      _audioReady = true;
    } catch (e) {
      audioError = 'Audio could not be loaded ($e). Highway runs silent.';
    }
    _applyVolumes();
    _watch = Timer.periodic(const Duration(milliseconds: 25), (_) => _tick());
    notifyListeners();
  }

  Iterable<AudioPlayer> get _all => [_backing, ..._stems.values];

  /// Current song time in seconds (call every frame).
  double get now {
    if (_audioReady) return _backing.position.inMicroseconds / 1e6;
    return _swBase + _sw.elapsedMicroseconds / 1e6 * speed;
  }

  double get duration => manifest.duration;

  // ------------------------------------------------------------ transport
  Future<void> play() async {
    if (playing) return;
    playing = true;
    if (loop != null && (now < loop!.start || now >= loop!.end)) await seek(loop!.start);
    if (_audioReady) {
      // play() futures complete when playback stops, so don't await them
      for (final p in _all) {
        unawaited(p.play());
      }
    } else {
      _sw.start();
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    if (_audioReady) {
      await Future.wait(_all.map((p) => p.pause()));
      await _resync();
    } else {
      _swBase = now;
      _sw
        ..stop()
        ..reset();
    }
    notifyListeners();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> seek(double t) async {
    t = t.clamp(0, duration);
    if (_audioReady) {
      final d = Duration(microseconds: (t * 1e6).round());
      await Future.wait(_all.map((p) => p.seek(d)));
    } else {
      _swBase = t;
      _sw.reset();
    }
    notifyListeners();
  }

  Future<void> setSpeed(double s) async {
    final base = now;
    speed = s.clamp(0.5, 1.0);
    if (_audioReady) {
      await Future.wait(_all.map((p) => p.setSpeed(speed)));
    } else {
      _swBase = base;
      _sw.reset();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ loop / parts
  Future<void> setLoop(Loop? l, {bool jump = true}) async {
    loop = l;
    if (l != null && jump) await seek(l.start);
    notifyListeners();
  }

  void setPart(String id) {
    partId = id;
    _applyVolumes();
    notifyListeners();
  }

  void setMode(DisplayMode m) {
    mode = m;
    notifyListeners();
  }

  void setMixer({double? backing, double? guide, double? other, bool? mute}) {
    backingVol = backing ?? backingVol;
    guideVol = guide ?? guideVol;
    otherVol = other ?? otherVol;
    muteMyPart = mute ?? muteMyPart;
    _applyVolumes();
    notifyListeners();
  }

  void _applyVolumes() {
    _backing.setVolume(backingVol);
    for (final e in _stems.entries) {
      final mine = e.key == partId;
      final sameAsMine = _stems.length > 1 && lesson.part(e.key).stem == part.stem;
      double v = mine ? (muteMyPart ? 0 : guideVol) : otherVol;
      if (!mine && sameAsMine) v = 0; // single-guitar song: don't double it
      e.value.setVolume(v);
    }
  }

  // ------------------------------------------------------------ housekeeping
  int _ticks = 0;
  bool _seeking = false;

  void _tick() {
    if (!playing || _seeking) return;
    final t = now;
    final l = loop;
    if (l != null && t >= l.end) {
      _seeking = true;
      seek(l.start).whenComplete(() => _seeking = false);
      return;
    }
    if (t >= duration - 0.05) {
      pause().then((_) => seek(l?.start ?? 0));
      return;
    }
    if (_audioReady && ++_ticks % 40 == 0) _resync(); // ~every second
  }

  Future<void> _resync() async {
    final master = _backing.position;
    for (final p in _stems.values) {
      if ((p.position - master).inMilliseconds.abs() > 40) await p.seek(master);
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    for (final p in _all) {
      p.dispose();
    }
    super.dispose();
  }
}
