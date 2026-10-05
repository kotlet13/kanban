import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "export_archive.py"
spec = importlib.util.spec_from_file_location("legacy_export", MODULE)
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.files = self.root / "source-files"
        self.files.mkdir()
        self.db = self.root / "source.sqlite"
        self.out = self.root / "browse"
        self.private = self.root / "private"
        connection = sqlite3.connect(self.db)
        connection.executescript("""
            CREATE TABLE projects(id INTEGER PRIMARY KEY, name TEXT, token TEXT, is_active INTEGER);
            CREATE TABLE users(id INTEGER PRIMARY KEY, username TEXT, password TEXT, api_access_token TEXT, twofactor_secret TEXT, name TEXT);
            CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, project_id INTEGER REFERENCES projects(id), is_active INTEGER);
            CREATE TABLE task_has_files(id INTEGER PRIMARY KEY, task_id INTEGER REFERENCES tasks(id), name TEXT, path TEXT, size INTEGER);
            CREATE TABLE project_activities(id INTEGER PRIMARY KEY, project_id INTEGER, data TEXT);
            CREATE TABLE sessions(id TEXT, data TEXT);
            CREATE TABLE plugin_custom_data(id INTEGER, binary_value BLOB);
            INSERT INTO projects VALUES(17,'Projekt č\n\u0001','public-secret',0);
            INSERT INTO users VALUES(3,'alice','hash-secret','api-secret','2fa-secret','Alice');
            INSERT INTO tasks VALUES(21,'Closed task',17,0);
            INSERT INTO tasks VALUES(22,'Open task',17,1);
            INSERT INTO sessions VALUES('auth-cookie','session-secret');
            INSERT INTO plugin_custom_data VALUES(1,x'00ff0a');
        """)
        connection.execute("INSERT INTO project_activities VALUES(?,?,?)", (4, 17, json.dumps({
            "task": {"id": 21, "title": "old title"},
            "user": {"id": 3, "password": "nested-hash", "api_access_token": "nested-token"},
            "project": {"id": 17, "token": "nested-public-token"}})))
        connection.commit()
        connection.close()

    def tearDown(self):
        self.temp.cleanup()

    def source(self):
        return exporter.sqlite_source(self.db)

    def run_export(self, source=None):
        return exporter.export(source or self.source(), self.files, self.out, self.private)

    def add_file(self, name="report.pdf", relative="tasks/abc", content=b"\x00\xffbytes\n"):
        path = self.files / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO task_has_files VALUES(?,?,?,?,?)", (9, 21, name, relative, len(content)))
        return content

    def test_all_tables_and_closed_records_retained_but_secrets_private(self):
        before = exporter.sha256_file(self.db)
        integrity = self.run_export()
        archive = json.loads((self.out / "archive-data.json").read_text())
        self.assertTrue(integrity["complete"])
        self.assertEqual([r["is_active"] for r in archive["tables"]["tasks"]], [0, 1])
        self.assertEqual(archive["tables"]["projects"][0]["name"], "Projekt č\n\u0001")
        self.assertNotIn("sessions", archive["tables"])
        self.assertNotIn("plugin_custom_data", archive["tables"])
        self.assertIn("password", integrity["redactedColumns"]["users"])
        self.assertIn("data.nested_auth_fields", integrity["redactedColumns"]["project_activities"])
        browse = (self.out / "archive-data.json").read_text()
        for value in ["public-secret", "hash-secret", "api-secret", "2fa-secret", "session-secret", "nested-token", "nested-hash"]:
            self.assertNotIn(value, browse)
        raw = json.loads((self.private / "tables/users.json").read_text())
        self.assertEqual(raw["rows"][0]["api_access_token"], "api-secret")
        binary = json.loads((self.private / "tables/plugin_custom_data.json").read_text())
        self.assertEqual(binary["rows"][0]["binary_value"], {"$binaryBase64": "AP8K"})
        self.assertEqual(before, exporter.sha256_file(self.db))
        self.assertEqual(self.private.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.private / "tables/users.json").stat().st_mode & 0o777, 0o600)

    def test_attachment_exact_bytes_hash_zero_byte_and_inventory(self):
        content = self.add_file()
        (self.files / "thumbnail").write_bytes(b"preview")
        result = self.run_export()
        data = json.loads((self.out / "archive-data.json").read_text())
        file = data["files"][0]
        self.assertEqual((self.out / file["path"]).read_bytes(), content)
        self.assertEqual(file["sha256"], exporter.sha256_file(self.files / "tasks/abc"))
        self.assertTrue(result["complete"])
        self.assertEqual(result["fileCounts"]["unreferenced"], 1)
        self.assertEqual(file["taskId"], 21)
        self.assertEqual(file["projectId"], 17)
        self.assertEqual(file["id"], 9)

    def test_valid_empty_file_is_not_missing(self):
        self.add_file(content=b"")
        result = self.run_export()
        self.assertTrue(result["complete"])
        self.assertEqual(result["fileCounts"]["copied"], 1)

    def test_missing_file_and_size_mismatch_never_claim_complete(self):
        self.add_file()
        (self.files / "tasks/abc").write_bytes(b"different")
        result = self.run_export()
        self.assertFalse(result["complete"])
        self.assertEqual(result["errors"][0]["code"], "size_mismatch")
        self.assertTrue((self.private / "tables/task_has_files.json").is_file())

    def test_traversal_and_symlink_file_fail_closed(self):
        with sqlite3.connect(self.db) as conn:
            conn.execute("INSERT INTO task_has_files VALUES(9,21,'secret','../source.sqlite',1)")
        result = self.run_export()
        self.assertFalse(result["complete"])
        data = json.loads((self.out / "archive-data.json").read_text())
        self.assertEqual(data["files"][0]["status"], "unsafe")
        self.assertIsNone(data["files"][0]["path"])

    def test_output_symlink_and_overlapping_private_root_rejected(self):
        destination = self.root / "destination"
        destination.mkdir()
        self.out.symlink_to(destination, target_is_directory=True)
        with self.assertRaises(exporter.ArchiveError):
            self.run_export()
        self.out.unlink()
        with self.assertRaises(exporter.ArchiveError):
            exporter.export(self.source(), self.files, self.out, self.out / "private")

    def test_existing_export_is_never_overwritten(self):
        self.run_export()
        before = exporter.sha256_file(self.out / "archive-data.js")
        with self.assertRaises(exporter.ArchiveError):
            self.run_export()
        self.assertEqual(before, exporter.sha256_file(self.out / "archive-data.js"))

    def test_foreign_key_and_table_count_integrity(self):
        source = self.source()
        source["tables"]["tasks"][0]["project_id"] = 999
        source["counts"]["users"] += 1
        result = self.run_export(source)
        self.assertFalse(result["complete"])
        codes = {error["code"] for error in result["errors"]}
        self.assertEqual(codes, {"broken_foreign_key", "table_count_mismatch"})

    def test_active_html_attachment_gets_download_extension(self):
        self.add_file(name="../../evil.html", content=b"<script>alert(1)</script>")
        result = self.run_export()
        data = json.loads((self.out / "archive-data.json").read_text())
        self.assertTrue(result["complete"])
        path = data["files"][0]["path"]
        self.assertTrue(path.endswith(".download"))
        self.assertNotIn("..", Path(path).parts)

    def test_js_data_does_not_form_script_tag_or_html_interpolation(self):
        with sqlite3.connect(self.db) as conn:
            conn.execute("UPDATE tasks SET title=?", ("</script><script>bad()</script>\u2028&",))
        self.run_export()
        data = (self.out / "archive-data.js").read_text()
        self.assertNotIn("</script>", data)
        self.assertNotIn("\u2028", data)
        self.assertIn("\\u003c/script\\u003e", data)
        self.assertEqual(json.loads(data[len("window.LEGACY_ARCHIVE = "):-2])["tables"]["tasks"][0]["title"],
                         "</script><script>bad()</script>\u2028&")


