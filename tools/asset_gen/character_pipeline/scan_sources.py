#!/usr/bin/env python3
"""Validate and catalog Tripo face/body source GLBs.

The Tripo source files are treated as immutable inputs:
  assets/characters/tripo/face/<id>/model.glb
  assets/characters/tripo/body/<id>/model.glb

This script uses only the Python standard library so it can run before Blender.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[3]
TRIPO_ROOT = REPO_ROOT / "assets" / "characters" / "tripo"
DEFAULT_CATALOG = TRIPO_ROOT / "catalog.json"


def scan_kind(kind: str) -> tuple[list[dict[str, Any]], list[str]]:
    root = TRIPO_ROOT / kind
    errors: list[str] = []
    items: list[dict[str, Any]] = []

    if not root.is_dir():
        return items, [f"missing source directory: {root.relative_to(REPO_ROOT)}"]

    for directory in sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: p.name):
        if not directory.name.isdigit():
            continue

        model = directory / "model.glb"
        if not model.is_file():
            errors.append(
                f"missing {kind} model: {model.relative_to(REPO_ROOT).as_posix()}"
            )
            continue

        items.append(
            {
                "id": directory.name,
                "source": model.relative_to(REPO_ROOT).as_posix(),
                "size_bytes": model.stat().st_size,
            }
        )

    if not items:
        errors.append(f"no valid {kind} sources found under {root.relative_to(REPO_ROOT)}")

    return items, errors


def build_catalog() -> tuple[dict[str, Any], list[str]]:
    faces, face_errors = scan_kind("face")
    bodies, body_errors = scan_kind("body")
    catalog = {
        "schema_version": 1,
        "source_policy": "immutable",
        "face": faces,
        "body": bodies,
    }
    return catalog, face_errors + body_errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate assets/characters/tripo face/body source GLBs."
    )
    parser.add_argument(
        "--write-catalog",
        action="store_true",
        help="Write assets/characters/tripo/catalog.json after validation.",
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=DEFAULT_CATALOG,
        help="Override catalog output path.",
    )
    args = parser.parse_args()

    catalog, errors = build_catalog()

    print(f"faces: {len(catalog['face'])}")
    print(f"bodies: {len(catalog['body'])}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    if args.write_catalog:
        output = args.catalog
        if not output.is_absolute():
            output = REPO_ROOT / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote: {output.relative_to(REPO_ROOT).as_posix()}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
