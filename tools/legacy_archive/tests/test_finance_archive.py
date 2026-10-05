"""Independent regression checks for preservation, not finance migration."""
import copy
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "export_archive.py"
SPEC = importlib.util.spec_from_file_location("legacy_finance_export", MODULE_PATH)
EXPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORTER)


def original_finance():
    # Deliberately include fields the original Dart decoder normalizes or loses.
    return {
        "schemaVersion": 1,
        "currencyCode": "EUR",
        "currentBalanceCents": -12345,
        "contributors": [{"id": "username:old", "name": "Črt"}],
        "months": [
            {"monthKey": "2026-10", "incomesByContributorCents": {"username:old": 15123, "orphan": 29}},
            {"monthKey": "2026-10", "incomesByContributorCents": {"username:old": 91}},
        ],
        "recurringExpenses": [{"id": "r1", "category": "Rent", "amountCents": 70001,
                               "startMonthKey": "2026-01", "endMonthKey": "2026-12",
                               "contributorId": "orphan", "enabled": False}],
        "plannedExpenses": [{"id": "p1", "title": "Negative source", "category": "Misc",
                             "amountCents": -99, "monthKey": "2026-10"}],
        "recurringIncomes": [{"id": "ri1", "title": "Salary", "amountCents": 200007,
                              "startMonthKey": "2026-01", "enabled": True}],
        "plannedIncomes": [{"id": "pi1", "title": "Future", "monthKey": "2026-11",
                            "amountCents": 9007199254740993}],
        "futureField": {"token": "business-field-not-a-real-secret", "text": "</script>Črt\u2028"},
    }


class FinanceArchiveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.files = self.root / "source-files"
        self.files.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def source(self, metadata):
        db = self.root / "source.sqlite"
        connection = sqlite3.connect(db)
        connection.executescript("""
            CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE project_has_metadata
              (project_id INTEGER, name TEXT, value TEXT, changed_by INTEGER, changed_on INTEGER);
            CREATE TABLE future_finance_rules (id INTEGER, data BLOB);
            INSERT INTO projects VALUES (15, 'Synthetic only');
            INSERT INTO future_finance_rules VALUES (1, X'00FF01');
        """)
        connection.executemany("INSERT INTO project_has_metadata VALUES (15, ?, ?, 7, 123)", metadata)
        connection.commit()
        connection.close()
        before = db.read_bytes()
        source = EXPORTER.sqlite_source(db)
        self.assertEqual(before, db.read_bytes(), "Archive read must not modify its source")
        return source

    def export(self, source):
        before = copy.deepcopy(source)
        browse, private = self.root / "browse", self.root / "private"
        integrity = EXPORTER.export(source, self.files, browse, private,
                                    captured_at="2026-10-04T12:00:00Z")
        self.assertEqual(before, source)
        archive = json.loads((browse / "archive-data.json").read_text())
        private_metadata = json.loads((private / "tables/project_has_metadata.json").read_text())
        self.assertEqual(source["tables"]["project_has_metadata"], private_metadata["rows"])
        self.assertEqual(source["tables"]["project_has_metadata"], archive["tables"]["project_has_metadata"])
        self.assertEqual(source["counts"]["project_has_metadata"], integrity["tableCounts"]["project_has_metadata"]["browseExport"])
        return archive, integrity, browse, private

    def test_full_legacy_finance_raw_preserves_semantics_and_unknown_fields(self):
        original = original_finance()
        # Whitespace and Unicode are part of the original metadata value.
        raw = json.dumps(original, ensure_ascii=False, indent=3) + "\n"
        source = self.source([("ui_finance_table_v1", raw),
                              ("ui_expense_currency", "USD"),
                              ("ui_expense_budget_cents", "123456")])
        archive, integrity, _, _ = self.export(source)
        values = {row["name"]: row["value"] for row in archive["tables"]["project_has_metadata"]}
        self.assertEqual(raw, values["ui_finance_table_v1"])
        self.assertEqual(original, json.loads(values["ui_finance_table_v1"]))
        self.assertEqual("EUR", json.loads(raw)["currencyCode"])
        self.assertEqual("USD", values["ui_expense_currency"])
        self.assertTrue(integrity["complete"])

    def test_chunk_order_exact_content_and_orphan_are_all_preserved(self):
        raw = json.dumps(original_finance(), ensure_ascii=False)
        chunks = [raw[i:i + 71] for i in range(0, len(raw), 71)]
        rows = [("ui_finance_table_v1", f"@chunked:{len(chunks)}")]
        rows.extend((f"ui_finance_table_v1_chunk_{i}", chunk) for i, chunk in reversed(list(enumerate(chunks))))
        rows.append(("ui_finance_table_v1_chunk_999", "orphan-data"))
        archive, _, _, _ = self.export(self.source(rows))
        values = {r["name"]: r["value"] for r in archive["tables"]["project_has_metadata"]}
        self.assertEqual(raw, "".join(values[f"ui_finance_table_v1_chunk_{i}"] for i in range(len(chunks))))
        self.assertEqual("orphan-data", values["ui_finance_table_v1_chunk_999"])

    def test_missing_and_malformed_chunks_are_not_synthesized_or_erased(self):
        rows = [("ui_finance_table_v1", "@chunked:3"),
                ("ui_finance_table_v1_chunk_0", '{"currentBalanceCents":'),
                ("ui_finance_table_v1_chunk_2", "broken}"),
                ("ui_finance_table_v1_chunk_bad", "unknown-source")]
        archive, _, _, _ = self.export(self.source(rows))
        self.assertEqual(4, len(archive["tables"]["project_has_metadata"]))
        self.assertNotIn("ui_finance_table_v1_chunk_1", {r["name"] for r in archive["tables"]["project_has_metadata"]})

    def test_newer_schema_nonobject_and_invalid_json_are_retained_verbatim(self):
        originals = [("ui_finance_table_v1", '{"schemaVersion":99,"newRule":[1,2]}'),
                     ("raw_finance_nonobject", '["unchanged"]'),
                     ("raw_finance_invalid", '{not json,\n\t"value"}')]
        archive, _, _, _ = self.export(self.source(originals))
        values = {r["name"]: r["value"] for r in archive["tables"]["project_has_metadata"]}
        self.assertEqual(dict(originals), values)

    def test_script_transport_escapes_active_text_but_roundtrips_exact_data(self):
        raw = json.dumps(original_finance(), ensure_ascii=False)
        archive, _, browse, _ = self.export(self.source([("ui_finance_table_v1", raw)]))
        script = (browse / "archive-data.js").read_text()
        self.assertNotIn("</script>", script)
        self.assertNotIn("\u2028", script)
        payload = script.removeprefix("window.LEGACY_ARCHIVE = ").removesuffix(";\n")
        self.assertEqual(archive, json.loads(payload))

    def test_unknown_finance_tables_remain_complete_private_and_disclosed(self):
        _, integrity, _, private = self.export(self.source([("ui_finance_table_v1", "{}")]))
        unknown = json.loads((private / "tables/future_finance_rules.json").read_text())
        self.assertEqual({"$binaryBase64": "AP8B"}, unknown["rows"][0]["data"])
        self.assertEqual({"source": 1, "privateExport": 1, "browseExport": 0},
                         integrity["tableCounts"]["future_finance_rules"])
        self.assertIn("future_finance_rules", integrity["omittedTables"])
        self.assertTrue(any(w["table"] == "future_finance_rules" for w in integrity["warnings"]))

    def test_named_credentials_are_redacted_before_browser_data_serialization(self):
        tables = {
            "project_has_metadata": [{"project_id": 15, "name": "apiToken", "value": "synthetic-secret"}],
            "project_activities": [{"id": 1, "data": json.dumps({
                "amountCents": 12345, "nested": {"accessToken": "synthetic-secret", "privateKey": "synthetic-secret"}
            })}],
        }
        before = copy.deepcopy(tables)
        projected, redacted, _, warnings = EXPORTER.projection(tables)
        self.assertEqual(before, tables, "Redaction must leave the recovery source intact")
        self.assertNotIn("synthetic-secret", json.dumps(projected))
        activity = json.loads(projected["project_activities"][0]["data"])
        self.assertEqual(12345, activity["amountCents"])
        self.assertIn("project_has_metadata", redacted)
        self.assertTrue("project_activities" in redacted or any(
            item.get("table") == "project_activities" for item in warnings
        ), "Nested redaction must be declared to users of the archive")

    def viewer_text(self, metadata):
        """Execute actual viewer handlers in a text-only DOM; no browser claim."""
        archive = {"schemaVersion": 1, "generatedAt": "2026-10-04T12:00:00Z",
                   "source": {}, "files": [], "integrity": {}, "tables": {
                       "projects": [{"id": 15, "name": "Synthetic only", "is_active": 1}],
                       "project_has_metadata": [{"project_id": 15, "name": k, "value": v}
                                                for k, v in metadata]}}
        harness = r"""
const fs = require('fs'), vm = require('vm');
class Node {
  constructor(tag) { this.tag=tag; this.children=[]; this.events={}; this.text=''; }
  set textContent(value) { this.text=String(value); this.children=[]; }
  get textContent() { return this.text+this.children.map(c=>c.textContent).join(' '); }
  set innerHTML(value) { throw new Error('Unsafe HTML injection'); }
  append(...nodes) { this.children.push(...nodes); }
  replaceChildren(...nodes) { this.text=''; this.children=nodes; }
  addEventListener(type, action) { this.events[type]=action; }
  setAttribute() {}
}
const nodes = new Map();
const document = {
 getElementById: id => { if(!nodes.has(id)) nodes.set(id,new Node('div')); return nodes.get(id); },
 createElement: tag => { if(tag==='script') throw new Error('Active content'); return new Node(tag); }
};
const context = {window:{LEGACY_ARCHIVE:JSON.parse(fs.readFileSync(0,'utf8'))},document,URL};
vm.runInNewContext(fs.readFileSync(process.argv[1],'utf8'),context);
function walk(node) { return [node,...node.children.flatMap(walk)]; }
let content=nodes.get('content');
walk(content).find(n=>n.className==='project-card').events.click();
walk(content).find(n=>n.tag==='button'&&n.text==='Finance').events.click();
process.stdout.write(JSON.stringify(content.textContent));
"""
        result = subprocess.run(["node", "-e", harness,
                                 str(MODULE_PATH.parent / "viewer/viewer.js")],
                                input=json.dumps(archive), capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_viewer_preserves_exact_signed_amounts_and_finance_currency(self):
        original = original_finance()
        original["plannedIncomes"][0]["amountCents"] = 21123
        text = self.viewer_text([("ui_finance_table_v1", json.dumps(original)),
                                 ("ui_expense_currency", "USD")])
        self.assertNotIn("Tabela ni dekodirana", text)
        for expected in ["-12345", "70001", "200007", "21123", "-99", "15123", "orphan", "Ponavljajoči stroški"]:
            self.assertIn(expected, text)
        self.assertIn("EUR", text)

    def test_viewer_rejects_precision_loss_newer_schema_and_missing_chunks(self):
        oversized = json.dumps(original_finance())
        newer = original_finance()
        newer["schemaVersion"] = 99
        for metadata in [
            [("ui_finance_table_v1", oversized)],
            [("ui_finance_table_v1", json.dumps(newer))],
            [("ui_finance_table_v1", "@chunked:2"), ("ui_finance_table_v1_chunk_0", "{}")],
        ]:
            with self.subTest(metadata_kind=metadata[0][1][:12]):
                text = self.viewer_text(metadata)
                self.assertIn("Tabela ni dekodirana", text)
                self.assertIn("Izvirni projektni metapodatki", text)
                self.assertNotIn("Ponavljajoči stroški", text)


if __name__ == "__main__":
    unittest.main()
