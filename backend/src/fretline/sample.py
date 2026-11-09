"""Build a demo .fretpack with synthesized audio that matches its lesson exactly.

This is the "hand-made lesson" for milestone M1: no AI involved, so the
player can be tested against known-correct data.
"""

from __future__ import annotations

import array
import math
import random
import tempfile
import wave
from datetime import UTC, datetime
from pathlib import Path

from fretline import audio
from fretline.models import STANDARD_TUNING, Lesson, Manifest, Note, Part
from fretline.package import write_fretpack
from fretline.pipeline import _fake
from fretline.pipeline.types import SongAnalysis, SongInput, PartAnalysis, RawNote, TabNote

SR = 22050
DURATION = 40.0


def _pluck(buf: array.array, t: float, midi: int, dur: float, amp: float) -> None:
    f = 440.0 * 2 ** ((midi - 69) / 12)
    start = int(t * SR)
    n = min(int(dur * SR), len(buf) - start)
    w = 2 * math.pi * f / SR
    for i in range(n):
        env = math.exp(-i / (SR * 0.35))
        x = math.sin(w * i) + 0.5 * math.sin(2 * w * i) + 0.25 * math.sin(3 * w * i)
        buf[start + i] += amp * env * x


def _write(path: Path, buf: array.array) -> Path:
    peak = max(1e-9, max(abs(x) for x in buf))
    pcm = array.array("h", (int(x / peak * 0.8 * 32767) for x in buf))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return path


def build(dst_dir: Path) -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="fretline-sample-"))
    song = SongInput(audio=tmp / "none.wav", workdir=tmp, tuning=list(STANDARD_TUNING), capo=0, duration=DURATION)
    grid = _fake.beats(song)
    sections = _fake.sections(song, grid)
    chords = _fake.chords(grid)
    strums = _fake.strums(grid)
    raw: list[RawNote] = _fake.transcribe(song)
    tabs: list[TabNote] = _fake.frets(raw, _fake.techniques(raw), song.tuning, 0)

    n = int(DURATION * SR) + SR
    rhythm = array.array("d", bytes(8 * n))
    lead = array.array("d", bytes(8 * n))
    backing = array.array("d", bytes(8 * n))

    # rhythm: strum the current chord, 12 ms between strings
    ci = 0
    for s in strums:
        while ci + 1 < len(chords) and chords[ci + 1].t <= s.t:
            ci += 1
        frets = chords[ci].frets
        strings = [(i, f) for i, f in enumerate(frets) if f >= 0]
        if s.dir == "up":
            strings.reverse()
        amp = 0.35 if s.accent else 0.25
        for k, (i, f) in enumerate(strings):
            _pluck(rhythm, s.t + k * 0.012, STANDARD_TUNING[i] + f, 0.6, amp)

    for tn in tabs:
        _pluck(lead, tn.t, tn.pitch + 12, tn.dur, 0.4)

    # backing: kick on beats, noise hat on 8ths
    rnd = random.Random(1)
    for i, b in enumerate(grid.beats):
        st = int(b * SR)
        for j in range(int(0.12 * SR)):
            if st + j < n:
                backing[st + j] += 0.9 * math.exp(-j / (SR * 0.03)) * math.sin(2 * math.pi * (55 + 60 * math.exp(-j / 400)) * j / SR)
        if i + 1 < len(grid.beats):
            for off in (0.0, 0.5):
                hs = int((b + off * (grid.beats[i + 1] - b)) * SR)
                for j in range(int(0.04 * SR)):
                    if hs + j < n:
                        backing[hs + j] += 0.15 * math.exp(-j / (SR * 0.008)) * (rnd.random() * 2 - 1)

    files = {
        "stems/guitar_rhythm.opus": audio.to_opus(_write(tmp / "r.wav", rhythm), tmp / "r.opus", "64k"),
        "stems/guitar_lead.opus": audio.to_opus(_write(tmp / "l.wav", lead), tmp / "l.opus", "64k"),
        "stems/backing.opus": audio.to_opus(_write(tmp / "b.wav", backing), tmp / "b.opus", "64k"),
    }

    parts_a = [
        PartAnalysis(id="rhythm", audio=tmp / "r.wav", notes=[], chords=chords, strums=strums),
        PartAnalysis(id="lead", audio=tmp / "l.wav", notes=tabs),
    ]
    skills = _fake.lesson(SongAnalysis(song=song, grid=grid, key="G", sections=sections, parts=parts_a))
    lesson = Lesson(
        beats=grid.beats,
        downbeats=grid.downbeats,
        sections=sections,
        parts=[
            Part(id="rhythm", name="Rhythm guitar", stem="stems/guitar_rhythm.opus",
                 chords=chords, strums=strums, skills=skills["rhythm"]),
            Part(id="lead", name="Lead guitar", stem="stems/guitar_lead.opus",
                 notes=[Note(t=t.t, dur=t.dur, string=t.string, fret=t.fret, pitch=t.pitch, tech=t.tech) for t in tabs],
                 skills=skills["lead"]),
        ],
    )
    manifest = Manifest(
        id="demo000000000001",
        title="Demo Song (G C D G)",
        artist="Fretline",
        duration=DURATION,
        bpm=grid.bpm,
        key="G",
        source_hash="0" * 64,
        created_at=datetime.now(UTC).isoformat(timespec="seconds"),
        ai_draft=False,
    )
    return write_fretpack(dst_dir / f"{manifest.id}.fretpack", manifest, lesson, files)
