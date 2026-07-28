#!/usr/bin/env python3
"""Tiny stdlib-only HTTP server that appends RSVP submissions to a CSV file.

Listens on 127.0.0.1 only — Caddy is the only thing that talks to it,
proxying just the /api/rsvp path from the public site.
"""

import csv
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = int(os.environ.get("RSVP_PORT", "8098"))
CSV_PATH = os.environ.get("RSVP_CSV_PATH", "/var/lib/sundrop-cafe/rsvps.csv")
CSV_HEADER = ["timestamp", "name", "phone", "coming"]
MAX_BODY_BYTES = 4096


def ensure_csv():
    if not os.path.exists(CSV_PATH):
        os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
        with open(CSV_PATH, "w", newline="") as f:
            csv.writer(f).writerow(CSV_HEADER)


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/api/rsvp":
            self._send_json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send_json(400, {"error": "invalid request body"})
            return

        raw = self.rfile.read(length)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid json"})
            return

        name = str(data.get("name", "")).strip()[:200]
        phone = str(data.get("phone", "")).strip()[:50]
        coming = str(data.get("coming", "")).strip().lower()
        if coming not in ("yes", "no", "maybe"):
            coming = "yes"

        if not name or not phone:
            self._send_json(400, {"error": "name and phone are required"})
            return

        ensure_csv()
        with open(CSV_PATH, "a", newline="") as f:
            csv.writer(f).writerow([
                datetime.now(timezone.utc).isoformat(timespec="seconds"),
                name,
                phone,
                coming,
            ])

        self._send_json(200, {"ok": True})

    def log_message(self, fmt, *args):
        # Keep journald output terse — just method, path, status.
        pass


def main():
    ensure_csv()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"sundrop-rsvp listening on {HOST}:{PORT}, writing to {CSV_PATH}")
    server.serve_forever()


if __name__ == "__main__":
    main()
