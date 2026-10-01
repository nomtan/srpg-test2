#!/usr/bin/env python3
"""Inspect Tripo source and normalized modular character assets.

Examples:
  python tools/asset_gen/character_pipeline/inspect_character_asset.py --kind body --id 007
  python tools/asset_gen/character_pipeline/inspect_character_asset.py --kind face --id 001 --id 002 --output report.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from character_asset_metrics import bone_contract, compare_bones, inspect_glb, read_glb


ROOT = Path(__file__).resolve().parents[3]
TRIPO = ROOT / "assets/characters/tripo"
MODULAR = ROOT / "assets/characters/modular"
REFERENCE_RIG = ROOT / "assets/characters/_shared/rigs/humanoid_v1.glb"
STANDARD = "ashen_character_v1"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _relative(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _inspect_one(kind: str, part_id: str, modular_root: Path) -> dict[str, Any]:
    source_path = TRIPO / kind / part_id / "model.glb"
    modular_path = modular_root / kind / part_id / "model.glb"
    metadata_path = modular_root / kind / part_id / "normalization.json"
    if not metadata_path.is_file() and modular_root != MODULAR:
        metadata_path = MODULAR / kind / part_id / "normalization.json"
    warnings: list[str] = []
    errors: list[str] = []
    source = inspect_glb(source_path) if source_path.is_file() else None
    modular = inspect_glb(modular_path) if modular_path.is_file() else None
    metadata = json.loads(metadata_path.read_text(encoding="utf-8")) if metadata_path.is_file() else None
    if source is None:
        errors.append(f"missing immutable source: {_relative(source_path)}")
    if modular is None:
        errors.append(f"missing modular output: {_relative(modular_path)}")
    if metadata is None:
        errors.append(f"missing normalization metadata: {_relative(metadata_path)}")
    compatibility: dict[str, Any] = {"standard": STANDARD, "status": "FAIL" if errors else "PASS"}
    if modular:
        if kind == "body":
            reference_document, _ = read_glb(REFERENCE_RIG)
            differences = compare_bones(modular["rig"]["bones"], bone_contract(reference_document))
            compatibility.update({
                "rig_profile": "humanoid_v1",
                "skeleton_matches_reference": not differences,
                "skeleton_differences": differences,
                "required_animations": all(name in {item["name"] for item in modular["animations"]["items"]} for name in ("idle", "walk", "attack", "hit")),
            })
            if differences:
                errors.append("modular skeleton differs from humanoid_v1")
        else:
            structure = modular["head_hair"]
            compatibility.update({
                "coordinate_space": "humanoid_v1_rest",
                "static": modular["rig"]["skin_count"] == 0 and modular["animations"]["count"] == 0,
                "head_hair_method": structure["method"],
                "expression_hair_isolated": structure["expression_hair_isolated"],
            })
            if structure["method"] == "legacy_combined":
                warnings.append("Head and Hair are not separately identifiable; allowed only for the 001-006 legacy reference set")
    comparison = None
    if source and modular:
        comparison = {
            "source_sha256": _sha256(source_path),
            "modular_sha256": _sha256(modular_path),
            "vertex_delta": modular["geometry"]["vertex_count"] - source["geometry"]["vertex_count"],
            "triangle_delta": modular["geometry"]["triangle_count"] - source["geometry"]["triangle_count"],
            "material_delta": modular["materials"]["count"] - source["materials"]["count"],
            "texture_delta": modular["textures"]["image_count"] - source["textures"]["image_count"],
        }
    compatibility["status"] = "FAIL" if errors else ("WARNING" if warnings else "PASS")
    for metrics in (source, modular):
        if metrics:
            metrics["path"] = _relative(Path(metrics["path"]))
    return {
        "asset_type": kind,
        "id": part_id,
        "source": source,
        "modular": modular,
        "normalization": metadata,
        "comparison": comparison,
        "compatibility": compatibility,
        "warnings": warnings,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect source and modular Ashen Vow character assets.")
    parser.add_argument("--kind", choices=("body", "face"), required=True)
    parser.add_argument("--id", action="append", required=True, dest="ids", help="Positive three-digit part ID; may be repeated.")
    parser.add_argument("--root", type=Path, default=MODULAR, help="Modular output root (useful for staged builds).")
    parser.add_argument("--output", type=Path, help="Write the JSON report to this path as well as stdout.")
    parser.add_argument("--quiet", action="store_true", help="Do not echo JSON to stdout (requires --output for a persistent report).")
    args = parser.parse_args()
    for part_id in args.ids:
        if len(part_id) != 3 or not part_id.isdigit() or int(part_id) <= 0:
            parser.error(f"invalid part ID: {part_id!r}; expected a positive three-digit number")
    modular_root = args.root if args.root.is_absolute() else ROOT / args.root
    report = {
        "schema_version": 1,
        "standard": STANDARD,
        "reference_rig": _relative(REFERENCE_RIG),
        "assets": [_inspect_one(args.kind, part_id, modular_root) for part_id in args.ids],
    }
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        output = args.output if args.output.is_absolute() else ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    if not args.quiet:
        print(text, end="")
    return 1 if any(asset["errors"] for asset in report["assets"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
