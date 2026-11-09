# Fretline — AI Guitar Tutor Design Doc

Nov 2, 2026 · @Gabriel

## Overview

Fretline (working name) turns any song file into a playable, graded guitar lesson: the PC does the heavy AI analysis once, and a tablet plays it back as a Just Dance-style note highway with chords and strum arrows.

**User flow**

1. Drop a song (MP3/FLAC/WAV) into the desktop app.
2. The PC separates the guitar(s), transcribes notes, chords, beats and strums, and builds the skill graph.
3. The result is saved as one portable song package (`.fretpack`).
4. The tablet imports the package (LAN sync or file) and runs the lesson fully offline.
5. The player learns the song skill by skill (shapes, changes, strum pattern, riffs, tempo), while mic scoring finds weak spots and drills them.

**In scope for v1:** standard tuning and capo, one or two guitar parts per song, local-only processing, no accounts.

**Out of scope for v1:** bass, vocals, alternate tunings beyond capo, cloud processing, a song store.

## Architecture

All AI runs once on the PC (GPU); the tablet only decodes audio, draws the highway and runs a tiny mic model, so it works offline on mid-range hardware.

&#91;embedded content: architecture · PC pipeline to tablet player\]

The only contract between the two sides is the `.fretpack` file, so either side can be rewritten without touching the other.

## Backend pipeline (PC)

The backend is a local Python worker (managed with uv) that runs seven stages on the GPU and writes one `.fretpack`; a 4-minute song should process in a few minutes, and it never needs to run again.

| # | Stage | Model / tool | Output |
| --- | --- | --- | --- |
| 1 | Stem separation | HT-Demucs 6-stem, BS/Mel-Roformer as quality upgrade | `guitar.wav`, `backing.wav` (no guitar) |
| 2 | Lead / rhythm split | Stereo panning analysis + note clustering on the stage 3 output | `lead` and `rhythm` note groups |
| 3 | Note transcription | Basic Pitch (baseline), TART stage 1 if weights are released | Time-aligned MIDI notes |
| 4 | Technique labels | TART technique classifier (slide, bend, hammer-on, harmonic) | Per-note technique tags |
| 5 | String / fret assignment | Fretting-Transformer (tuning + capo aware) | Playable tab positions |
| 6 | Beats, chords, strums | beat\_this (beats/downbeats), BTC or Chordino (chords), onset detection on rhythm stem | Beat grid, chord timeline, strum events |
| 7 | Lesson builder | Own code (rule-based simplification) | Skill graph, drills, sections |

**Strum direction** is the one stage with no off-the-shelf model. v1 uses a heuristic: compare onset times of low vs high strings inside each strum (low first = down) and fall back to the conventional pattern (downs on beats, ups on off-beats). A small classifier trained on self-recorded strums is the v2 upgrade.

**Section detection** (intro, verse, chorus) comes from self-similarity on chroma features, so the app can loop "the chorus" by name.

**Stack:** Python 3.12 + uv, PyTorch (CUDA), FastAPI for the local job API, a small desktop shell (Tauri or the same Flutter app in desktop mode) for drag-and-drop and progress.

## Song package (.fretpack)

A `.fretpack` is a plain zip with audio stems plus one JSON lesson file, so the tablet needs zero AI and any device can play it.

| File | Content |
| --- | --- |
| `manifest.json` | Title, artist, duration, BPM, key, tuning, capo, schema version, source file hash |
| `lesson.json` | Parts, notes, chords, strums, beat grid, sections, skill graph (see below) |
| `stems/guitar_lead.opus` | Isolated lead guitar |
| `stems/guitar_rhythm.opus` | Isolated rhythm guitar (same as lead if only one part) |
| `stems/backing.opus` | Everything except guitars, for play-along |
| `tab.musicxml` | Optional export for MuseScore / Guitar Pro |

**Core `lesson.json` shape** (times in seconds, positions in beats):

```json
{
  "beats": [0.00, 0.52, 1.04],
  "sections": [{"name": "Chorus", "start": 32.1, "end": 48.7}],
  "parts": [{
    "id": "rhythm",
    "chords": [{"t": 0.00, "name": "G", "frets": [3,2,0,0,0,3]}],
    "strums": [{"t": 0.00, "dir": "down", "muted": false}],
    "notes": [{"t": 0.00, "dur": 0.5, "string": 6, "fret": 3, "tech": null}],
    "skills": [{"id": "chg-C-D", "type": "change", "needs": ["shape-C", "shape-D"], "occurs": [12.4, 16.6], "drill": "..."}]
  }]
}
```

**Transfer between devices**

- LAN sync: the PC app advertises itself via mDNS; the tablet browses and pulls packages over HTTP. No cloud, no account.
- Manual: export the file and open it on the tablet (AirDrop, USB, Syncthing).
- Packages contain copyrighted audio stems, so they stay personal: no sharing feature in v1.

## Frontend (tablet)

The tablet app is a Flutter player whose main screen is a horizontal note highway: the current event sits highlighted on a fixed "now" line and the next 2 to 4 events scroll in from the right, so the player always sees what to play and what comes next.

