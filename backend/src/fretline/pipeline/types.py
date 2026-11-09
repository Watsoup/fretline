"""Inputs/outputs passed between pipeline stages.

These are internal to the PC side. The runner converts them into the
public `.fretpack` models (fretline.models) at the end.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from fretline.models import Chord, Section, Skill, Strum, Technique


@dataclass
class SongInput:
    audio: Path  # original file (mp3/flac/wav)
    workdir: Path  # scratch dir for this job; write intermediate files here
    tuning: list[int]  # MIDI, low E -> high e
    capo: int
    duration: float  # seconds


@dataclass
class Stems:
    """Stage 1 output."""

    guitar: Path  # all guitars
    backing: Path  # everything except guitars


@dataclass
class RawNote:
    """Stage 3 output: a transcribed note before string/fret assignment."""

    t: float
    dur: float
    pitch: int  # MIDI
    velocity: float = 0.8  # 0..1
    confidence: float = 1.0


@dataclass
class PartSplit:
    """Stage 2 output."""

    lead_audio: Path
    rhythm_audio: Path  # same file as lead_audio if only one guitar
    lead_notes: list[RawNote]
    rhythm_notes: list[RawNote]
    single_part: bool  # True if only one guitar was found


@dataclass
class TabNote:
    """Stage 5 output."""

    t: float
    dur: float
    pitch: int
    string: int  # 1 = high e, 6 = low E
    fret: int  # relative to capo
    tech: Technique | None = None
    tech_to_fret: int | None = None


@dataclass
class BeatGrid:
    """Stage 6a output."""

    beats: list[float]
    downbeats: list[float]
    bpm: float


@dataclass
class PartAnalysis:
    """Everything known about one part before the lesson builder runs."""

    id: str  # "lead" | "rhythm"
    audio: Path
    notes: list[TabNote]
    chords: list[Chord] = field(default_factory=list)
    strums: list[Strum] = field(default_factory=list)


@dataclass
class SongAnalysis:
    """Stage 7 input."""

    song: SongInput
    grid: BeatGrid
    key: str | None
    sections: list[Section]
    parts: list[PartAnalysis]


# Stage 7 output: skills per part id
LessonSkills = dict[str, list[Skill]]
