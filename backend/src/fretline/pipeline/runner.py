"""Runs the stages in order, reports progress, assembles and writes the .fretpack."""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from fretline import audio
from fretline.models import STANDARD_TUNING, Lesson, Manifest, Note, Part
from fretline.package import write_fretpack
from fretline.pipeline import stages
from fretline.pipeline.types import PartAnalysis, SongAnalysis, SongInput

# (stage key, label, relative weight for the progress bar)
STAGES: list[tuple[str, str, float]] = [
    ("separate", "Separating guitar", 30),
    ("transcribe", "Transcribing notes", 15),
    ("split", "Splitting lead / rhythm", 5),
    ("techniques", "Labelling techniques", 10),
    ("frets", "Assigning strings and frets", 10),
    ("beats", "Finding beats", 5),
    ("key", "Finding key", 1),
    ("sections", "Finding sections", 3),
    ("chords", "Recognising chords", 8),
    ("strums", "Detecting strums", 4),
    ("lesson", "Building lesson", 3),
    ("package", "Packaging", 6),
]
_TOTAL = sum(w for *_, w in STAGES)


@dataclass
class Progress:
    stage: str
    label: str
    fraction: float  # 0..1 overall


ProgressFn = Callable[[Progress], None]


@dataclass
class SongMeta:
    title: str | None = None
    artist: str | None = None
    tuning: list[int] | None = None
    capo: int = 0


class Cancelled(Exception):
    pass


class _StopAfter(Exception):
    def __init__(self, result: object):
        self.result = result


class _Tracker:
    def __init__(self, cb: ProgressFn | None, should_cancel: Callable[[], bool] | None = None):
        self.cb = cb
        self.should_cancel = should_cancel
        self.stop_after: str | None = None
        self.done = 0.0
        self.timings: dict[str, float] = {}

    def run(self, key: str, fn: Callable[[stages.Report], object]):
        idx = next(i for i, s in enumerate(STAGES) if s[0] == key)
        _, label, weight = STAGES[idx]
        if self.should_cancel and self.should_cancel():
            raise Cancelled()

        def report(f: float) -> None:
            self._emit(key, label, self.done + weight * max(0.0, min(1.0, f)))

        report(0)
        t0 = time.perf_counter()
        try:
            result = fn(report)
        except NotImplementedError as e:
            raise StageError(key, label, f"not implemented: {e}") from e
        except Exception as e:
            raise StageError(key, label, f"{type(e).__name__}: {e}") from e
        self.timings[key] = time.perf_counter() - t0
        self.done += weight
        self._emit(key, label, self.done)
        if key == self.stop_after:
            raise _StopAfter(result)
        return result

    def _emit(self, key: str, label: str, done: float) -> None:
        if self.cb:
            self.cb(Progress(stage=key, label=label, fraction=done / _TOTAL))


class StageError(RuntimeError):
    def __init__(self, stage: str, label: str, msg: str):
        super().__init__(f"[{stage}] {label}: {msg}")
        self.stage = stage


