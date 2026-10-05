import http.client
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

spec = importlib.util.spec_from_file_location("archive_preview", Path(__file__).resolve().parents[1] / "serve_archive.py")
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.parent = Path(self.temp.name).resolve()
        self.root = self.parent / "browse"
        self.root.mkdir()
        for name in preview.ASSETS:
            (self.root / name).write_text("generated viewer fixture")
        (self.root / "attachments").mkdir()
        (self.root / "attachments/file.bin").write_bytes(b"\x00\xffexact")
        (self.root / "unlisted.txt").write_text("not exposed")
        (self.parent / "private-secret.json").write_text("private secret")
        (self.root / "archive-data.json").write_text(json.dumps({"schemaVersion": 1,
             "files": [{"path": "attachments/file.bin"}]}))
        root, allowlist = preview.archive_allowlist(self.root)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), preview.handler_for(root, allowlist))
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join()
        self.temp.cleanup()

    def request(self, path, method="GET", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1])
        connection.request(method, path, headers=headers or {})
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_generated_assets_and_referenced_attachment_only(self):
        self.assertEqual(self.request("/")[0], 200)
        code, headers, content = self.request("/attachments/file.bin")
        self.assertEqual(code, 200)
        self.assertEqual(content, b"\x00\xffexact")
        self.assertEqual(headers["Content-Disposition"], "attachment")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Cross-Origin-Resource-Policy"], "same-origin")
        self.assertIn("connect-src 'none'", headers["Content-Security-Policy"])
        for path in ["/unlisted.txt", "/attachments/", "/private-secret.json", "/../private-secret.json",
                     "/%2e%2e/private-secret.json", "/%2e%2e%2fprivate-secret.json", "/%ff"]:
            with self.subTest(path=path):
                code, _, body = self.request(path)
                self.assertEqual(code, 404)
                self.assertNotIn(b"private secret", body)

    def test_head_has_no_body_and_post_is_not_supported(self):
        code, headers, body = self.request("/attachments/file.bin", "HEAD")
        self.assertEqual(code, 200)
        self.assertEqual(body, b"")
        self.assertEqual(int(headers["Content-Length"]), 7)
        self.assertEqual(self.request("/archive-data.js", "POST")[0], 501)

    def test_unrelated_hostname_or_missing_port_is_rejected(self):
        for host in ["evil.example", "evil.example:18482", "localhost", "127.0.0.1"]:
            with self.subTest(host=host):
                code, _, body = self.request("/archive-data.js", headers={"Host": host})
                self.assertEqual(code, 403)
                self.assertNotIn(b"generated viewer fixture", body)

    def test_changed_attachment_symlink_is_never_followed(self):
        (self.root / "attachments/file.bin").unlink()
        (self.root / "attachments/file.bin").symlink_to(self.parent / "private-secret.json")
        code, _, body = self.request("/attachments/file.bin")
        self.assertEqual(code, 404)
        self.assertNotIn(b"private secret", body)

    def test_unsafe_manifest_attachment_rejected_before_server_start(self):
        (self.root / "archive-data.json").write_text(json.dumps({"schemaVersion": 1,
             "files": [{"path": "attachments/../../private-secret.json"}]}))
        with self.assertRaises(ValueError):
            preview.archive_allowlist(self.root)


if __name__ == "__main__":
    unittest.main()
