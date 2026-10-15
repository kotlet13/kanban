#!/usr/bin/env python3
"""Validate and package real widget captures without modifying their pixels."""
import hashlib
import json
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT / "build/qa/upgrade-store-20261015"
FROZEN = ROOT / "build/qa/upgrade-release-20261014/source-input-manifest.json"
SCENES = (
    "01-pulse", "02-planner", "03-calendar", "04-ideas",
    "05-projects", "06-shopping", "07-garden", "08-finances",
)
SIZES = {
    "android-phone": (720, 1280),
    "ios-iphone": (1320, 2868),
    "ios-ipad": (2064, 2752),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    source = json.loads(FROZEN.read_text())
    assert source["version"] == "1.9.0+28"
    for row in source["files"]:
        assert digest(ROOT / row["path"]) == row["sha256"], row["path"]
    rows = []
    for device, size in SIZES.items():
        for locale in ("sl", "en"):
            for scene in SCENES:
                relative = Path(device) / locale / f"{scene}.png"
                path = CAPTURES / relative
                with Image.open(path) as picture:
                    assert picture.format == "PNG", relative
                    assert picture.size == size, (relative, picture.size)
                    picture.load()
                    if "A" in picture.getbands():
                        assert picture.getchannel("A").getextrema() == (255, 255), relative
                    assert any(low != high for low, high in picture.convert("RGB").getextrema()), relative
                rows.append({
                    "path": relative.as_posix(), "width": size[0], "height": size[1],
                    "bytes": path.stat().st_size, "sha256": digest(path),
                })
    assert len(rows) == 48
    assert len({row["sha256"] for row in rows}) == 48, "Duplicate device/locale capture"
    manifest = {
        "version": source["version"], "runtimeCommit": source["baseCommit"],
        "runtimeInputSha256": source["aggregateSha256"],
        "captureKind": "actual Flutter widget rendering with isolated synthetic records",
        "physicalDeviceCapture": False, "pixelsEdited": False,
        "platforms": list(SIZES), "locales": ["sl", "en"], "files": rows,
        "harnesses": [
            {"path": str(path.relative_to(ROOT)), "sha256": digest(path)}
            for path in sorted((ROOT / "tools/release").glob("upgrade_*_capture_test.dart"))
        ],
    }
    (CAPTURES / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    output = ROOT / "build/releases/Jivie-1.9.0+28-store-screenshots.zip"
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(CAPTURES / "manifest.json", "manifest.json")
        for row in rows:
            archive.write(CAPTURES / row["path"], row["path"])
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == 49
    print(json.dumps({"images": len(rows), "archive": str(output), "sha256": digest(output)}))


if __name__ == "__main__":
    main()
