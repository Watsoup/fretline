import math
import struct
import time
import wave
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from fretline.api import create_app
from fretline.package import read_fretpack
from fretline.pipeline.runner import STAGES, check_lesson, process, run_until


@pytest.fixture
def song(tmp_path: Path) -> Path:
    p = tmp_path / "song.wav"
    sr = 8000
    with wave.open(str(p), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 196 * i / sr))) for i in range(sr * 12)))
    return p


def test_full_pipeline_writes_valid_package(song: Path, tmp_path: Path):
    seen = []
    out = process(song, tmp_path / "out", tmp_path / "work", on_progress=lambda p: seen.append(p))
    c = read_fretpack(out)
    assert c.manifest.duration == pytest.approx(12, abs=0.1)
    assert {p.id for p in c.lesson.parts} == {"lead", "rhythm"}
    check_lesson(c.lesson)
    assert seen[-1].fraction == pytest.approx(1.0)
    assert [s for s, *_ in STAGES] == list(dict.fromkeys(p.stage for p in seen))


def test_run_until_returns_stage_output(song: Path, tmp_path: Path):
    grid = run_until(song, tmp_path / "w", "beats")
    assert grid.bpm > 0 and grid.beats


def test_api_job_roundtrip(song: Path, tmp_path: Path):
    app = create_app(tmp_path / "home")
    with TestClient(app) as client:
        r = client.post("/jobs", files={"file": ("song.wav", song.read_bytes())}, data={"title": "T", "capo": "2"})
        assert r.status_code == 201, r.text
        jid = r.json()["id"]
        for _ in range(200):
            job = client.get(f"/jobs/{jid}").json()
            if job["state"] in ("done", "failed"):
                break
            time.sleep(0.05)
        assert job["state"] == "done", job
        pkgs = client.get("/packages").json()
        assert pkgs[0]["title"] == "T" and pkgs[0]["capo"] == 2
        blob = client.get(pkgs[0]["url"]).content
        assert blob[:2] == b"PK"
        lesson = client.get(f"/packages/{job['package_id']}/lesson").json()
        assert lesson["lesson"]["parts"]


def test_api_rejects_bad_input(tmp_path: Path):
    with TestClient(create_app(tmp_path / "home")) as client:
        assert client.post("/jobs", files={"file": ("x.txt", b"hi")}).status_code == 415
        assert client.get("/packages/..%2Fetc.fretpack").status_code in (400, 404)


def test_check_lesson_catches_bad_needs(song: Path, tmp_path: Path):
    out = process(song, tmp_path / "out", tmp_path / "work")
    lesson = read_fretpack(out).lesson
    lesson.parts[0].skills[0].needs = ["nope"]
    with pytest.raises(ValueError, match="needs unknown"):
        check_lesson(lesson)


def test_api_serves_file_inside_package(tmp_path: Path):
    from fretline.sample import build

    pkg = build(tmp_path)
    with TestClient(create_app(tmp_path / "home")) as client:
        assert client.post("/packages", files={"file": ("d.fretpack", pkg.read_bytes())}).status_code == 201
        r = client.get("/packages/demo000000000001/files/stems/backing.opus")
        assert r.status_code == 200 and r.headers["content-type"] == "audio/ogg"
        assert client.get("/packages/demo000000000001/files/nope").status_code == 404


def test_pairing_qr(tmp_path: Path, monkeypatch):
    import fretline.api as api

    monkeypatch.setattr(api, "lan_ip", lambda: "192.168.1.20")
    monkeypatch.setattr(api, "pair_url", lambda port, ip=None: f"http://192.168.1.20:{port}/app/")
    with TestClient(create_app(tmp_path / "home", port=8765)) as client:
        h = client.get("/health").json()
        assert h["lan"]["pair_url"] == "http://192.168.1.20:8765/app/"
        r = client.get("/lan/qr.svg")
        assert r.status_code == 200 and r.content.lstrip().startswith(b"<?xml")


def test_title_from_filename_strips_ytdlp_id():
    from fretline.pipeline.runner import title_from_filename

    assert title_from_filename(Path("Drag Racer [JYr6ckOUDqg].mp3")) == "Drag Racer"
    assert title_from_filename(Path("My Song [live].mp3")) == "My Song [live]"
    assert title_from_filename(Path("plain.wav")) == "plain"