class MysqlExtractionTests(unittest.TestCase):
    def test_mysql_reads_snapshot_with_binary_cast_and_validates_numeric_cells(self):
        schema = '\n'.join(json.dumps(r) for r in [
            {"table": "tasks", "column": "id", "type": "int", "ordinal": 1},
            {"table": "tasks", "column": "value", "type": "decimal(10,4)", "ordinal": 2},
            {"table": "tasks", "column": "title", "type": "text", "ordinal": 3},
            {"kind": "version", "value": "8.4.11"}])
        data = json.dumps({"kind": "table", "name": "tasks", "count": 1}) + '\n' + json.dumps(
            [b'17'.hex(), b'1.2300'.hex(), 'č\n\x00'.encode().hex()])
        inspected = [{"HostConfig": {"NetworkMode": "none", "PortBindings": {}},
                      "Mounts": [{"Type": "volume", "Destination": "/var/lib/mysql"}]}]
        def query(container, database, sql):
            if "START TRANSACTION" in sql:
                self.assertIn("SET SESSION TRANSACTION READ ONLY", sql)
                self.assertIn("HEX(CAST(`id` AS BINARY))", sql)
                self.assertNotIn("HEX(`id`)", sql)
                return data
            return schema
        completed = type("Result", (), {"returncode": 0, "stdout": json.dumps(inspected)})()
        with patch.object(exporter.subprocess, "run", return_value=completed), patch.object(exporter, "mysql_query", side_effect=query):
            source = exporter.mysql_source("isolated", "legacy_archive")
        self.assertEqual(source["tables"]["tasks"][0], {"id": 17, "value": "1.2300", "title": 'č\n\x00'})
        self.assertEqual(source["rawHexCells"]["tasks"][0][0], "3137")

    @unittest.skipUnless(os.environ.get("LEGACY_ARCHIVE_TEST_CONTAINER"), "optional local MySQL numeric serialization test")
    def test_actual_mysql_integer_decimal_null_binary_unicode_newline(self):
        query = """SELECT JSON_ARRAY(HEX(CAST(17 AS BINARY)),HEX(CAST(-42 AS BINARY)),
          HEX(CAST(CAST('1.2300' AS DECIMAL(10,4)) AS BINARY)),
          HEX(CAST(CONVERT(0xc48d0a00 USING utf8mb4) AS BINARY)),HEX(CAST(0x00ff AS BINARY)),
          HEX(CAST(NULL AS BINARY)));"""
        result = exporter.mysql_query(os.environ["LEGACY_ARCHIVE_TEST_CONTAINER"], "legacy_archive", query)
        cells = json.loads(result)
        self.assertEqual(cells, ["3137", "2D3432", "312E32333030", "C48D0A00", "00FF", None])


if __name__ == "__main__":
    unittest.main()
