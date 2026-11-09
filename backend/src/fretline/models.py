"""The .fretpack contract (manifest.json + lesson.json).

This module is the single source of truth for the schema. `fretline schema`
exports it as JSON Schema into /schema so the Flutter app can follow it.

Conventions
-----------
- Times are in seconds from the start of the song.
- Strings are numbered like guitarists do: 1 = high e, 6 = low E.
- `frets` arrays (chord shapes) go low E -> high e (6 -> 1), -1 = muted (x).
- `tuning` is 6 MIDI note numbers, low E -> high e. Standard = 40 45 50 55 59 64.
  Drop D = 38 45 50 55 59 64.
- Fret numbers are relative to the capo (fret 0 = capo position).
"""

from __future__ import annotations

from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field

SCHEMA_VERSION = 1
STANDARD_TUNING = [40, 45, 50, 55, 59, 64]


class Technique(StrEnum):
    slide = "slide"
    bend = "bend"
    hammer_on = "hammer_on"
    pull_off = "pull_off"
    harmonic = "harmonic"
    vibrato = "vibrato"
    palm_mute = "palm_mute"


class StrumDir(StrEnum):
    down = "down"
    up = "up"


class SkillType(StrEnum):
    shape = "shape"
    change = "change"
    strum = "strum"
    riff = "riff"
    section = "section"
    song = "song"


# --------------------------------------------------------------------------
# lesson.json
# --------------------------------------------------------------------------


class Section(BaseModel):
    name: str
    start: float
    end: float


class Chord(BaseModel):
    t: float
    name: str
    frets: list[int] = Field(min_length=6, max_length=6)
    fingers: list[int] | None = Field(
        default=None, description="Finger per string (0 = open/none, 1-4, 5 = thumb)"
    )
    easy_of: str | None = Field(
        default=None, description="Set when this is a stepping-stone voicing of a harder chord"
    )


class Strum(BaseModel):
    t: float
    dir: StrumDir
    muted: bool = False
    accent: bool = False


class Note(BaseModel):
    t: float
    dur: float
    string: int = Field(ge=1, le=6)
    fret: int = Field(ge=0, le=24)
    pitch: int | None = Field(default=None, description="MIDI pitch (before capo), informative")
    tech: Technique | None = None
    tech_to_fret: int | None = Field(
        default=None, description="Target fret for slides / bends (in semitones for bends)"
    )


class Drill(BaseModel):
    """What the player app runs when this skill is practised."""

    kind: Literal["shape", "change", "strum", "loop", "play_along"]
    chords: list[str] = Field(default_factory=list)
    pattern: list[StrumDir | None] = Field(
        default_factory=list, description="Strum pattern on 8th notes, null = skip"
    )
    loop_start: float | None = None
    loop_end: float | None = None
    target_bpm: float | None = None
    duration_s: float | None = Field(default=None, description="e.g. 60 for one-minute changes")
    text: str | None = Field(default=None, description="Short human instruction")


class Skill(BaseModel):
    id: str
    type: SkillType
    name: str
    needs: list[str] = Field(default_factory=list)
    occurs: list[float] = Field(default_factory=list, description="Start times in the song")
    weight: float = Field(default=1.0, description="How often it occurs, for mastery %")
    drill: Drill


class Part(BaseModel):
    id: Literal["lead", "rhythm"]
    name: str
    stem: str = Field(description="Path inside the zip, e.g. stems/guitar_rhythm.opus")
    chords: list[Chord] = Field(default_factory=list)
    strums: list[Strum] = Field(default_factory=list)
    notes: list[Note] = Field(default_factory=list)
    skills: list[Skill] = Field(default_factory=list)


class Lesson(BaseModel):
    schema_version: int = SCHEMA_VERSION
    beats: list[float]
    downbeats: list[float] = Field(default_factory=list)
    sections: list[Section] = Field(default_factory=list)
    parts: list[Part]


# --------------------------------------------------------------------------
# manifest.json
# --------------------------------------------------------------------------


class Manifest(BaseModel):
    schema_version: int = SCHEMA_VERSION
    id: str = Field(description="Stable id = first 16 hex chars of source_hash")
    title: str
    artist: str = ""
    duration: float
    bpm: float
    key: str | None = None
    tuning: list[int] = Field(default_factory=lambda: list(STANDARD_TUNING), min_length=6, max_length=6)
    capo: int = Field(default=0, ge=0, le=12)
    source_hash: str = Field(description="sha256 of the original audio file")
    created_at: str
    ai_draft: bool = Field(default=True, description="True until a human checked the tab")
    backing_stem: str = "stems/backing.opus"
    cover: str | None = Field(default=None, description="Optional image path inside the zip")
