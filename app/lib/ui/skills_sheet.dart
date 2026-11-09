import 'package:flutter/material.dart';

import '../data/progress.dart';
import '../models/lesson.dart';
import 'theme.dart';
import '../models/notation.dart';

const _typeLabel = {
  SkillType.shape: 'Chord shapes',
  SkillType.change: 'Chord changes',
  SkillType.strum: 'Strum patterns',
  SkillType.riff: 'Riffs & phrases',
  SkillType.section: 'Sections',
  SkillType.song: 'Whole song',
};

/// Skill list for the current part. Returns the chosen skill (or null).
Future<Skill?> showSkillsSheet(BuildContext context, ProgressStore store, String songId, Part part) {
  final suggested = store.suggest(songId, part);
  return showModalBottomSheet<Skill>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, scroll) {
        final prog = store.part(songId, part.id);
        final mastery = store.mastery(songId, part);
        return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          Row(children: [
            Text('${part.name} skills', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${(mastery * 100).round()} % mastered', style: const TextStyle(color: C.dim)),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: mastery, color: C.ok, backgroundColor: C.line),
          if (suggested != null) ...[
            const SizedBox(height: 16),
            Card(
              color: C.accent.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.bolt, color: C.accent),
                title: Text('Next up: ${skillName(suggested)}'),
                subtitle: Text(drillText(suggested) ?? _typeLabel[suggested.type]!),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => Navigator.pop(context, suggested),
              ),
            ),
          ],
          for (final type in SkillType.values)
            if (part.skills.any((s) => s.type == type)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 4),
                child: Text(_typeLabel[type]!.toUpperCase(),
                    style: const TextStyle(color: C.dim, fontSize: 12, letterSpacing: 1)),
              ),
              for (final s in part.skills.where((s) => s.type == type))
                _tile(context, s, prog[s.id], store.unlocked(songId, part, s), part),
            ],
        ]);
      },
    ),
  );
}

Widget _tile(BuildContext context, Skill s, SkillProgress? p, bool unlocked, Part part) {
  final mastered = p?.mastered ?? false;
  final review = p?.dueForReview ?? false;
  final Widget lead;
  final String status;
  if (mastered && review) {
    lead = const Icon(Icons.refresh, color: C.accent);
    status = 'review';
  } else if (mastered) {
    lead = const Icon(Icons.check_circle, color: C.ok);
    status = 'mastered';
  } else if (!unlocked) {
    lead = const Icon(Icons.lock_outline, color: C.dim);
    final missing = s.needs.map((n) => part.skill(n) == null ? n : skillName(part.skill(n)!)).take(3).join(', ');
    status = 'needs $missing';
  } else {
    lead = const Icon(Icons.radio_button_unchecked, color: C.text);
    status = s.type == SkillType.shape ? 'clean ${p?.clean ?? 0}/$passesToMaster' : '${((p?.tempo ?? startTempo) * 100).round()} % tempo';
  }
  return ListTile(
    dense: true,
    leading: lead,
    title: Text(skillName(s), style: TextStyle(color: unlocked || mastered ? C.text : C.dim)),
    subtitle: Text(drillText(s) ?? status, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: Text(status, style: const TextStyle(color: C.dim, fontSize: 12)),
    // locked skills can still be previewed; the doc's rule is about suggestions
    onTap: () => Navigator.pop(context, s),
  );
}
