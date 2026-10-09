#!/usr/bin/env python3
"""Mechanical composition of the existing approved Jivie mark for Play."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/store/google-play"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--font-directory", required=True,
                        help="Flutter's existing material_fonts directory")
    args = parser.parse_args()
    fonts = Path(args.font_directory)
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "assets/branding/jivie/google-play-512.png",
                    OUT / "icon-512.png")
    source = Image.open(ROOT / "assets/branding/jivie/icon-foreground.png").convert("RGBA")
    mark = source.resize((460, 460), Image.Resampling.LANCZOS)
    title = ImageFont.truetype(str(fonts / "Roboto-Medium.ttf"), 96)
    tagline = ImageFont.truetype(str(fonts / "Roboto-Regular.ttf"), 32)
    for language, copy in (("sl", "Prostor za vsakdan."),
                            ("en", "Space for everyday life.")):
        image = Image.new("RGB", (1024, 500), "#F4F6FA")
        image.paste(mark, (12, 20), mark)
        draw = ImageDraw.Draw(image)
        draw.text((485, 153), "Jivie", font=title, fill="#202329")
        draw.text((489, 279), copy, font=tagline, fill="#696E79")
        image.save(OUT / f"feature-{language}-1024x500.png", optimize=True)
    files = []
    for file in sorted(OUT.rglob("*.png")):
        with Image.open(file) as image:
            files.append({"path": str(file.relative_to(ROOT)), "width": image.width,
                          "height": image.height, "mode": image.mode,
                          "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    (OUT / "manifest.json").write_text(json.dumps({
        "screenshots": "Current Flutter widgets, synthetic local data, Android target, headless renderer; not Android device captures",
        "files": files}, ensure_ascii=False, indent=2) + "\n")
    print(f"Prepared and inventoried {len(files)} PNG images in {OUT}")


if __name__ == "__main__":
    main()