def process(
    src: Path,
    out_dir: Path,
    workdir: Path,
    meta: SongMeta | None = None,
    on_progress: ProgressFn | None = None,
    should_cancel: Callable[[], bool] | None = None,
    _stop_after: str | None = None,
) -> Path:
    """Full pipeline: song file -> .fretpack in out_dir. Returns its path."""
    meta = meta or SongMeta()
    workdir.mkdir(parents=True, exist_ok=True)
    info = audio.probe(src)
    src_hash = audio.sha256(src)
    song = SongInput(
        audio=src,
        workdir=workdir,
        tuning=list(meta.tuning or STANDARD_TUNING),
        capo=meta.capo,
        duration=info["duration"],
    )
    tr = _Tracker(on_progress, should_cancel)
    tr.stop_after = _stop_after

    stems = tr.run("separate", lambda r: stages.separate_stems(song, r))
    raw = tr.run("transcribe", lambda r: stages.transcribe_notes(song, stems, r))
    split = tr.run("split", lambda r: stages.split_parts(song, stems, raw, r))

    part_inputs = [("rhythm", split.rhythm_audio, split.rhythm_notes), ("lead", split.lead_audio, split.lead_notes)]

    techs = tr.run(
        "techniques",
        lambda r: {pid: stages.label_techniques(song, a, n, r) for pid, a, n in part_inputs},
    )
    for pid, _, n in part_inputs:
        if len(techs[pid]) != len(n):
            raise StageError("techniques", "Labelling techniques", f"{pid}: {len(techs[pid])} labels for {len(n)} notes")
    tabs = tr.run(
        "frets",
        lambda r: {pid: stages.assign_frets(song, n, techs[pid], r) for pid, _, n in part_inputs},
    )
    grid = tr.run("beats", lambda r: stages.detect_beats(song, r))
    key = tr.run("key", lambda r: stages.detect_key(song, r))
    sections = tr.run("sections", lambda r: stages.detect_sections(song, grid, r))
    chords = tr.run("chords", lambda r: stages.detect_chords(song, split.rhythm_audio, grid, r))
    strums = tr.run("strums", lambda r: stages.detect_strums(song, split.rhythm_audio, grid, chords, r))

    parts = [
        PartAnalysis(id="rhythm", audio=split.rhythm_audio, notes=tabs["rhythm"], chords=chords, strums=strums),
        PartAnalysis(id="lead", audio=split.lead_audio, notes=tabs["lead"]),
    ]
    analysis = SongAnalysis(song=song, grid=grid, key=key, sections=sections, parts=parts)
    skills = tr.run("lesson", lambda r: stages.build_skills(analysis, r))

    def package(r: stages.Report) -> Path:
        stem_paths = {"rhythm": "stems/guitar_rhythm.opus", "lead": "stems/guitar_lead.opus"}
        if split.single_part:
            # one guitar: both parts share one stem so players don't play it twice
            stem_paths["lead"] = stem_paths["rhythm"]
        files: dict[str, Path] = {}
        enc = workdir / "enc"
        jobs = [("stems/backing.opus", stems.backing)] + list(
            {stem_paths[p.id]: p.audio for p in parts}.items()
        )
        for i, (arc, local) in enumerate(jobs):
            files[arc] = audio.to_opus(local, enc / arc)
            r((i + 1) / (len(jobs) + 1))

        lesson = Lesson(
            beats=grid.beats,
            downbeats=grid.downbeats,
            sections=sections,
            parts=[
                Part(
                    id=p.id,  # type: ignore[arg-type]
                    name="Rhythm guitar" if p.id == "rhythm" else "Lead guitar",
                    stem=stem_paths[p.id],
                    chords=sorted(p.chords, key=lambda c: c.t),
                    strums=sorted(p.strums, key=lambda s: s.t),
                    notes=sorted(
                        (
                            Note(t=n.t, dur=n.dur, string=n.string, fret=n.fret, pitch=n.pitch, tech=n.tech,
                                 tech_to_fret=n.tech_to_fret)
                            for n in p.notes
                        ),
                        key=lambda n: (n.t, -n.string),
                    ),
                    skills=skills.get(p.id, []),
                )
                for p in parts
            ],
        )
        check_lesson(lesson)
        manifest = Manifest(
            id=src_hash[:16],
            title=meta.title or info["title"] or title_from_filename(src),
            artist=meta.artist or info["artist"] or "",
            duration=song.duration,
            bpm=grid.bpm,
            key=key,
            tuning=song.tuning,
            capo=song.capo,
            source_hash=src_hash,
            created_at=datetime.now(UTC).isoformat(timespec="seconds"),
        )
        return write_fretpack(out_dir / f"{manifest.id}.fretpack", manifest, lesson, files)

    return tr.run("package", package)


_YTDLP_ID = re.compile(r"\s*\[[A-Za-z0-9_-]{11}\]$")


def title_from_filename(path: Path) -> str:
    """'Drag Racer [JYr6ckOUDqg].mp3' -> 'Drag Racer' (strips yt-dlp's video id)."""
    return _YTDLP_ID.sub("", path.stem).strip() or path.stem


def check_lesson(lesson: Lesson) -> None:
    """Catch stage bugs early with a readable message."""
    problems: list[str] = []
    for part in lesson.parts:
        ids = [s.id for s in part.skills]
        dup = {i for i in ids if ids.count(i) > 1}
        if dup:
            problems.append(f"{part.id}: duplicate skill ids {sorted(dup)}")
        known = set(ids)
        for s in part.skills:
            bad = [n for n in s.needs if n not in known]
            if bad:
                problems.append(f"{part.id}/{s.id}: needs unknown {bad}")
    for a, b in zip(lesson.beats, lesson.beats[1:]):
        if b <= a:
            problems.append(f"beats not strictly increasing at {b}")
            break
    for s in lesson.sections:
        if s.end <= s.start:
            problems.append(f"section {s.name} has end <= start")
    if problems:
        raise ValueError("invalid lesson: " + "; ".join(problems))


def run_until(src: Path, workdir: Path, stage: str, meta: SongMeta | None = None,
              on_progress: ProgressFn | None = None) -> object:
    """Debug helper: run stages up to and including `stage`, return its output."""
    if stage not in {k for k, *_ in STAGES}:
        raise ValueError(f"unknown stage {stage!r}; one of {[k for k, *_ in STAGES]}")
    try:
        process(src, workdir / "out", workdir, meta, on_progress, _stop_after=stage)
    except _StopAfter as s:
        return s.result
    raise AssertionError("unreachable")
