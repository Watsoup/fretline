"""THE PIPELINE STAGES — this file is yours.

Every function below is called by runner.py in this order:

    1  separate_stems      audio            -> Stems
    3  transcribe_notes    guitar stem      -> RawNote[]
    2  split_parts         stems + notes    -> PartSplit          (needs stage 3)
    4  label_techniques    part audio/notes -> Technique|None[]   (per part)
    5  assign_frets        notes + techs    -> TabNote[]          (per part)
    6a detect_beats        audio            -> BeatGrid
    6b detect_key          audio            -> key name
    6c detect_sections     audio + grid     -> Section[]
    6d detect_chords       rhythm audio     -> Chord[]
    6e detect_strums       rhythm audio     -> Strum[]
    7  build_skills        everything       -> {part_id: Skill[]}

Each one currently returns FAKE data from _fake.py so the app works end to
end. Replace the body, keep the signature. Write any intermediate files into
`song.workdir`. Call `report(fraction)` with 0..1 inside long stages if you
want a smoother progress bar (optional).

Run one stage in isolation with:   uv run fretline stage <name> song.mp3
Run the whole thing with:          uv run fretline process song.mp3
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from fretline.models import Chord, Section, Strum, Technique
from fretline.pipeline import _fake
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

Report = Callable[[float], None]


def _noop(_: float) -> None:
    pass


# ---------------------------------------------------------------- stage 1
def separate_stems(song: SongInput, report: Report = _noop) -> Stems:
    """HT-Demucs 6-stem (BS/Mel-Roformer later).

    Return guitar-only and everything-but-guitar WAVs, written in song.workdir.
    """
    return _fake.stems(song)  # TODO


# ---------------------------------------------------------------- stage 3
def transcribe_notes(song: SongInput, guitar: Stems, report: Report = _noop) -> list[RawNote]:
    """Basic Pitch on the guitar stem (TART stage 1 if weights appear)."""
    return _fake.transcribe(song)  # TODO


# ---------------------------------------------------------------- stage 2
def split_parts(song: SongInput, stems: Stems, notes: list[RawNote], report: Report = _noop) -> PartSplit:
    """Lead / rhythm split: stereo panning + note clustering.

    If only one guitar: single_part=True and both audios point to the same file.
    """
    return _fake.split(stems, notes)  # TODO


# ---------------------------------------------------------------- stage 4
def label_techniques(
    song: SongInput, part_audio: Path, notes: list[RawNote], report: Report = _noop
) -> list[Technique | None]:
    """TART technique classifier. Return one entry per note (same order)."""
    return _fake.techniques(notes)  # TODO


# ---------------------------------------------------------------- stage 5
def assign_frets(
    song: SongInput, notes: list[RawNote], techs: list[Technique | None], report: Report = _noop
) -> list[TabNote]:
    """Fretting-Transformer. Must respect song.tuning and song.capo.

    Strings: 1 = high e ... 6 = low E. Fret relative to capo.
    """
    return _fake.frets(notes, techs, song.tuning, song.capo)  # TODO


# ---------------------------------------------------------------- stage 6
def detect_beats(song: SongInput, report: Report = _noop) -> BeatGrid:
    """beat_this: beat + downbeat times, global BPM."""
    return _fake.beats(song)  # TODO


def detect_key(song: SongInput, report: Report = _noop) -> str | None:
    """Key name like "G" or "Em". None if unsure."""
    return _fake.key(song)  # TODO


def detect_sections(song: SongInput, grid: BeatGrid, report: Report = _noop) -> list[Section]:
    """Self-similarity on chroma -> named sections (Intro, Verse, Chorus...)."""
    return _fake.sections(song, grid)  # TODO


def detect_chords(song: SongInput, rhythm_audio: Path, grid: BeatGrid, report: Report = _noop) -> list[Chord]:
    """BTC or Chordino. One Chord per change. fretline.chords.shape(name) gives frets."""
    return _fake.chords(grid)  # TODO


def detect_strums(
    song: SongInput, rhythm_audio: Path, grid: BeatGrid, chords: list[Chord], report: Report = _noop
) -> list[Strum]:
    """Onsets on the rhythm stem + direction heuristic (low strings first = down,
    fallback: downs on beats, ups on off-beats)."""
    return _fake.strums(grid)  # TODO


# ---------------------------------------------------------------- stage 7
def build_skills(analysis: SongAnalysis, report: Report = _noop) -> LessonSkills:
    """Lesson builder: skill graph, drills, occurrences, weights, per part id.

    Skill ids must be unique within a part; `needs` must reference ids in the
    same part. Keys of the returned dict = part ids ("lead", "rhythm").
    """
    return _fake.lesson(analysis)  # TODO
