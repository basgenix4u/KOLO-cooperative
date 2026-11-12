#!/usr/bin/env python3
"""Serve the Flutter web build and proxy the API on the same origin.

The browser build talks to `/api/v1/...` rather than to `127.0.0.1:8000`. That
matters for two reasons:

  * a page served from one origin cannot call another without CORS, and a
    CORS-sandboxed origin under a preview host is exactly the case that breaks;
  * a browser is not the machine running this server, so `localhost` in the
    client would point at the viewer's own laptop.

So this serves the built app and forwards `/api/` to the Django process beside
it. One origin, no CORS, and it works from anywhere the port is reachable.

Usage:
    python tool/serve_web.py [--port 8080] [--api http://127.0.0.1:8000]
"""

from __future__ import annotations

import argparse
import http.server
import socketserver
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "build" / "web"
API_TARGET = "http://127.0.0.1:8000"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, fmt: str, *args) -> None:  # quieter than the default
        print(f"web {self.address_string()} {fmt % args}", flush=True)

    # -- API proxy ---------------------------------------------------------
    def _proxy(self, method: str) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None

        target = API_TARGET.rstrip("/") + self.path
        request = urllib.request.Request(target, data=body, method=method)

        # Forward the headers that matter and nothing else. In particular the
        # Host header of the preview origin must not be passed on, or Django's
        # ALLOWED_HOSTS check rejects a request that is otherwise fine.
        for header in ("Content-Type", "Authorization", "Accept", "Idempotency-Key"):
            value = self.headers.get(header)
            if value:
                request.add_header(header, value)

        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
                status = response.status
                content_type = response.headers.get("Content-Type", "application/json")
        except urllib.error.HTTPError as error:
            payload = error.read()
            status = error.code
            content_type = error.headers.get("Content-Type", "application/json")
        except Exception as error:  # noqa: BLE001 - the browser needs an answer
            payload = f'{{"error":{{"code":"proxy_unavailable","message":"{error}"}}}}'.encode()
            status = 502
            content_type = "application/json"

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:  # noqa: N802 - http.server's naming
        if self.path.startswith("/api/"):
            self._proxy("GET")
            return
        # A client-side route such as /groups/ajo must serve the app shell, not a
        # 404, or a refreshed deep link breaks.
        if not (ROOT / self.path.lstrip("/")).exists() and "." not in self.path.rsplit("/", 1)[-1]:
            self.path = "/index.html"
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        self._proxy("POST")

    def do_PATCH(self) -> None:  # noqa: N802
        self._proxy("PATCH")

    def do_PUT(self) -> None:  # noqa: N802
        self._proxy("PUT")

    def do_DELETE(self) -> None:  # noqa: N802
        self._proxy("DELETE")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--api", default="http://127.0.0.1:8000")
    args = parser.parse_args()

    global API_TARGET
    API_TARGET = args.api

    if not (ROOT / "index.html").exists():
        print(f"No web build at {ROOT}. Run: flutter build web --release")
        return 1

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", args.port), Handler) as httpd:
        print(f"Serving {ROOT} on http://0.0.0.0:{args.port} (API → {API_TARGET})", flush=True)
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
