import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/fretpack.dart';
import '../data/progress.dart';
import '../models/lesson.dart';
import '../player/controller.dart';
import '../player/drills.dart';
import 'lanes/chord_lane.dart';
import 'lanes/fretboard_strip.dart';
import 'lanes/strum_lane.dart';
import 'lanes/tab_lane.dart';
import 'skills_sheet.dart';
import 'theme.dart';
import 'transport_bar.dart';
import '../models/notation.dart';

class PlayerScreen extends StatefulWidget {
  final LoadedSong song;
  final ProgressStore progress;
  const PlayerScreen({super.key, required this.song, required this.progress});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  late final PlayerController ctl = PlayerController(widget.song);
  final time = ValueNotifier<double>(0);
  late final Ticker _ticker;
  final _focus = FocusNode();

  Skill? drill;
  int occurrence = 0;

  String get songId => widget.song.manifest.id;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => time.value = ctl.now)..start();
    ctl.addListener(() => setState(() {}));
    ctl.init().then((_) {
      if (ctl.audioError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ctl.audioError!)));
      }
    });
    widget.progress.setLastPlayedSong(songId);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _saveMastery();
    ctl.dispose();
    time.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _saveMastery() {
    widget.progress.cacheMastery(songId, {
      for (final p in ctl.lesson.parts) p.id: widget.progress.mastery(songId, p),
    });
  }

  Future<void> _openSkills() async {
    final s = await showSkillsSheet(context, widget.progress, songId, ctl.part);
    if (s == null) return;
    occurrence = 0;
    setState(() => drill = s);
    await startDrill(ctl, s, widget.progress.skill(songId, ctl.partId, s));
  }

  Future<void> _record(PassResult r) async {
    final s = drill!;
    final before = widget.progress.skill(songId, ctl.partId, s);
    final after = await widget.progress.record(songId, ctl.partId, s, r);
    _saveMastery();
    if (!mounted) return;
    String? msg;
    if (after.mastered && !before.mastered) {
      msg = '${skillName(s)} mastered!';
    } else if (after.tempo > before.tempo) {
      msg = 'Tempo up: ${(after.tempo * 100).round()} %';
      await ctl.setSpeed(after.tempo);
    }
    if (!mounted) return;
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    }
    setState(() {});
  }

  void _exitDrill() {
    setState(() => drill = null);
    ctl.setLoop(null, jump: false);
    ctl.setSpeed(1.0);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.song.manifest;
    final part = ctl.part;
    final lesson = ctl.lesson;
    final hasChords = part.chords.isNotEmpty || part.strums.isNotEmpty;
    final hasNotes = part.notes.isNotEmpty;
    final showRhythm = ctl.mode != DisplayMode.lead && hasChords;
    final showLead = ctl.mode != DisplayMode.rhythm && hasNotes;

    final lanes = <Widget>[
      if (showRhythm) ...[
        Expanded(flex: 5, child: ChordLane(time: time, lesson: lesson, part: part)),
        Expanded(
            flex: 2,
            child: _lane('STRUM', CustomPaint(painter: StrumLanePainter(time, lesson, part), size: Size.infinite))),
      ],
      if (showLead)
        Expanded(flex: 5, child: _lane('TAB', CustomPaint(painter: TabLanePainter(time, lesson, part), size: Size.infinite))),
      Expanded(
        flex: 2,
        child: CustomPaint(
          painter: FretboardPainter(time, lesson, part, !showLead),
          size: Size.infinite,
        ),
      ),
    ];

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) ctl.toggle();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            Flexible(
              child: Text('${m.title}${m.artist.isNotEmpty ? ' — ${m.artist}' : ''}', overflow: TextOverflow.ellipsis),
            ),
            if (m.aiDraft) ...[
              const SizedBox(width: 8),
              const Tooltip(
                message: 'Transcribed by AI: expect mistakes',
                child: Chip(label: Text('AI draft', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
              ),
            ],
          ]),
          actions: [
            ValueListenableBuilder<double>(
              valueListenable: time,
              builder: (_, now, _) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(lesson.sectionAt(now)?.name ?? '', style: const TextStyle(color: C.accent, fontSize: 16)),
              ),
            ),
            if (m.capo > 0)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('Capo ${m.capo}', style: const TextStyle(color: C.dim))),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            if (drill != null) _drillBanner(drill!),
            if (!showRhythm && !showLead)
              Expanded(
                child: Center(
                  child: Text(
                    ctl.mode == DisplayMode.lead ? 'This part has no tab notes — try Rhythm mode' : 'This part has no chords — try Lead mode',
                    style: const TextStyle(color: C.dim),
                  ),
                ),
              )
            else
              ...lanes,
            TransportBar(ctl: ctl, time: time, onSkills: _openSkills),
          ]),
        ),
      ),
    );
  }

  Widget _lane(String label, Widget child) => Stack(children: [
        Positioned.fill(child: child),
        Positioned(
          left: 6,
          top: 4,
          child: Text(label, style: const TextStyle(color: C.dim, fontSize: 10, letterSpacing: 1.5)),
        ),
      ]);

  Widget _drillBanner(Skill s) {
    final p = widget.progress.skill(songId, ctl.partId, s);
    final multi = s.occurs.length > 1 && s.drill.loopStart == null;
    return Container(
      color: C.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        const Icon(Icons.school, color: C.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Drill: ${skillName(s)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              '${drillText(s) ?? ''}  ·  ${(p.tempo * 100).round()} %  ·  clean ${p.clean}${p.mastered ? '  ·  mastered' : ''}',
              style: const TextStyle(color: C.dim, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        if (multi)
          IconButton(
            tooltip: 'Next place in the song (${s.occurs.length})',
            icon: const Icon(Icons.skip_next),
            onPressed: () {
              occurrence++;
              ctl.setLoop(loopFor(ctl.lesson, s, occurrence));
            },
          ),
        // Manual self-grading until mic scoring (M5) feeds PassResult automatically.
        TextButton.icon(
          onPressed: () => _record(PassResult.clean),
          icon: const Icon(Icons.check, color: C.ok),
          label: const Text('Clean'),
        ),
        TextButton.icon(
          onPressed: () => _record(PassResult.miss),
          icon: const Icon(Icons.close, color: C.bad),
          label: const Text('Missed'),
        ),
        IconButton(tooltip: 'Exit drill', onPressed: _exitDrill, icon: const Icon(Icons.close)),
      ]),
    );
  }
}
