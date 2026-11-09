# Fretline

Song file → guitar lesson. The PC does the AI once and writes a `.fretpack`; the tablet plays it as a note highway, offline.
Design: [`Fretline AI Guitar Tutor Design Doc.md`](Fretline%20AI%20Guitar%20Tutor%20Design%20Doc.md).

```
backend/   Python 3.12 + uv + FastAPI   pipeline, job API, .fretpack writer, pairing QR
desktop/   Tauri shell + ui/index.html  drag-and-drop, progress, library, QR for tablets
app/       Flutter (Android + PWA)      library, note highway, skills, sync
schema/    JSON Schema of manifest.json / lesson.json (generated from backend/src/fretline/models.py)
```

## Who writes what

**The pipeline stages are yours:** `backend/src/fretline/pipeline/stages.py`.
Each function has typed inputs/outputs (`pipeline/types.py`) and currently returns fake data from
`pipeline/_fake.py`, so the full app works end to end today. Replace one body at a time.

| Order | Function | Doc stage |
| --- | --- | --- |
| 1 | `separate_stems` | Demucs |
| 2 | `transcribe_notes` | Basic Pitch |
| 3 | `split_parts` | lead / rhythm split (needs notes) |
| 4 | `label_techniques` | TART |
| 5 | `assign_frets` | Fretting-Transformer |
| 6 | `detect_beats`, `detect_key`, `detect_sections`, `detect_chords`, `detect_strums` | beat_this, chords, strum heuristic, sections |
| 7 | `build_skills` | lesson builder |

Everything else (runner, progress, packaging, validation, API, UIs) is plumbing around them.
`runner.check_lesson` rejects broken output (unknown `needs`, unsorted beats…) with a readable message.

Debug one stage without the UI:

```sh
cd backend
uv run fretline stage beats song.mp3       # runs stages up to "beats", prints its output as JSON
uv run fretline process song.mp3 -o out/   # full pipeline, writes out/<id>.fretpack
```

Stage keys: `separate transcribe split techniques frets beats key sections chords strums lesson package`.
A failed job keeps its work dir in `~/.local/share/fretline/work/<job>/` so you can inspect intermediates.

## Run it

```sh
# backend (needs ffmpeg on PATH)
cd backend && uv sync && uv run pytest
uv run fretline serve                 # http://127.0.0.1:8765/ui/   API docs at /docs
uv run fretline sample -o samples     # synthetic demo .fretpack (milestone M1 test data)
uv run fretline schema                # refresh /schema after changing models.py

# desktop shell (starts the backend itself, or reuses a running one)
cd desktop && npm install && npm run dev

# tablet app
cd app && ./setup.sh && flutter test && flutter run
```

## Practising on the PC

The desktop app has **Learn ▸** (header) and **Practice** (per song). Both open the same Flutter player
as the tablet, as a web build served by the backend at `http://127.0.0.1:8765/app/` (`?song=<id>` opens a
song directly). **Add songs** in the player goes back to the desktop page. Build it once, then restart the backend:

```sh
cd app && flutter build web --base-href /app/
```

Progress on the PC is stored in the webview (localStorage) and is separate from the tablet's.

## Pairing a tablet

The desktop UI shows a QR code for `http://<pc-ip>:8765/app/`.

- **Android:** *Get songs from PC → Scan QR*. The host is remembered; songs download and play offline.
- **iPhone/iPad:** scan with the camera to open the PWA served by the PC
  (`flutter build web --base-href /app/` first). It streams from the PC, so the PC must stay on.

Write endpoints (`POST /jobs`, deletes) only accept requests from the PC itself; the LAN can only list and download packages.

## Releasing (APK + website)

`git tag v1.2.3 && git push origin v1.2.3` runs `.github/workflows/release.yml`. It does the following:
- builds the signed APK (versionName `1.2.3`, versionCode = CI run number) and the web player
- creates a GitHub Release with the APK
- uploads `index.html` (from `site/`), `fretline-<v>.apk`, `fretline-latest.apk`, `version.json` and `play/` to the website over FTP

The web player on the site can play the demo and `.fretpack` files. Making new songs still needs the PC app.

One-time setup (repo → Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ~/.config/fretline/release.jks` |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` | `storePassword` in `~/.config/fretline/release-key.txt` |
| `ANDROID_KEY_ALIAS` | `fretline` |
| `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD` | the website's FTP user |

| Variable | Example |
| --- | --- |
| `FTP_DIR` | `./` if the FTP user's home is the site folder, else e.g. `public_html/fretline/` (ends with `/`) |
| `SITE_PATH` | URL path of that folder: `/` or `/fretline/` |
| `FTP_PROTOCOL` | `ftps` (default); `ftp` if the host has no TLS |

**Back up `~/.config/fretline/` (keystore + passwords).** Without the keystore, installed apps can't be updated.
Local release builds use the same key through `app/android/key.properties` (git-ignored).

## Status

- Done: schema, backend plumbing with fake stages (7 tests), desktop UI + Tauri shell (builds),
  Flutter player: highway (chord / strum / tab lanes, fretboard strip), transport, loop sections, speed,
  mixer, display modes, skill graph with tempo ladder + prerequisites + spaced review, library, QR sync.
- Not yet: mic scoring (M5). Drills use manual *Clean / Missed* buttons for now; mic scoring will
  feed the same `ProgressStore.record()` call.
- Flutter code has **not been compiled yet** (Flutter wasn't installed when it was written).
  Expect a few fixes on the first `flutter analyze`.
- iOS PWA: Safari's Ogg/Opus support varies by version. If stems don't play there, the backend can
  add an AAC copy of each stem.
