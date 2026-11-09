"""Local job API (FastAPI).

Write endpoints (submit, cancel, delete) only accept requests from this PC.
Read endpoints (list / download packages) are open to the LAN for tablet sync.
"""

from __future__ import annotations

import mimetypes
import os
import shutil
import tempfile
import zipfile
from contextlib import asynccontextmanager
from ipaddress import ip_address
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles

from fretline import __version__
from fretline.jobs import JobQueue
from fretline.lan import lan_ip, pair_url, qr_svg
from fretline.package import read_fretpack, read_manifest
from fretline.pipeline.runner import SongMeta

AUDIO_EXT = {".mp3", ".flac", ".wav", ".ogg", ".m4a", ".aac", ".opus"}
REPO = Path(__file__).resolve().parents[3]


def default_home() -> Path:
    if env := os.environ.get("FRETLINE_HOME"):
        return Path(env)
    base = os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share"
    return Path(base) / "fretline"


def local_only(request: Request) -> None:
    host = request.client.host if request.client else ""
    try:
        ok = ip_address(host).is_loopback
    except ValueError:
        ok = host in ("testclient", "localhost")
    if not ok:
        raise HTTPException(403, "only allowed from this computer")


def create_app(home: Path | None = None, port: int = 8765) -> FastAPI:
    home = home or default_home()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.queue = JobQueue(home)
        yield

    app = FastAPI(title="Fretline", version=__version__, lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

    def q(request: Request) -> JobQueue:
        return request.app.state.queue

    # ---------------------------------------------------------------- info
    @app.get("/health")
    def health():
        ip = lan_ip()
        return {
            "name": "fretline",
            "version": __version__,
            "lan": {"address": ip, "port": port, "pair_url": pair_url(port, ip)} if ip else None,
        }

    @app.get("/lan/qr.svg", include_in_schema=False)
    def pairing_qr():
        """QR code tablets scan to connect (desktop UI shows it)."""
        url = pair_url(port)
        if not url:
            raise HTTPException(503, "no LAN address; is the PC on Wi-Fi / Ethernet?")
        return Response(qr_svg(url), media_type="image/svg+xml", headers={"Cache-Control": "no-store"})

    # ---------------------------------------------------------------- jobs
    @app.post("/jobs", dependencies=[Depends(local_only)], status_code=201)
    async def submit_job(
        request: Request,
        file: UploadFile = File(...),
        title: str | None = Form(None),
        artist: str | None = Form(None),
        capo: int = Form(0),
        tuning: str | None = Form(None, description="6 MIDI numbers low->high, comma separated"),
    ):
        name = file.filename or "song"
        if Path(name).suffix.lower() not in AUDIO_EXT:
            raise HTTPException(415, f"unsupported file type; use one of {sorted(AUDIO_EXT)}")
        if not 0 <= capo <= 12:
            raise HTTPException(422, "capo must be 0..12")
        tun = None
        if tuning:
            try:
                tun = [int(x) for x in tuning.split(",")]
            except ValueError:
                raise HTTPException(422, "tuning must be 6 integers") from None
            if len(tun) != 6:
                raise HTTPException(422, "tuning must be 6 integers")
        fd, tmp = tempfile.mkstemp(prefix="fretline-up-")
        with os.fdopen(fd, "wb") as out:
            shutil.copyfileobj(file.file, out)
        job = q(request).submit(name, Path(tmp), SongMeta(title=title, artist=artist, tuning=tun, capo=capo))
        return job.public()

    @app.get("/jobs")
    def list_jobs(request: Request):
        return [j.public() for j in q(request).all()]

    @app.get("/jobs/{jid}")
    def get_job(jid: str, request: Request):
        job = q(request).get(jid)
        if not job:
            raise HTTPException(404, "no such job")
        return job.public()

    @app.post("/jobs/{jid}/cancel", dependencies=[Depends(local_only)])
    def cancel_job(jid: str, request: Request):
        if not q(request).cancel(jid):
            raise HTTPException(409, "job is not queued or running")
        return q(request).get(jid).public()  # type: ignore[union-attr]

    @app.delete("/jobs/{jid}", dependencies=[Depends(local_only)], status_code=204)
    def forget_job(jid: str, request: Request):
        if not q(request).forget(jid):
            raise HTTPException(409, "job is still active or unknown")

    # ---------------------------------------------------------------- packages
    def pkg_path(request: Request, pid: str) -> Path:
        if not pid.isalnum():
            raise HTTPException(400, "bad id")
        p = q(request).packages / f"{pid}.fretpack"
        if not p.exists():
            raise HTTPException(404, "no such package")
        return p

    @app.get("/packages")
    def list_packages(request: Request):
        out = []
        for p in sorted(q(request).packages.glob("*.fretpack"), key=lambda p: p.stat().st_mtime, reverse=True):
            try:
                m = read_manifest(p)
            except Exception as e:  # noqa: BLE001
                print(f"[packages] skipping {p.name}: {e}")
                continue
            out.append({**m.model_dump(), "size": p.stat().st_size, "url": f"/packages/{p.stem}.fretpack"})
        return out

    @app.get("/packages/{pid}.fretpack")
    def download_package(pid: str, request: Request):
        p = pkg_path(request, pid)
        m = read_manifest(p)
        safe = "".join(c for c in f"{m.artist} - {m.title}" if c.isalnum() or c in " -_").strip() or pid
        return FileResponse(p, media_type="application/zip", filename=f"{safe}.fretpack")

    @app.get("/packages/{pid}/lesson")
    def package_lesson(pid: str, request: Request):
        c = read_fretpack(pkg_path(request, pid))
        return {"manifest": c.manifest.model_dump(), "lesson": c.lesson.model_dump(exclude_none=True)}

    @app.get("/packages/{pid}/files/{path:path}")
    def package_file(pid: str, path: str, request: Request):
        """One file from inside the zip (used by the web/PWA player to stream stems)."""
        p = pkg_path(request, pid)
        with zipfile.ZipFile(p) as z:
            try:
                info = z.getinfo(path)
            except KeyError:
                raise HTTPException(404, "no such file in package") from None
            data = z.read(info)
        media = "audio/ogg" if path.endswith(".opus") else mimetypes.guess_type(path)[0] or "application/octet-stream"
        return Response(data, media_type=media, headers={"Cache-Control": "max-age=86400"})

    @app.post("/packages", dependencies=[Depends(local_only)], status_code=201)
    async def import_package(request: Request, file: UploadFile = File(...)):
        """Add a hand-made / edited .fretpack to the library."""
        fd, tmp = tempfile.mkstemp(prefix="fretline-pkg-")
        with os.fdopen(fd, "wb") as out:
            shutil.copyfileobj(file.file, out)
        try:
            c = read_fretpack(Path(tmp))
        except Exception as e:  # noqa: BLE001
            os.unlink(tmp)
            raise HTTPException(422, f"invalid .fretpack: {e}") from e
        dst = q(request).packages / f"{c.manifest.id}.fretpack"
        shutil.move(tmp, dst)
        return {**c.manifest.model_dump(), "url": f"/packages/{dst.stem}.fretpack"}

    @app.delete("/packages/{pid}", dependencies=[Depends(local_only)], status_code=204)
    def delete_package(pid: str, request: Request):
        pkg_path(request, pid).unlink()

    # ---------------------------------------------------------------- static UIs
    ui = Path(os.environ.get("FRETLINE_UI", REPO / "desktop" / "ui"))
    if ui.is_dir():
        app.mount("/ui", StaticFiles(directory=ui, html=True), name="ui")
    web = Path(os.environ.get("FRETLINE_WEB", REPO / "app" / "build" / "web"))
    if web.is_dir():
        # Flutter PWA served to iOS devices on the LAN
        app.mount("/app", StaticFiles(directory=web, html=True), name="app")

    @app.get("/", include_in_schema=False)
    def root():
        return RedirectResponse("/ui/" if ui.is_dir() else "/docs")

    return app
