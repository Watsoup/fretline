"""Read / write .fretpack files (plain zip)."""

from __future__ import annotations

import json
import zipfile
from dataclasses import dataclass
from pathlib import Path

from fretline.models import Lesson, Manifest

MANIFEST = "manifest.json"
LESSON = "lesson.json"


@dataclass
class PackageContents:
    manifest: Manifest
    lesson: Lesson


def write_fretpack(
    dst: Path,
    manifest: Manifest,
    lesson: Lesson,
    files: dict[str, Path],
) -> Path:
    """files: {path inside zip: local file}. Stems are already-compressed opus,
    so they are stored, not deflated."""
    referenced = {manifest.backing_stem, *(p.stem for p in lesson.parts)}
    missing = referenced - files.keys()
    if missing:
        raise ValueError(f"package references files that were not provided: {sorted(missing)}")

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(".tmp")
    with zipfile.ZipFile(tmp, "w") as z:
        z.writestr(MANIFEST, manifest.model_dump_json(indent=2), compress_type=zipfile.ZIP_DEFLATED)
        z.writestr(LESSON, lesson.model_dump_json(exclude_none=True), compress_type=zipfile.ZIP_DEFLATED)
        for arc, local in files.items():
            z.write(local, arc, compress_type=zipfile.ZIP_STORED)
    tmp.replace(dst)
    return dst


def read_fretpack(path: Path) -> PackageContents:
    with zipfile.ZipFile(path) as z:
        manifest = Manifest.model_validate(json.loads(z.read(MANIFEST)))
        lesson = Lesson.model_validate(json.loads(z.read(LESSON)))
    return PackageContents(manifest=manifest, lesson=lesson)


def read_manifest(path: Path) -> Manifest:
    with zipfile.ZipFile(path) as z:
        return Manifest.model_validate(json.loads(z.read(MANIFEST)))
