import '../data/progress.dart';
import '../models/lesson.dart';
import 'controller.dart';
import '../models/notation.dart';

/// Which display mode a skill opens in (doc: change -> Rhythm, riff -> Lead).
DisplayMode modeFor(Skill s) => switch (s.type) {
      SkillType.shape || SkillType.change || SkillType.strum => DisplayMode.rhythm,
      SkillType.riff => DisplayMode.lead,
      SkillType.section || SkillType.song => DisplayMode.full,
    };

/// Loop window for one occurrence of a skill.
Loop loopFor(Lesson lesson, Skill s, int occurrence) {
  final d = s.drill;
  if (d.loopStart != null && d.loopEnd != null && d.loopEnd! > d.loopStart!) {
    return Loop(d.loopStart!, d.loopEnd!, skillName(s));
  }
  final occ = s.occurs.isEmpty ? 0.0 : s.occurs[occurrence % s.occurs.length];
  final bar = lesson.barStart(occ + 0.01);
  final len = lesson.barLen(occ);
  return switch (s.type) {
    // the bar before the change + the bar of the change
    SkillType.change => Loop((lesson.barStart(bar - 0.01)).clamp(0, double.infinity), bar + len, skillName(s)),
    SkillType.strum => Loop(bar, bar + 2 * len, skillName(s)),
    _ => Loop(bar, bar + len, skillName(s)),
  };
}

/// Puts the player into a skill's drill: mode, loop, tempo from progress.
Future<void> startDrill(PlayerController ctl, Skill s, SkillProgress p, {int occurrence = 0}) async {
  ctl.setMode(modeFor(s));
  await ctl.setSpeed(p.tempo);
  await ctl.setLoop(loopFor(ctl.lesson, s, occurrence));
}
