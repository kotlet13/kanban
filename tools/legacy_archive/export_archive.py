#!/usr/bin/env python3
"""Read an already restored LOCAL Kanboard backup; never call production/PHP.

Only Python's standard library is needed. MySQL is read through docker exec and
the container's mysql client. Original field bytes and schema are retained in
the private export; a separate projection is suitable for the offline viewer.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone


BUSINESS_TABLES = set("""action_has_params actions column_has_move_restrictions
column_has_restrictions columns comments currencies custom_filters group_has_users
groups links plugin_schema_versions predefined_task_descriptions project_activities
project_daily_column_stats project_daily_stats project_has_categories project_has_files
project_has_groups project_has_metadata project_has_notification_types project_has_roles
project_has_users project_role_has_restrictions projects schema_version subtask_time_tracking
subtasks swimlanes tags task_has_external_links task_has_files task_has_links task_has_metadata
task_has_tags tasks transitions user_has_metadata user_has_notification_types
user_has_notifications user_has_unread_notifications users""".split())
PRIVATE_TABLES = {"invites", "last_logins", "password_reset", "remember_me", "sessions", "settings"}
USER_FIELDS = set("""id username name email role is_active timezone language
notifications_enabled notifications_filter avatar_path theme""".split())
SECRET_KEYS = re.compile(r"password|passwd|secret|token|api[_-]?key|private[_-]?key|"
                         r"twofactor|two_factor|otp|authentication|authorization|csrf|"
                         r"session[_-]?id|cookie|credential", re.I)
IDENTIFIER = re.compile(r"^[A-Za-z0-9_]+$")
INTEGER = re.compile(r"^(tinyint|smallint|mediumint|int|integer|bigint)(\W|$)", re.I)


class ArchiveError(Exception):
    """A safe error: never includes database rows, passwords or query stderr."""


def identifier(value: str) -> str:
    if not IDENTIFIER.fullmatch(value):
        raise ArchiveError("Unsupported database identifier; no export was guessed.")
    return "`" + value + "`"


def mysql_query(container: str, database: str, query: str) -> str:
    # No shell, remote connection, host mount, password or user-supplied SQL.
    command = ["docker", "exec", "-i", container, "mysql", "--batch", "--raw",
               "--skip-column-names", "--binary-mode", "--default-character-set=utf8mb4",
               "-u", "root", database]
    result = subprocess.run(command, input=query, text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise ArchiveError("Local MySQL read failed; private database diagnostics were suppressed.")
    return result.stdout


def mysql_source(container: str, database: str) -> dict:
    identifier(database)
    # Prohibit accidentally attaching this tool to a published/networked service.
    result = subprocess.run(["docker", "inspect", container], text=True,
                            capture_output=True, timeout=15)
    if result.returncode:
        raise ArchiveError("Local archive container was not found.")
    info = json.loads(result.stdout)[0]
    if info["HostConfig"].get("NetworkMode") != "none" or info["HostConfig"].get("PortBindings"):
        raise ArchiveError("The archive database must use --network none and have no published ports.")
    # The official image creates an anonymous database volume. No host bind or
    # unrelated mount is accepted; root owns deletion of this disposable volume.
    if any(m.get("Type") != "volume" or m.get("Destination") != "/var/lib/mysql"
           for m in info.get("Mounts", [])):
        raise ArchiveError("The disposable archive database must have no host binds or unrelated mounts.")
    schema_sql = """SELECT JSON_OBJECT('table',TABLE_NAME,'column',COLUMN_NAME,
      'type',COLUMN_TYPE,'nullable',IS_NULLABLE,'ordinal',ORDINAL_POSITION)
      FROM information_schema.columns WHERE TABLE_SCHEMA=DATABASE()
      ORDER BY TABLE_NAME,ORDINAL_POSITION;
      SELECT JSON_OBJECT('kind','foreign_key','table',TABLE_NAME,'column',COLUMN_NAME,
      'parentTable',REFERENCED_TABLE_NAME,'parentColumn',REFERENCED_COLUMN_NAME,
      'constraint',CONSTRAINT_NAME,'ordinal',ORDINAL_POSITION)
      FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE()
      AND REFERENCED_TABLE_NAME IS NOT NULL ORDER BY TABLE_NAME,CONSTRAINT_NAME,ORDINAL_POSITION;
      SELECT JSON_OBJECT('kind','version','value',VERSION());"""
    schemas, foreign_keys, version = {}, [], None
    for line in mysql_query(container, database, schema_sql).splitlines():
        row = json.loads(line)
        if row.get("kind") == "foreign_key":
            foreign_keys.append(row)
        elif row.get("kind") == "version":
            version = row["value"]
        else:
            schemas.setdefault(row["table"], []).append(row)
    if not schemas:
        raise ArchiveError("The local database contains no exportable tables.")
    sql = ["SET SESSION TRANSACTION READ ONLY; START TRANSACTION WITH CONSISTENT SNAPSHOT;"]
    for table, columns in schemas.items():
        quoted = identifier(table)
        sql.append(f"SELECT JSON_OBJECT('kind','table','name','{table}','count',COUNT(*)) FROM {quoted};")
        # HEX avoids the mysql client's escaping, newline and NUL ambiguities.
        # Raw cells are kept separately, so float/decimal values are never rounded.
        cells = [f"IFNULL(CONCAT('\"',HEX(CAST({identifier(c['column'])} AS BINARY)),'\"'),'null')"
                 for c in columns]
        joined_cells = ", ',', ".join(cells)
        sql.append(f"SELECT CONCAT('[', {joined_cells}, ']') FROM {quoted};")
    sql.append("COMMIT;")
    tables, counts, raw_cells, current = {}, {}, {}, None
    for line in mysql_query(container, database, "\n".join(sql)).splitlines():
        row = json.loads(line)
        if isinstance(row, dict):
            current = row["name"]
            counts[current] = row["count"]
            tables[current], raw_cells[current] = [], []
        else:
            if current is None:
                raise ArchiveError("Unexpected local database output.")
            raw_cells[current].append(row)
            decoded = {}
            if len(schemas[current]) != len(row):
                raise ArchiveError("Local database returned an unexpected column count.")
            for column, cell in zip(schemas[current], row):
                value = None
                if cell is not None:
                    data = bytes.fromhex(cell)
                    try:
                        value = data.decode("utf-8")
                    except UnicodeDecodeError:
                        value = {"$binaryBase64": base64.b64encode(data).decode("ascii")}
                    if isinstance(value, str) and INTEGER.match(column["type"]):
                        value = int(value)
                decoded[column["column"]] = value
            tables[current].append(decoded)
    return {"tables": tables, "counts": counts, "schema": schemas, "foreignKeys": foreign_keys,
            "rawHexCells": raw_cells, "engine": "mysql", "engineVersion": version}


def sqlite_source(path: Path) -> dict:
    # SQLite input is a backup copy, not an application's open live database.
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("PRAGMA query_only=ON")
        connection.execute("BEGIN")
        names = [r[0] for r in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        tables, schemas, counts, foreign_keys, raw_cells = {}, {}, {}, [], {}
        for table in names:
            quoted = identifier(table)
            schemas[table] = [{"column": r[1], "type": r[2], "ordinal": r[0],
                               "nullable": not r[3]} for r in connection.execute(f"PRAGMA table_info({quoted})")]
            rows = connection.execute(f"SELECT * FROM {quoted}").fetchall()
            raw_cells[table] = []
            tables[table] = []
            for row in rows:
                tables[table].append({k: {"$binaryBase64": base64.b64encode(v).decode("ascii")}
                                     if isinstance(v, bytes) else v for k, v in dict(row).items()})
            counts[table] = connection.execute(f"SELECT COUNT(*) FROM {quoted}").fetchone()[0]
            for fk in connection.execute(f"PRAGMA foreign_key_list({quoted})"):
                foreign_keys.append({"table": table, "column": fk[3], "parentTable": fk[2],
                                     "parentColumn": fk[4], "constraint": f"{table}_{fk[0]}", "ordinal": fk[1]})
        return {"tables": tables, "counts": counts, "schema": schemas, "foreignKeys": foreign_keys,
                "rawHexCells": raw_cells, "engine": "sqlite", "engineVersion": sqlite3.sqlite_version}
    finally:
        connection.close()


def redact_nested(value):
    if isinstance(value, dict):
        semantic_secret = SECRET_KEYS.search(str(value.get("name", value.get("key", ""))))
        return {k: redact_nested(v) for k, v in value.items()
                if not SECRET_KEYS.search(k) and not (semantic_secret and k == "value")}
    if isinstance(value, list):
        return [redact_nested(v) for v in value]
    return value


def projection(tables: dict) -> tuple[dict, dict, list, list]:
    projected, redactions, omitted, warnings = {}, {}, [], []
    for table, rows in tables.items():
        if table not in BUSINESS_TABLES:
            omitted.append(table)
            if table not in PRIVATE_TABLES and table != "sqlite_sequence":
                warnings.append({"code": "private_only_unknown_table", "table": table,
                                 "message": "Unknown table retained in full in private export only."})
            continue
        projected[table] = []
        removed = set()
        for row in rows:
            result = {}
            for key, value in row.items():
                if (table == "users" and key not in USER_FIELDS) or SECRET_KEYS.search(key):
                    removed.add(key)
                    continue
                if key in {"data", "event_data"} and isinstance(value, str) and value:
                    try:
                        parsed = json.loads(value)
                        sanitized = redact_nested(parsed)
                        if sanitized != parsed:
                            removed.add(key + ".nested_auth_fields")
                            value = json.dumps(sanitized, ensure_ascii=False, separators=(",", ":"))
                    except (ValueError, TypeError):
                        removed.add(key)
                        warnings.append({"code": "unparsed_event_data", "table": table,
                                         "id": row.get("id"), "message": "Opaque event data is private-only."})
                        continue
                if key == "value" and SECRET_KEYS.search(str(row.get("name", ""))):
                    removed.add(key)
                    continue
                sanitized = redact_nested(value)
                if sanitized != value:
                    removed.add(key + ".nested_auth_fields")
                result[key] = sanitized
            projected[table].append(result)
        if removed:
            redactions[table] = sorted(removed)
    return projected, redactions, sorted(omitted), warnings


def finance_warnings(tables: dict) -> list:
    """Diagnose legacy finance decoding without changing any raw metadata."""
    by_project, warnings = {}, []
    for row in tables.get("project_has_metadata", []):
        by_project.setdefault(row.get("project_id"), {})[row.get("name")] = row.get("value")
    for project, values in by_project.items():
        marker = values.get("ui_finance_table_v1")
        chunk_keys = {key for key in values if isinstance(key, str) and key.startswith("ui_finance_table_v1_chunk_")}
        problem = None
        raw = marker
        if marker is None:
            if chunk_keys:
                problem = "orphan_chunks"
            else:
                continue
        elif isinstance(marker, str) and marker.startswith("@chunked:"):
            match = re.fullmatch(r"@chunked:([1-9][0-9]*)", marker)
            count = int(match[1]) if match and len(match[1]) < 8 else None
            if count is None or count > len(chunk_keys):
                problem = "missing_or_invalid_chunks"
            else:
                expected = {f"ui_finance_table_v1_chunk_{i}" for i in range(count)}
                if not expected.issubset(chunk_keys):
                    problem = "missing_or_invalid_chunks"
                else:
                    raw = "".join(str(values[key]) for key in [f"ui_finance_table_v1_chunk_{i}" for i in range(count)])
                    if expected != chunk_keys:
                        warnings.append({"code": "finance_orphan_chunks", "projectId": project,
                                         "message": "Extra finance chunks retained unchanged."})
        if problem is None:
            try:
                decoded = json.loads(raw)
                if not isinstance(decoded, dict) or decoded.get("schemaVersion") != 1:
                    problem = "unsupported_schema"
            except (ValueError, TypeError):
                problem = "malformed_json"
        if problem:
            warnings.append({"code": "finance_" + problem, "projectId": project,
                             "message": "Finance source cannot be safely decoded; all original metadata is retained."})
    return warnings


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_source(root: Path, relative: str) -> Path:
    posix = PurePosixPath(relative)
    if not relative or "\\" in relative or posix.is_absolute() or ".." in posix.parts:
        raise ArchiveError("Unsafe attachment path.")
    candidate = root.joinpath(*posix.parts)
    if not candidate.resolve().is_relative_to(root.resolve()):
        raise ArchiveError("Attachment path escapes the files root.")
    if any(part.is_symlink() for part in [candidate, *candidate.parents] if part != root.parent):
        raise ArchiveError("Symlinks are not accepted in attachment paths.")
    return candidate


def safe_filename(name: str) -> str:
    # Keep human-readable names without enabling hidden/active browser content.
    result = re.sub(r"[^\w .()-]", "_", name, flags=re.UNICODE).strip(" .")[:120] or "file"
    # Dangerous content is still exact bytes, but served/downloaded as .download.
    if Path(result).suffix.lower() in {".html", ".htm", ".svg", ".js", ".xml", ".xhtml", ".mhtml"}:
        result += ".download"
    return result


def copy_files(tables: dict, root: Path, output: Path) -> tuple[list, dict, list, list]:
    root = root.resolve()
    files, errors, inventory, referenced = [], [], [], set()
    task_projects = {r["id"]: r.get("project_id") for r in tables.get("tasks", [])}
    for table in ("project_has_files", "task_has_files"):
        for row in tables.get(table, []):
            file_id = row.get("id")
            entry = {"table": table, "id": file_id, "originalName": str(row.get("name") or "file"),
                     "status": "missing", "path": None, "size": row.get("size"), "sha256": None}
            if table == "project_has_files":
                entry["projectId"] = row.get("project_id")
            else:
                entry["taskId"] = row.get("task_id")
                entry["projectId"] = task_projects.get(row.get("task_id"))
            try:
                source = safe_source(root, str(row.get("path") or ""))
                referenced.add(source.relative_to(root).as_posix())
                if not source.is_file():
                    raise FileNotFoundError()
                if not isinstance(file_id, int) or file_id < 0:
                    raise ArchiveError("Unsupported attachment ID.")
                relative = Path("attachments") / table / f"{file_id}-{safe_filename(entry['originalName'])}"
                destination = output / relative
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                shutil.copyfile(source, destination)
                destination.chmod(0o600)
                digest = sha256_file(source)
                size = source.stat().st_size
                entry.update(path=relative.as_posix(), size=size, sha256=digest, status="ok",
                             mimeType=mimetypes.guess_type(entry["originalName"])[0])
                if sha256_file(destination) != digest:
                    entry["status"] = "hash_mismatch"
                elif row.get("size") is not None and int(row["size"]) != size:
                    entry["status"] = "size_mismatch"
                if entry["status"] != "ok":
                    errors.append({"code": entry["status"], "table": table, "id": file_id,
                                   "message": "Attachment bytes or size do not match the source record."})
            except ArchiveError:
                entry["status"] = "unsafe"
                errors.append({"code": "unsafe_attachment", "table": table, "id": file_id,
                               "message": "Attachment source path was rejected."})
            except (OSError, ValueError):
                errors.append({"code": "missing_attachment", "table": table, "id": file_id,
                               "message": "Attachment could not be read from the backup."})
            files.append(entry)
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            errors.append({"code": "source_symlink", "message": "Source files contain a symlink."})
        elif path.is_file():
            inventory.append({"path": path.relative_to(root).as_posix(), "size": path.stat().st_size,
                              "sha256": sha256_file(path),
                              "referenced": path.relative_to(root).as_posix() in referenced})
    counts = {"referenced": len(files), "copied": sum(f["path"] is not None for f in files),
              "missing": sum(f["status"] != "ok" for f in files),
              "unreferenced": sum(not f["referenced"] for f in inventory), "sourceFiles": len(inventory)}
    return files, counts, errors, inventory


def validate_relations(source: dict) -> list:
    errors, groups = [], {}
    for fk in source["foreignKeys"]:
        groups.setdefault((fk["table"], fk["constraint"], fk["parentTable"]), []).append(fk)
    for (table, constraint, parent), fields in groups.items():
        fields.sort(key=lambda f: f["ordinal"])
        targets = {tuple(r.get(f["parentColumn"]) for f in fields) for r in source["tables"].get(parent, [])}
        invalid = 0
        for row in source["tables"].get(table, []):
            values = tuple(row.get(f["column"]) for f in fields)
            if all(v is not None for v in values) and values not in targets:
                invalid += 1
        if invalid:
            errors.append({"code": "broken_foreign_key", "table": table, "constraint": constraint,
                           "count": invalid, "message": "Source contains missing referenced records."})
    return errors


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    path.chmod(0o600)


def prepare_output(path: Path) -> None:
    if path.is_symlink() or (path.exists() and any(path.iterdir())):
        raise ArchiveError("Output directory must be new or empty; existing archives are never replaced.")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)


def reject_symlink_components(path: Path) -> None:
    if any(component.is_symlink() for component in [path, *path.absolute().parents]):
        raise ArchiveError("Symlinks are not accepted in archive output paths.")


def export(source: dict, files_root: Path, output: Path, private_output: Path, *,
           captured_at: str | None = None, backup: Path | None = None,
           viewer_dir: Path | None = None, kanboard_version: str | None = None) -> dict:
    reject_symlink_components(output)
    reject_symlink_components(private_output)
    output, private_output, files_root = output.resolve(), private_output.resolve(), files_root.resolve()
    if not files_root.is_dir():
        raise ArchiveError("Files root is missing; completeness cannot be inferred.")
    if (output == private_output or output.is_relative_to(private_output) or
            private_output.is_relative_to(output) or output.is_relative_to(files_root) or
            files_root.is_relative_to(output) or private_output.is_relative_to(files_root) or
            files_root.is_relative_to(private_output)):
        raise ArchiveError("Source, browse and private directories must be separate.")
    prepare_output(output)
    prepare_output(private_output)
    tables, redactions, omitted, warnings = projection(source["tables"])
    warnings.extend(finance_warnings(source["tables"]))
    errors = validate_relations(source)
    for table, rows in source["tables"].items():
        if source["counts"][table] != len(rows):
            errors.append({"code": "table_count_mismatch", "table": table,
                           "message": "Export row count does not match the source snapshot."})
        write_json(private_output / "tables" / f"{table}.json", {
            "schema": source["schema"][table], "rows": rows,
            "rawHexCells": source["rawHexCells"].get(table), "sourceCount": source["counts"][table]})
    files, file_counts, file_errors, inventory = copy_files(source["tables"], files_root, output)
    errors.extend(file_errors)
    counts = {t: {"source": source["counts"][t], "privateExport": len(rows),
                  "browseExport": len(tables.get(t, []))} for t, rows in source["tables"].items()}
    integrity = {"complete": not errors, "errors": errors, "warnings": warnings,
                 "tableCounts": counts, "fileCounts": file_counts,
                 "omittedTables": omitted, "redactedColumns": redactions}
    generated_at = datetime.now(timezone.utc).isoformat()
    archive = {"schemaVersion": 1, "generatedAt": generated_at,
               "source": {"kanboardVersion": kanboard_version, "capturedAt": captured_at,
                          "versionProvenance": "Operator supplied from backup record" if kanboard_version else "Unknown",
                          "restoredEngine": source["engine"], "restoredEngineVersion": source["engineVersion"],
                          "scope": "All retained tables and local files in the supplied backup; not previously deleted data."},
               "tables": tables, "files": files, "integrity": integrity}
    write_json(output / "archive-data.json", archive)
    # A JS assignment enables file:// viewing without fetch/CORS or a web server.
    serialized = json.dumps(archive, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    serialized = serialized.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    serialized = serialized.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    (output / "archive-data.js").write_text("window.LEGACY_ARCHIVE = " + serialized + ";\n", encoding="utf-8")
    (output / "archive-data.js").chmod(0o600)
    write_json(output / "manifest.json", {k: v for k, v in archive.items() if k not in {"tables", "files"}})
    private_manifest = {"generatedAt": generated_at, "sourceEngine": source["engine"],
                        "schema": source["schema"], "foreignKeys": source["foreignKeys"],
                        "sourceFileInventory": inventory, "integrity": integrity,
                        "rawEncoding": "MySQL rawHexCells preserve CAST(field AS BINARY) bytes; null is SQL NULL. This is SQL value serialization, not physical database bytes. Original backup is authoritative."}
    if backup:
        private_manifest["originalBackup"] = {"name": backup.name, "size": backup.stat().st_size,
                                              "sha256": sha256_file(backup)}
    write_json(private_output / "manifest.json", private_manifest)
    if viewer_dir:
        for name in ("index.html", "viewer.js", "viewer.css"):
            src = viewer_dir / name
            if not src.is_file() or src.is_symlink():
                raise ArchiveError("Offline viewer assets are not ready.")
            shutil.copyfile(src, output / name)
            (output / name).chmod(0o600)
    return integrity


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--mysql-container", help="Already restored disposable container (--network none, no binds/ports)")
    source.add_argument("--sqlite", type=Path, help="Already downloaded SQLite backup copy")
    parser.add_argument("--database", default="legacy_archive")
    parser.add_argument("--files-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New user-facing browse directory")
    parser.add_argument("--private-output", type=Path, required=True, help="Separate new protected raw-record directory")
    parser.add_argument("--backup", type=Path, help="Original backup archive, hashed read-only")
    parser.add_argument("--captured-at", help="Backup capture time, ISO8601")
    parser.add_argument("--kanboard-version", help="Version verified in the backup record (not inferred from the local image)")
    parser.add_argument("--viewer-dir", type=Path, default=Path(__file__).parent / "viewer")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        data = mysql_source(args.mysql_container, args.database) if args.mysql_container else sqlite_source(args.sqlite)
        result = export(data, args.files_root, args.output, args.private_output,
                        captured_at=args.captured_at, backup=args.backup, viewer_dir=args.viewer_dir,
                        kanboard_version=args.kanboard_version)
        # Counts only; no names, content, fields, paths or private values in logs.
        print(json.dumps({"complete": result["complete"], "tables": len(result["tableCounts"]),
                          "rows": sum(t["source"] for t in result["tableCounts"].values()),
                          "files": result["fileCounts"], "errorCount": len(result["errors"]),
                          "warningCount": len(result["warnings"])}))
        return 0 if result["complete"] else 2
    except (ArchiveError, OSError, ValueError, sqlite3.Error, subprocess.SubprocessError):
        print("Archive export failed. Original backup is unchanged; no completeness claim was made.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
