#!/usr/bin/env python3
"""Optional loopback-only preview of an allowlisted generated archive.

The archive itself remains file:// portable. Never point this at the original
backup/private export; it only accepts a generated browse directory.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit


ASSETS = {"index.html", "viewer.js", "viewer.css", "archive-data.js", "archive-data.json", "manifest.json"}
CSP = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'none'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"


def safe_relative(value):
    return (isinstance(value, str) and bool(value) and not value.startswith("/") and
            not any(c in value for c in "\\\x00?#:") and
            all(p not in {"", ".", ".."} for p in value.split("/")))


def archive_allowlist(root):
    if root.is_symlink() or any(p.is_symlink() for p in root.absolute().parents):
        raise ValueError("Archive preview does not accept symlink roots.")
    root = root.resolve()
    if (root / "archive-data.json").is_symlink():
        raise ValueError("Archive manifest must be a generated regular file.")
    data = json.loads((root / "archive-data.json").read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or not isinstance(data.get("files"), list):
        raise ValueError("Expected a generated browse archive.")
    allowed = set(ASSETS)
    for file in data["files"]:
        path = file.get("path")
        if path is not None:
            if not safe_relative(path) or not path.startswith("attachments/"):
                raise ValueError("Unsafe attachment in archive manifest.")
            allowed.add(path)
    return root, allowed


def handler_for(root, allowed):
    class ArchiveHandler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass  # URLs may include personal filenames; no access log.

        def do_GET(self):
            self.serve(False)

        def do_HEAD(self):
            self.serve(True)

        def serve(self, head):
            expected_host = f"127.0.0.1:{self.server.server_address[1]}"
            if self.headers.get("Host") != expected_host:
                self.send_error(403)
                return
            try:
                path = unquote(urlsplit(self.path).path, errors="strict").lstrip("/") or "index.html"
            except (UnicodeError, ValueError):
                self.send_error(404)
                return
            if not safe_relative(path) or path not in allowed:
                self.send_error(404)
                return
            candidate = root.joinpath(*PurePosixPath(path).parts)
            if (not candidate.resolve().is_relative_to(root) or candidate.is_symlink() or
                    any(p.is_symlink() for p in candidate.parents if p != root.parent) or
                    not candidate.is_file()):
                self.send_error(404)
                return
            try:
                fd = os.open(candidate, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
                with os.fdopen(fd, "rb") as handle:
                    length = os.fstat(handle.fileno()).st_size
                    self.send_response(200)
                    self.send_header("Content-Type", mimetypes.guess_type(path)[0] or "application/octet-stream")
                    self.send_header("Content-Length", str(length))
                    self.send_header("Content-Security-Policy", CSP)
                    self.send_header("X-Content-Type-Options", "nosniff")
                    self.send_header("Referrer-Policy", "no-referrer")
                    self.send_header("Cross-Origin-Resource-Policy", "same-origin")
                    self.send_header("Cache-Control", "no-store")
                    if path.startswith("attachments/"):
                        self.send_header("Content-Disposition", "attachment")
                    self.end_headers()
                    if not head:
                        while True:
                            chunk = handle.read(64 * 1024)
                            if not chunk:
                                break
                            self.wfile.write(chunk)
            except (OSError, ValueError):
                # No private filesystem paths or user content in diagnostics.
                self.close_connection = True
    return ArchiveHandler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--port", type=int, default=18482)
    args = parser.parse_args()
    root, allowed = archive_allowlist(args.archive)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(root, allowed))
    print(f"Read-only archive preview: http://127.0.0.1:{server.server_address[1]}/ (Ctrl-C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
