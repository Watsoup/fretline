"""ffmpeg / ffprobe helpers (plumbing, not analysis)."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path


class AudioError(RuntimeError):
    pass


def _need(tool: str) -> str:
    path = shutil.which(tool)
    if not path:
        raise AudioError(f"{tool} not found on PATH (install ffmpeg)")
    return path


def probe(path: Path) -> dict:
    """Duration + tags of an audio file."""
    out = subprocess.run(
        [_need("ffprobe"), "-v", "error", "-print_format", "json", "-show_format", str(path)],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise AudioError(f"ffprobe failed on {path.name}: {out.stderr.strip()}")
    fmt = json.loads(out.stdout).get("format", {})
    tags = {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}
    return {
        "duration": float(fmt.get("duration", 0.0)),
        "title": tags.get("title"),
        "artist": tags.get("artist"),
    }


def to_opus(src: Path, dst: Path, bitrate: str = "128k") -> Path:
    dst.parent.mkdir(parents=True, exist_ok=True)
    out = subprocess.run(
        [_need("ffmpeg"), "-y", "-v", "error", "-i", str(src), "-vn", "-c:a", "libopus", "-b:a", bitrate, str(dst)],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise AudioError(f"ffmpeg opus encode failed: {out.stderr.strip()}")
    return dst


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
