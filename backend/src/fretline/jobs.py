"""In-process job queue: one worker thread, one song at a time (GPU bound)."""

from __future__ import annotations

import shutil
import threading
import traceback
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path

from fretline.pipeline.runner import Cancelled, Progress, SongMeta, StageError, process


class JobState(StrEnum):
    queued = "queued"
    running = "running"
    done = "done"
    failed = "failed"
    cancelled = "cancelled"


@dataclass
class Job:
    id: str
    filename: str
    src: Path
    meta: SongMeta
    state: JobState = JobState.queued
    stage: str | None = None
    label: str = "Waiting"
    progress: float = 0.0
    error: str | None = None
    package_id: str | None = None
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat(timespec="seconds"))
    cancel: threading.Event = field(default_factory=threading.Event, repr=False)

    def public(self) -> dict:
        return {
            "id": self.id,
            "filename": self.filename,
            "state": self.state,
            "stage": self.stage,
            "label": self.label,
            "progress": round(self.progress, 4),
            "error": self.error,
            "package_id": self.package_id,
            "created_at": self.created_at,
        }


class JobQueue:
    def __init__(self, home: Path):
        self.uploads = home / "uploads"
        self.work = home / "work"
        self.packages = home / "packages"
        for d in (self.uploads, self.work, self.packages):
            d.mkdir(parents=True, exist_ok=True)
        self._jobs: dict[str, Job] = {}
        self._queue: deque[str] = deque()
        self._cv = threading.Condition()
        self._thread = threading.Thread(target=self._loop, name="fretline-worker", daemon=True)
        self._thread.start()

    # ------------------------------------------------------------ public
    def submit(self, filename: str, data_path: Path, meta: SongMeta) -> Job:
        jid = uuid.uuid4().hex[:12]
        suffix = Path(filename).suffix.lower() or ".audio"
        src = self.uploads / f"{jid}{suffix}"
        shutil.move(data_path, src)
        job = Job(id=jid, filename=filename, src=src, meta=meta)
        with self._cv:
            self._jobs[jid] = job
            self._queue.append(jid)
            self._cv.notify()
        return job

    def get(self, jid: str) -> Job | None:
        return self._jobs.get(jid)

    def all(self) -> list[Job]:
        return sorted(self._jobs.values(), key=lambda j: j.created_at, reverse=True)

    def cancel(self, jid: str) -> bool:
        job = self._jobs.get(jid)
        if not job or job.state not in (JobState.queued, JobState.running):
            return False
        job.cancel.set()
        with self._cv:
            if jid in self._queue:
                self._queue.remove(jid)
                job.state = JobState.cancelled
                job.label = "Cancelled"
        return True

    def forget(self, jid: str) -> bool:
        job = self._jobs.get(jid)
        if not job or job.state in (JobState.queued, JobState.running):
            return False
        del self._jobs[jid]
        return True

    # ------------------------------------------------------------ worker
    def _loop(self) -> None:
        while True:
            with self._cv:
                while not self._queue:
                    self._cv.wait()
                jid = self._queue.popleft()
            self._run(self._jobs[jid])

    def _run(self, job: Job) -> None:
        job.state = JobState.running
        workdir = self.work / job.id

        def on_progress(p: Progress) -> None:
            job.stage, job.label, job.progress = p.stage, p.label, p.fraction

        try:
            out = process(job.src, self.packages, workdir, job.meta, on_progress, job.cancel.is_set)
            job.package_id = out.stem
            job.state, job.label, job.progress = JobState.done, "Done", 1.0
        except Cancelled:
            job.state, job.label = JobState.cancelled, "Cancelled"
        except StageError as e:
            job.state, job.error = JobState.failed, str(e)
            traceback.print_exc()
        except Exception as e:  # noqa: BLE001
            job.state, job.error = JobState.failed, f"{type(e).__name__}: {e}"
            traceback.print_exc()
        finally:
            # keep intermediate files of failed jobs so you can inspect them
            if job.state != JobState.failed:
                shutil.rmtree(workdir, ignore_errors=True)
                job.src.unlink(missing_ok=True)
