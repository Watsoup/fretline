import 'package:flutter/material.dart';

import '../player/controller.dart';
import 'theme.dart';

String fmt(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

/// Play, section picker (loop), speed 50-100 %, part toggle, mode, mixer.
class TransportBar extends StatelessWidget {
  final PlayerController ctl;
  final ValueNotifier<double> time;
  final VoidCallback onSkills;
  const TransportBar({super.key, required this.ctl, required this.time, required this.onSkills});

  @override
  Widget build(BuildContext context) {
    final lesson = ctl.lesson;
    return Container(
      color: C.panel,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // scrub bar with section markers
        ValueListenableBuilder<double>(
          valueListenable: time,
          builder: (context, now, _) => Row(children: [
            SizedBox(width: 44, child: Text(fmt(now), style: const TextStyle(color: C.dim, fontSize: 12))),
            Expanded(
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(child: CustomPaint(painter: _SectionMarks(ctl))),
                Slider(
                  value: now.clamp(0, ctl.duration),
                  max: ctl.duration <= 0 ? 1 : ctl.duration,
                  onChanged: (v) => ctl.seek(v),
                ),
              ]),
            ),
            SizedBox(width: 44, child: Text(fmt(ctl.duration), style: const TextStyle(color: C.dim, fontSize: 12))),
          ]),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            IconButton.filled(
              iconSize: 32,
              onPressed: ctl.toggle,
              icon: Icon(ctl.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Back one bar',
              onPressed: () => ctl.seek(ctl.now - lesson.barLen(ctl.now)),
              icon: const Icon(Icons.replay),
            ),
            _SectionPicker(ctl: ctl),
            _Speed(ctl: ctl),
            if (lesson.parts.length > 1)
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final p in lesson.parts) ButtonSegment(value: p.id, label: Text(p.id))],
                selected: {ctl.partId},
                onSelectionChanged: (s) => ctl.setPart(s.first),
              ),
            SegmentedButton<DisplayMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: DisplayMode.rhythm, label: Text('Rhythm')),
                ButtonSegment(value: DisplayMode.lead, label: Text('Lead')),
                ButtonSegment(value: DisplayMode.full, label: Text('Full')),
              ],
              selected: {ctl.mode},
              onSelectionChanged: (s) => ctl.setMode(s.first),
            ),
            FilterChip(
              label: const Text('Mute my part'),
              selected: ctl.muteMyPart,
              onSelected: (v) => ctl.setMixer(mute: v),
            ),
            IconButton(tooltip: 'Mixer', onPressed: () => _mixer(context), icon: const Icon(Icons.tune)),
            FilledButton.tonalIcon(onPressed: onSkills, icon: const Icon(Icons.school), label: const Text('Skills')),
          ],
        ),
      ]),
    );
  }

  void _mixer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.panel,
      builder: (_) => ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _vol('Backing', ctl.backingVol, (v) => ctl.setMixer(backing: v)),
            _vol('My part (guide)', ctl.guideVol, (v) => ctl.setMixer(guide: v)),
            _vol('Other guitar', ctl.otherVol, (v) => ctl.setMixer(other: v)),
          ]),
        ),
      ),
    );
  }

  Widget _vol(String label, double v, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(child: Slider(value: v, onChanged: on)),
      ]);
}

class _SectionMarks extends CustomPainter {
  final PlayerController ctl;
  _SectionMarks(this.ctl);
  @override
  void paint(Canvas c, Size s) {
    if (ctl.duration <= 0) return;
    const pad = 24.0; // Slider's horizontal padding
    final w = s.width - 2 * pad;
    for (final sec in ctl.lesson.sections) {
      final x = pad + sec.start / ctl.duration * w;
      c.drawLine(Offset(x, s.height * 0.15), Offset(x, s.height * 0.85), Paint()..color = C.line..strokeWidth = 2);
    }
    final l = ctl.loop;
    if (l != null) {
      c.drawRect(
        Rect.fromLTRB(pad + l.start / ctl.duration * w, s.height * 0.3, pad + l.end / ctl.duration * w, s.height * 0.7),
        Paint()..color = C.accent.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(_SectionMarks old) => true;
}

class _SectionPicker extends StatelessWidget {
  final PlayerController ctl;
  const _SectionPicker({required this.ctl});

  @override
  Widget build(BuildContext context) {
    final sections = ctl.lesson.sections;
    return PopupMenuButton<int>(
      tooltip: 'Loop a section',
      onSelected: (i) {
        if (i < 0) {
          ctl.setLoop(null, jump: false);
        } else {
          final s = sections[i];
          ctl.setLoop(Loop(s.start, s.end, s.name));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: -1, child: Text('No loop (whole song)')),
        for (var i = 0; i < sections.length; i++)
          PopupMenuItem(value: i, child: Text('${sections[i].name}  ·  ${fmt(sections[i].start)}')),
      ],
      child: Chip(
        avatar: Icon(Icons.repeat, size: 18, color: ctl.loop != null ? C.accent : C.dim),
        label: Text(ctl.loop?.label ?? 'Loop'),
      ),
    );
  }
}

class _Speed extends StatelessWidget {
  final PlayerController ctl;
  const _Speed({required this.ctl});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.speed, size: 18, color: C.dim),
      SizedBox(
        width: 140,
        child: Slider(
          value: ctl.speed,
          min: 0.5,
          max: 1.0,
          divisions: 10,
          label: '${(ctl.speed * 100).round()} %',
          onChanged: ctl.setSpeed,
        ),
      ),
      SizedBox(width: 44, child: Text('${(ctl.speed * 100).round()}%')),
    ]);
  }
}
