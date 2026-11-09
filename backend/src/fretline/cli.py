"""fretline CLI.

  fretline serve [--port 8765]              run the local API (+ desktop UI at /ui)
  fretline process song.mp3 [-o out/]        run the full pipeline once
  fretline stage <stage> song.mp3            run up to one stage, print its output
  fretline sample [-o dir]                   write the synthetic demo .fretpack
  fretline schema [-o ../schema]             export JSON Schema of the package files
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys
import tempfile
from pathlib import Path

from pydantic import BaseModel


def _progress(p) -> None:
    bar = "#" * int(p.fraction * 30)
    print(f"\r[{bar:<30}] {p.fraction * 100:5.1f}%  {p.label:<32}", end="", file=sys.stderr, flush=True)


def _jsonable(o):
    if isinstance(o, BaseModel):
        return o.model_dump(exclude_none=True)
    if dataclasses.is_dataclass(o) and not isinstance(o, type):
        return {f.name: _jsonable(getattr(o, f.name)) for f in dataclasses.fields(o)}
    if isinstance(o, dict):
        return {str(k): _jsonable(v) for k, v in o.items()}
    if isinstance(o, list | tuple):
        return [_jsonable(v) for v in o]
    if isinstance(o, Path):
        return str(o)
    return o


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="fretline")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("serve")
    s.add_argument("--host", default="0.0.0.0")
    s.add_argument("--port", type=int, default=8765)
    s.add_argument("--local-only", action="store_true", help="bind to 127.0.0.1 (no tablet sync)")
    s.add_argument("--home", type=Path, help="data dir (default ~/.local/share/fretline)")

    p = sub.add_parser("process")
    p.add_argument("song", type=Path)
    p.add_argument("-o", "--out", type=Path, default=Path("."))
    p.add_argument("--title")
    p.add_argument("--artist")
    p.add_argument("--capo", type=int, default=0)
    p.add_argument("--keep-work", action="store_true")

    st = sub.add_parser("stage")
    st.add_argument("stage")
    st.add_argument("song", type=Path)
    st.add_argument("--capo", type=int, default=0)

    sm = sub.add_parser("sample")
    sm.add_argument("-o", "--out", type=Path, default=Path("samples"))

    sc = sub.add_parser("schema")
    sc.add_argument("-o", "--out", type=Path, default=Path(__file__).resolve().parents[3] / "schema")

    a = ap.parse_args(argv)

    if a.cmd == "serve":
        import uvicorn

        from fretline.api import create_app

        app = create_app(a.home, port=a.port)
        host = "127.0.0.1" if a.local_only else a.host
        print(f"Fretline API on http://127.0.0.1:{a.port}  (desktop UI: /ui/, docs: /docs)")
        uvicorn.run(app, host=host, port=a.port, log_level="info")
        return 0

    if a.cmd == "process":
        from fretline.pipeline.runner import SongMeta, process

        work = Path(tempfile.mkdtemp(prefix="fretline-work-"))
        out = process(a.song, a.out, work, SongMeta(title=a.title, artist=a.artist, capo=a.capo), _progress)
        print(f"\nwrote {out}")
        if a.keep_work:
            print(f"intermediate files in {work}")
        else:
            import shutil

            shutil.rmtree(work, ignore_errors=True)
        return 0

    if a.cmd == "stage":
        from fretline.pipeline.runner import SongMeta, run_until

        work = Path(tempfile.mkdtemp(prefix="fretline-stage-"))
        result = run_until(a.song, work, a.stage, SongMeta(capo=a.capo), _progress)
        print(file=sys.stderr)
        print(json.dumps(_jsonable(result), indent=2, default=str))
        print(f"(work dir: {work})", file=sys.stderr)
        return 0

    if a.cmd == "sample":
        from fretline.sample import build

        print(f"wrote {build(a.out)}")
        return 0

    if a.cmd == "schema":
        from fretline.models import Lesson, Manifest

        a.out.mkdir(parents=True, exist_ok=True)
        for name, model in (("lesson", Lesson), ("manifest", Manifest)):
            path = a.out / f"{name}.schema.json"
            path.write_text(json.dumps(model.model_json_schema(), indent=2) + "\n")
            print(f"wrote {path}")
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
