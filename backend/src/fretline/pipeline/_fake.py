"""Placeholder implementations so the whole app runs end to end.

Nothing here listens to the audio: it fabricates a plausible G-C-D song on a
fixed tempo grid. Each function is called from a stub in stages.py; delete
the call once you write the real stage.
"""

from __future__ import annotations

import shutil

from fretline.chords import shape
from fretline.models import Chord, Drill, Section, Skill, SkillType, Strum, StrumDir, Technique
from fretline.pipeline.types import (
    BeatGrid,
    LessonSkills,
    PartSplit,
    RawNote,
    SongAnalysis,
    SongInput,
    Stems,
    TabNote,
)

FAKE_BPM = 100.0
PROGRESSION = ["G", "C", "D", "G"]
PATTERN = [StrumDir.down, None, StrumDir.down, StrumDir.up, None, StrumDir.up, StrumDir.down, StrumDir.up]


def stems(song: SongInput) -> Stems:
    guitar = song.workdir / "guitar.wav"
    backing = song.workdir / "backing.wav"
    shutil.copy(song.audio, guitar)
    shutil.copy(song.audio, backing)
    return Stems(guitar=guitar, backing=backing)


def transcribe(song: SongInput) -> list[RawNote]:
    # G major arpeggio riff on 8th notes
    riff = [55, 59, 62, 67, 62, 59, 55, 50]
    step = 60.0 / FAKE_BPM / 2
    notes: list[RawNote] = []
    t, i = 0.0, 0
    while t < song.duration - step:
        notes.append(RawNote(t=round(t, 3), dur=round(step * 0.9, 3), pitch=riff[i % len(riff)]))
        t += step
        i += 1
    return notes


def split(stems: Stems, notes: list[RawNote]) -> PartSplit:
    return PartSplit(
        lead_audio=stems.guitar,
        rhythm_audio=stems.guitar,
        lead_notes=notes,
        rhythm_notes=notes,
        single_part=True,
    )


def techniques(notes: list[RawNote]) -> list[Technique | None]:
    return [Technique.hammer_on if i % 16 == 3 else None for i in range(len(notes))]


def frets(
    notes: list[RawNote], techs: list[Technique | None], tuning: list[int], capo: int
) -> list[TabNote]:
    """Naive: lowest fret wins. Real one = Fretting-Transformer."""
    out = []
    for n, tech in zip(notes, techs):
        best = None
        for idx, open_pitch in enumerate(tuning):  # idx 0 = low E = string 6
            fret = n.pitch - open_pitch - capo
            if 0 <= fret <= 15 and (best is None or fret < best[1]):
                best = (6 - idx, fret)
        if best is None:
            continue
        out.append(TabNote(t=n.t, dur=n.dur, pitch=n.pitch, string=best[0], fret=best[1], tech=tech))
    return out


def beats(song: SongInput) -> BeatGrid:
    period = 60.0 / FAKE_BPM
    n = int(song.duration / period)
    b = [round(i * period, 3) for i in range(n)]
    return BeatGrid(beats=b, downbeats=b[::4], bpm=FAKE_BPM)


def key(song: SongInput) -> str:
    return "G"


def sections(song: SongInput, grid: BeatGrid) -> list[Section]:
    bars = grid.downbeats
    out = []
    for i in range(0, len(bars), 8):
        start = bars[i]
        end = bars[i + 8] if i + 8 < len(bars) else song.duration
        out.append(Section(name="Verse" if (i // 8) % 2 == 0 else "Chorus", start=start, end=end))
    if out:
        out[0].name = "Intro"
    return out


def chords(grid: BeatGrid) -> list[Chord]:
    return [
        Chord(t=t, name=PROGRESSION[i % 4], frets=shape(PROGRESSION[i % 4]))
        for i, t in enumerate(grid.downbeats)
    ]


def strums(grid: BeatGrid) -> list[Strum]:
    out = []
    for bar_i, bar_t in enumerate(grid.downbeats):
        bi = grid.beats.index(bar_t)
        for eighth, d in enumerate(PATTERN):
            if d is None:
                continue
            beat = bi + eighth // 2
            if beat + 1 >= len(grid.beats):
                break
            t = grid.beats[beat] + (grid.beats[beat + 1] - grid.beats[beat]) * (eighth % 2) * 0.5
            out.append(Strum(t=round(t, 3), dir=d, accent=eighth == 0))
    return out


def lesson(a: SongAnalysis) -> LessonSkills:
    out: LessonSkills = {}
    bpm = a.grid.bpm
    for part in a.parts:
        skills: list[Skill] = []
        if part.chords:
            names = sorted({c.name for c in part.chords})
            for name in names:
                skills.append(
                    Skill(
                        id=f"shape-{name}",
                        type=SkillType.shape,
                        name=f"{name} shape",
                        occurs=[c.t for c in part.chords if c.name == name],
                        weight=sum(1 for c in part.chords if c.name == name),
                        drill=Drill(kind="shape", chords=[name], text=f"Form {name}, strum once, every string rings"),
                    )
                )
            changes: dict[tuple[str, str], list[float]] = {}
            for prev, cur in zip(part.chords, part.chords[1:]):
                if prev.name != cur.name:
                    changes.setdefault((prev.name, cur.name), []).append(cur.t)
            for (x, y), occ in changes.items():
                skills.append(
                    Skill(
                        id=f"chg-{x}-{y}",
                        type=SkillType.change,
                        name=f"{x} → {y}",
                        needs=[f"shape-{x}", f"shape-{y}"],
                        occurs=occ,
                        weight=len(occ),
                        drill=Drill(kind="change", chords=[x, y], duration_s=60, target_bpm=bpm,
                                    text=f"Switch {x} ↔ {y} for 60 s, count clean changes"),
                    )
                )
            skills.append(
                Skill(
                    id="strum-main",
                    type=SkillType.strum,
                    name="Strum pattern",
                    occurs=[part.strums[0].t] if part.strums else [],
                    weight=len(part.strums) / 8,
                    drill=Drill(kind="strum", pattern=PATTERN, target_bpm=bpm, chords=["G"],
                                text="Pattern on one chord with the click"),
                )
            )
        if part.notes and part.id == "lead":
            bar = 4 * 60.0 / bpm
            skills.append(
                Skill(
                    id="riff-intro",
                    type=SkillType.riff,
                    name="Intro riff",
                    occurs=[0.0],
                    weight=4,
                    drill=Drill(kind="loop", loop_start=0.0, loop_end=round(2 * bar, 3), target_bpm=bpm,
                                text="Loop bars 1–2, slow then faster"),
                )
            )
        base = [s.id for s in skills]
        for i, sec in enumerate(a.sections):
            skills.append(
                Skill(
                    id=f"sec-{i}-{sec.name.lower()}",
                    type=SkillType.section,
                    name=sec.name,
                    needs=base,
                    occurs=[sec.start],
                    weight=(sec.end - sec.start) / 10,
                    drill=Drill(kind="play_along", loop_start=sec.start, loop_end=sec.end, target_bpm=bpm),
                )
            )
        skills.append(
            Skill(
                id="song",
                type=SkillType.song,
                name="Full song",
                needs=[s.id for s in skills if s.type == SkillType.section],
                occurs=[0.0],
                weight=1,
                drill=Drill(kind="play_along", loop_start=0.0, loop_end=a.song.duration, target_bpm=bpm),
            )
        )
        out[part.id] = skills
    return out

