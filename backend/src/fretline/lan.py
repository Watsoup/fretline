"""LAN address of this PC + the pairing QR code tablets scan.

The QR holds http://<ip>:<port>/app/ : the iOS camera opens the PWA from it,
the Android app reads the host out of it and remembers it.
"""

from __future__ import annotations

import io
import socket

import segno


def lan_ip() -> str | None:
    """Address of the interface on the default route (no packet is sent)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 1))
            ip = s.getsockname()[0]
            return None if ip.startswith("127.") else ip
    except OSError:
        return None


def pair_url(port: int, ip: str | None = None) -> str | None:
    ip = ip or lan_ip()
    return f"http://{ip}:{port}/app/" if ip else None


def qr_svg(text: str) -> bytes:
    buf = io.BytesIO()
    segno.make(text, error="m").save(buf, kind="svg", scale=8, border=2, dark="#14161b", light="#ffffff")
    return buf.getvalue()