&#91;embedded content: note highway mockup · chord, strum and tab lanes\]

Everything left of the dashed line has been played; events fade the further ahead they are, so the eye stays on the next two or three.

**Main screen, top to bottom**

1. **Chord lane** — the current chord diagram large and highlighted, the next one or two smaller and dimmed, with a countdown ring (beats until change).
2. **Strum lane** — down and up arrows on the beat grid; the current strum glows, ghost strums (muted / skipped) are outlined, accented strums are bold.
3. **Tab lane** — six string lines with fret numbers flowing toward the now line, technique marks (slide, bend, hammer-on) drawn on the note.
4. **Fretboard strip** — a mini neck showing where the current fingers go, with the next shape faded in early.
5. **Transport bar** — play, section picker ("loop chorus"), speed 50 to 100 %, part toggle (lead / rhythm), mute my part.

**Display modes:** a Rhythm mode shows chord + strum lanes only; a Lead mode shows tab + fretboard only; Full shows all. The skill being practised sets the default mode (a chord change opens Rhythm mode, a riff opens Lead mode).

**Playback:** stems mixed live (backing + optional guide guitar at adjustable volume), time-stretched without pitch change via Rubber Band (or SoundTouch) so slowed practice still sounds right.

**Mic feedback (on device, lightweight):** a small pitch / onset detector (Basic Pitch TFLite or CREPE-tiny) compares what the mic hears with the next expected events and scores timing (early / on time / late) and pitch (right / wrong note). Feedback is a colour flash on the event, Just Dance style: Perfect / Good / Miss.

**Library screen:** imported songs with cover, mastery % per part, and a "continue" button.

## Progression: skill-based learning

Each song is broken into small skills that are drilled and tracked separately; mic scoring finds the weakest one and the app drills it, so the player always works on what is actually holding them back.

| Skill | Example | Drill | Mastered when (starting values) |
| --- | --- | --- | --- |
| Chord shape | G, C, D | Form the shape, strum once, check every string rings | Clean shape in under 2 s, 3 times in a row |
| Chord change | G to C | One-minute changes: switch back and forth for 60 s, count clean changes | Changes per minute fast enough for the song tempo |
| Strum pattern | D D U U D U | Pattern on one easy chord or muted strings, with click | 4 bars in time at target tempo |
| Riff / phrase | Intro lick, bars 1 to 2 | Loop the phrase, slow then faster | Clean loop at target tempo |
| Section | Chorus | Play along over the backing stem | 80 % score at target tempo |
| Song | Full song | Play along, sections chained | Every section mastered |

&#91;embedded content: skill graph · example chorus\]

If mic scoring keeps catching a late C to D, the app drills that one change instead of replaying the whole chorus.

**Rules**

1. **One new variable at a time.** A step adds a new skill or raises tempo, never both.
2. **Tempo is its own dial.** Each skill starts at 60 to 70 % speed and rises in 5 % steps after clean passes.
3. **Prerequisites.** A change needs both shapes; a section needs its changes, strum pattern and riffs.
4. **Adaptive drills.** During play-along, each error is tagged to a skill (late on every C to D = that change). After repeated misses the app cuts into a 30 to 60 s drill on that skill, then drops back into the section.
5. **Spaced review.** Mastered skills come back as short warm-ups a few days later so they stick.
6. **Stepping stones.** A too-hard shape (a barre chord) can be swapped for an easier voicing or power chord, marked as temporary until the real shape is mastered.

**Song mastery %** = share of skills mastered, weighted by how often each occurs in the song. It is shown in the library, never used to order lessons.

**Lesson builder output:** the skill list, its dependencies, drill content per skill (generated from the transcription), and where each skill occurs in the song.

## Roadmap, risks, open questions

Build the player against a hand-written `lesson.json` first, then plug the AI pipeline in behind it, so the fun part is testable from week one.

**Milestones**

- [ ] M1: `.fretpack` schema + Flutter highway playing a hand-made lesson
- [ ] M2: PC pipeline v0 (Demucs + Basic Pitch + beat\_this + chords) producing real packages
- [ ] M3: Fretting-Transformer tabs, strum heuristic, skill graph builder
- [ ] M4: LAN sync PC to tablet
- [ ] M5: Mic scoring and adaptive drills
- [ ] M6: Lead / rhythm split, technique labels (TART)

**Risks**

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Two guitars bleed into one stem | Wrong notes in both parts | Panning analysis, let the user correct part assignment |
| Transcription errors on dense mixes | Unplayable tabs | In-app tab editor; full song marked "AI draft" |
| Strum direction guessed wrong | Bad habits | Conventional-pattern fallback, user can flip an arrow |
| TART weights not released | No technique labels | Ship without techniques; Basic Pitch is enough for v1 |
| Mic scoring noisy in a room | Frustrating feedback | Option to plug in via audio interface; score timing before pitch |

**Open questions**

- Flutter on desktop too, or a separate Tauri shell for the PC side? -> Something lighter for desktop
- Android, iOS ? -> Mainly Android, PWA for iOS
- Support for alternate tunings (drop D) in v1? -> TBH no idea what that means, i belieb
