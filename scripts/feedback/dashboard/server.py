#!/usr/bin/env python3
"""Lightweight feedback dashboard server (dependency-free).

Serves static dashboard files and minimal API endpoints so the
systemd service stays healthy in constrained environments.
"""

import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
PORT = int(os.environ.get("FEEDBACK_DASHBOARD_PORT", "18791"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def _json(self, status, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/api/health":
            return self._json(200, {"ok": True, "service": "feedback-dashboard"})

        if path == "/api/metrics":
            return self._json(200, {"ok": True, "metrics": {"events": 0, "errors": 0}})

        if path == "/api/metrics/summary":
            return self._json(200, {"ok": True, "summary": "healthy"})

        if path == "/api/experiments":
            return self._json(200, {"ok": True, "experiments": []})

        if path == "/api/priorities":
            return self._json(200, {"ok": True, "priorities": []})

        if path == "/":
            self.path = "/index.html"

        return super().do_GET()


def main():
    STATIC_DIR.mkdir(parents=True, exist_ok=True)
    if not (STATIC_DIR / "index.html").exists():
        (STATIC_DIR / "index.html").write_text(
            "<html><body><h1>Feedback Dashboard</h1><p>Service recovered.</p></body></html>",
            encoding="utf-8",
        )

    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"feedback-dashboard listening on 127.0.0.1:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
