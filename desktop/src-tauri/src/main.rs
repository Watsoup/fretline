// Fretline desktop shell: starts the Python backend, shows the UI, stops the
// backend on exit. The UI talks to the backend at http://127.0.0.1:8765.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const PORT: u16 = 8765;

struct Backend(Mutex<Option<Child>>);

fn health_ok() -> bool {
    ureq::get(&format!("http://127.0.0.1:{PORT}/health"))
        .timeout(Duration::from_millis(400))
        .call()
        .is_ok()
}

fn backend_dir() -> PathBuf {
    std::env::var_os("FRETLINE_BACKEND")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../backend")))
}

fn start_backend() -> Option<Child> {
    if health_ok() {
        println!("[fretline] backend already running, reusing it");
        return None;
    }
    let dir = backend_dir();
    println!("[fretline] starting backend in {}", dir.display());
    let child = Command::new("uv")
        .args(["run", "fretline", "serve", "--port", &PORT.to_string()])
        .current_dir(&dir)
        .spawn();
    match child {
        Ok(c) => {
            let t0 = Instant::now();
            while t0.elapsed() < Duration::from_secs(20) && !health_ok() {
                std::thread::sleep(Duration::from_millis(200));
            }
            Some(c)
        }
        Err(e) => {
            eprintln!("[fretline] could not start backend (is uv installed?): {e}");
            None
        }
    }
}

fn main() {
    let child = start_backend();
    tauri::Builder::default()
        .manage(Backend(Mutex::new(child)))
        .build(tauri::generate_context!())
        .expect("error while building Fretline")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                use tauri::Manager;
                if let Some(mut c) = app.state::<Backend>().0.lock().unwrap().take() {
                    let _ = c.kill();
                    let _ = c.wait();
                }
            }
        });
}
