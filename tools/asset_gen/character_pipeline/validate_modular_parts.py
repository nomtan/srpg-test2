#!/usr/bin/env python3
"""Validate modular character GLBs against Ashen Vow Character Standard v1.

The validator only reports; it never edits or repairs an asset. Corrections
belong in build_modular_parts.py or in the Blender authoring step.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from character_asset_metrics import IDENTITY, accessor_values, bone_contract, close, compare_bones, inspect_glb, read_glb


ROOT = Path(__file__).resolve().parents[3]
MODULAR = ROOT / "assets/characters/modular"
TRIPO = ROOT / "assets/characters/tripo"
REFERENCE_RIG = ROOT / "assets/characters/_shared/rigs/humanoid_v1.glb"
STANDARD_PATH = ROOT / "assets/characters/_shared/character_asset_standard_v1.json"


@dataclass
class ValidationReport:
    checks: list[dict[str, Any]] = field(default_factory=list)

    def add(self, status: str, code: str, message: str, asset: str = "catalog") -> None:
        self.checks.append({"status": status, "asset": asset, "code": code, "message": message})
        print(f"{status}: {asset}: {message}")

    def require(self, condition: bool, code: str, message: str, asset: str) -> None:
        self.add("PASS" if condition else "FAIL", code, message, asset)

    def warning(self, condition: bool, code: str, pass_message: str, warning_message: str, asset: str) -> None:
        self.add("PASS" if condition else "WARNING", code, pass_message if condition else warning_message, asset)

    @property
    def status(self) -> str:
        statuses = {check["status"] for check in self.checks}
        return "FAIL" if "FAIL" in statuses else ("WARNING" if "WARNING" in statuses else "PASS")


def _load_metadata(root: Path, kind: str, part_id: str) -> dict[str, Any] | None:
    path = root / kind / part_id / "normalization.json"
    if not path.is_file() and root != MODULAR:
        path = MODULAR / kind / part_id / "normalization.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


def _validate_metadata(report: ValidationReport, kind: str, part_id: str, metadata: dict[str, Any] | None, source: Path) -> None:
    asset = f"{kind}{part_id}"
    report.require(metadata is not None, "metadata.exists", "normalization metadata exists", asset)
    if metadata is None:
        return
    expected = {
        "standard": "ashen_character_v1",
        "version": 1,
        "asset_type": kind,
        "id": part_id,
        "rig_profile": "humanoid_v1",
        "coordinate_space": "humanoid_v1_rest",
    }
    report.require(all(metadata.get(key) == value for key, value in expected.items()), "metadata.schema", "metadata identifies Standard v1, type, ID, rig, and coordinate space", asset)
    report.require("rig_source_body_id" not in metadata, "metadata.no_body001_dependency", "metadata has no Body001 reference-rig dependency", asset)
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest() if source.is_file() else None
    report.require(source_hash is not None and metadata.get("source_sha256") == source_hash, "source.hash", "immutable source hash matches metadata", asset)
    if kind == "face":
        profile = metadata.get("expression_profile", "")
        report.require(isinstance(profile, str) and profile.isidentifier() and (ROOT / "assets/characters/_shared/face/expression/profiles" / (profile + ".tres")).is_file(), "metadata.expression_profile", "face declares an existing expression profile", asset)
        valid_fit = (
            isinstance(metadata.get("scale"), (int, float))
            and metadata["scale"] > 0
            and isinstance(metadata.get("position"), list)
            and len(metadata["position"]) == 3
        )
        report.require(valid_fit, "metadata.face_fit", "face has a positive scale and a three-axis normalization position", asset)


def _validate_budget(report: ValidationReport, asset: str, label: str, value: int, limits: dict[str, int]) -> None:
    if value > limits["hard_max"]:
        report.add("FAIL", f"budget.{label}", f"{label} {value} exceeds hard limit {limits['hard_max']}", asset)
    elif value > limits["recommended_max"]:
        tier = "warning tier" if value <= limits["warning_max"] else "upper warning tier"
        report.add("WARNING", f"budget.{label}", f"{label} {value} exceeds recommended {limits['recommended_max']} ({tier})", asset)
    else:
        report.add("PASS", f"budget.{label}", f"{label} {value} is within recommended {limits['recommended_max']}", asset)


def _identity_mesh_transforms(metrics: dict[str, Any]) -> bool:
    for node in metrics["transform"]["mesh_nodes"]:
        if node["matrix"] is not None and not close(node["matrix"], IDENTITY):
            return False
        if (
            not close(node["translation"], [0, 0, 0])
            or not close(node["rotation"], [0, 0, 0, 1])
            or not close(node["scale"], [1, 1, 1])
        ):
            return False
    return True


def _validate_textures(report: ValidationReport, asset: str, metrics: dict[str, Any], standard: dict[str, Any]) -> None:
    textures = metrics["textures"]
    report.warning(
        not textures["unused_texture_indices"],
        "texture.unused",
        "all embedded textures are referenced",
        f"unused texture indices remain: {textures['unused_texture_indices']}",
        asset,
    )
    limits = standard["performance"]["texture_resolution"]
    for image in textures["images"]:
        largest = max(image["width"] or 0, image["height"] or 0)
        _validate_budget(report, asset, f"texture_resolution.{image['index']}", largest, limits)
    roles = {role for material in metrics["materials"]["items"] for role in material["texture_roles"]}
    ignored_roles = sorted(roles - {"base_color"})
    kind = "body" if asset.startswith("body") else "face"
    reference_key = "bodies" if kind == "body" else "faces"
    legacy = asset[-3:] in standard["reference_set"][reference_key]
    if not ignored_roles:
        report.add("PASS", "texture.toon_roles", "textures match the base-color-only toon runtime", asset)
    elif legacy:
        report.add("WARNING", "texture.toon_roles", f"legacy texture roles ignored by the toon runtime: {ignored_roles}", asset)
    else:
        report.add("FAIL", "texture.toon_roles", f"new Standard v1 asset contains PBR texture roles ignored at runtime: {ignored_roles}", asset)


def _validate_body(report: ValidationReport, path: Path, metrics: dict[str, Any], reference: dict[str, dict[str, Any]], standard: dict[str, Any]) -> None:
    part_id = path.parent.name
    asset = f"body{part_id}"
    rig = metrics["rig"]
    report.require(rig["skeleton_count"] == 1 and rig["skin_count"] == 1, "body.one_rig", "body has exactly one Skeleton/Skin", asset)
    report.require(rig["bone_count"] == standard["bone_count"], "body.bone_count", f"body has {standard['bone_count']} humanoid_v1 bones", asset)
    differences = compare_bones(rig["bones"], reference)
    report.require(not differences, "body.rest_contract", "bone names, hierarchy, and rest transforms match humanoid_v1" if not differences else "; ".join(differences[:3]), asset)
    report.require(rig["unweighted_vertices"] == 0, "body.weights.complete", "all body vertices are weighted", asset)
    report.require(rig["invalid_joint_vertices"] == 0, "body.weights.valid_joints", "all weighted vertices reference valid joints", asset)
    report.require(rig["maximum_influences"] <= standard["maximum_bone_influences"], "body.weights.influences", f"maximum influences is {rig['maximum_influences']} (limit {standard['maximum_bone_influences']})", asset)
    document, _ = read_glb(path)
    animation_names = [animation.get("name", "") for animation in document.get("animations", [])]
    report.require(len(animation_names) == len(set(animation_names)), "body.animation.unique", "animation names are unique", asset)
    missing = sorted(set(standard["required_animations"]) - set(animation_names))
    report.require(not missing, "body.animation.required", "required idle/walk/attack/hit clips exist" if not missing else f"missing animations: {missing}", asset)
    joints = set(document.get("skins", [{}])[0].get("joints", [])) if document.get("skins") else set()
    invalid_tracks = sum(
        1
        for animation in document.get("animations", [])
        for channel in animation.get("channels", [])
        if channel.get("target", {}).get("node") not in joints
    )
    report.require(invalid_tracks == 0, "body.animation.tracks", "animation tracks target humanoid_v1 joints", asset)
    report.require(_identity_mesh_transforms(metrics), "body.transform", "body mesh transform is normalized", asset)
    report.require(metrics["geometry"]["mesh_count"] >= 1, "body.mesh", "body contains renderable geometry", asset)
    budget = standard["performance"]["body"]
    _validate_budget(report, asset, "vertices", metrics["geometry"]["vertex_count"], budget["vertices"])
    _validate_budget(report, asset, "triangles", metrics["geometry"]["triangle_count"], budget["triangles"])
    _validate_budget(report, asset, "materials", metrics["materials"]["count"], budget["materials"])
    _validate_budget(report, asset, "textures", metrics["textures"]["image_count"], budget["textures"])
    _validate_textures(report, asset, metrics, standard)


def _validate_range(report: ValidationReport, asset: str, label: str, value: float, limits: dict[str, float]) -> None:
    if not limits["hard_min"] <= value <= limits["hard_max"]:
        report.add("FAIL", f"face.bounds.{label}", f"{label} {value:.4f} is outside hard range [{limits['hard_min']}, {limits['hard_max']}]", asset)
    elif not limits["recommended_min"] <= value <= limits["recommended_max"]:
        report.add("WARNING", f"face.bounds.{label}", f"{label} {value:.4f} is outside recommended range [{limits['recommended_min']}, {limits['recommended_max']}]", asset)
    else:
        report.add("PASS", f"face.bounds.{label}", f"{label} {value:.4f} is in the recommended range", asset)


def _validate_face(report: ValidationReport, path: Path, metrics: dict[str, Any], standard: dict[str, Any]) -> None:
    part_id = path.parent.name
    asset = f"face{part_id}"
    report.require(metrics["rig"]["skeleton_count"] == 0 and metrics["rig"]["skin_count"] == 0 and metrics["animations"]["count"] == 0, "face.static", "face has no Skeleton, Skin, or Animation", asset)
    report.require(_identity_mesh_transforms(metrics), "face.transform", "face mesh transform is normalized", asset)
    report.require(metrics["geometry"]["mesh_count"] >= 1, "face.mesh", "face contains renderable Head + Hair geometry", asset)
    report.require(metrics["uv"]["set_count"] >= 1, "face.uv", "face has texture coordinates", asset)
    bounds = metrics["geometry"]["bounds"]
    report.require(bounds is not None, "face.bounds", "face exposes mesh bounds", asset)
    if bounds:
        if "face_size" in standard:
            report.require(abs(bounds["width"] - standard["face_size"]["width_m"]) < 0.001, "face.size.reference", "face width matches the approved Face007 reference within 1mm", asset)
        values = {
            "width": bounds["width"],
            "height": bounds["height"],
            "depth": bounds["depth"],
            "center_x": bounds["center"][0],
            "center_y": bounds["center"][1],
            "center_z": bounds["center"][2],
        }
        for label, value in values.items():
            _validate_range(report, asset, label, value, standard["face_head_space"][label])
    method = metrics["head_hair"]["method"]
    legacy = part_id in standard["face_structure"]["legacy_combined_ids"]
    _validate_expression_v2(report, path, legacy)
    if method == standard["face_structure"]["new_asset_method"]:
        report.add("PASS", "face.head_hair", "Head and Hair are isolated by material", asset)
    elif legacy:
        report.add("WARNING", "face.head_hair", "legacy combined Head/Hair accepted for reference-set compatibility; new assets must use material separation", asset)
    else:
        report.add("FAIL", "face.head_hair", f"new face requires {standard['face_structure']['new_asset_method']}, found {method}", asset)
    budget = standard["performance"]["face"]
    _validate_budget(report, asset, "vertices", metrics["geometry"]["vertex_count"], budget["vertices"])
    _validate_budget(report, asset, "triangles", metrics["geometry"]["triangle_count"], budget["triangles"])
    _validate_budget(report, asset, "materials", metrics["materials"]["count"], budget["materials"])
    _validate_budget(report, asset, "textures", metrics["textures"]["image_count"], budget["textures"])
    _validate_textures(report, asset, metrics, standard)


def _validate_expression_v2(report: ValidationReport, path: Path, legacy: bool) -> None:
    asset = "face" + path.parent.name
    document, binary = read_glb(path)
    primitives = [p for mesh in document.get("meshes", []) for p in mesh.get("primitives", [])]
    names = [document.get("materials", [])[p["material"]].get("name", "") if "material" in p else "" for p in primitives]
    separated = any(name.startswith("Head") for name in names) and any(name.startswith("Hair") for name in names)
    if legacy and not separated:
        report.add("WARNING", "face.expression.mode", "legacy_projection retained for legacy_combined_ids faces", asset)
        return
    report.require(separated and all(name.startswith(("Head", "Hair")) for name in names), "face.expression.materials", "v2 has only classified Head* / Hair* surfaces", asset)
    metadata = _load_metadata(path.parents[2], "face", path.parent.name) or {}
    report.require(metadata.get("expression_rendering", "uv_v2") == "uv_v2", "face.expression.mode", "new Face uses uv_v2, not legacy_projection", asset)
    enabled = excluded = False
    for index, (primitive, name) in enumerate(zip(primitives, names)):
        if not name.startswith("Head"):
            continue
        attributes = primitive.get("attributes", {})
        required = {"POSITION", "TEXCOORD_0", "TEXCOORD_1", "COLOR_0"}
        present = required <= attributes.keys()
        report.require(present, "face.expression.channels", f"Head surface {index} has base UV, ExpressionUV and mask", asset)
        if not present:
            continue
        positions = accessor_values(document, binary, attributes["POSITION"])
        uv = accessor_values(document, binary, attributes["TEXCOORD_1"])
        colors = accessor_values(document, binary, attributes["COLOR_0"])
        valid_uv = len(uv) == len(positions) and all(len(value) == 2 and all(math.isfinite(v) and 0 <= v <= 1 for v in value) for value in uv)
        report.require(valid_uv, "face.expression.uv", f"Head surface {index} UV is complete, finite and within 0..1", asset)
        valid_mask = len(colors) == len(positions) and all(len(value) in (3, 4) and all(math.isfinite(v) and 0 <= v <= 1 for v in value) for value in colors)
        report.require(valid_mask, "face.expression.mask", f"Head surface {index} COLOR_0 mask is complete, finite and within 0..1", asset)
        if not valid_uv or not valid_mask:
            continue
        enabled |= any(c[0] > 0.5 for c in colors)
        excluded |= any(c[0] <= 0.5 for c in colors)
        indices = [int(v[0]) for v in accessor_values(document, binary, primitive["indices"])] if "indices" in primitive else list(range(len(uv)))
        degenerate = 0
        for offset in range(0, len(indices) - 2, 3):
            a, b, c = indices[offset:offset + 3]
            if not any(colors[i][0] > 0.5 for i in (a, b, c)):
                continue
            area = (uv[b][0] - uv[a][0]) * (uv[c][1] - uv[a][1]) - (uv[b][1] - uv[a][1]) * (uv[c][0] - uv[a][0])
            degenerate += abs(area) < 1e-10
        report.require(degenerate == 0, "face.expression.uv_area", f"Head surface {index} has {degenerate} degenerate enabled UV triangles", asset)
    report.require(enabled and excluded, "face.expression.mask_regions", "Head has enabled front and excluded regions across its surfaces", asset)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate modular character parts against Ashen Vow Standard v1.")
    parser.add_argument("--root", type=Path, default=MODULAR)
    parser.add_argument("--json-output", type=Path, help="Write a machine-readable validation report.")
    args = parser.parse_args()
    root = args.root if args.root.is_absolute() else ROOT / args.root
    standard = json.loads(STANDARD_PATH.read_text(encoding="utf-8"))
    reference_document, _ = read_glb(REFERENCE_RIG)
    reference = bone_contract(reference_document)
    report = ValidationReport()
    paths = {kind: sorted((root / kind).glob("*/model.glb")) for kind in ("body", "face")}
    if not any(paths.values()):
        report.add("FAIL", "catalog.empty", f"no modular assets found under {root}")
    for kind in ("body", "face"):
        for path in paths[kind]:
            part_id = path.parent.name
            source = TRIPO / kind / part_id / "model.glb"
            _validate_metadata(report, kind, part_id, _load_metadata(root, kind, part_id), source)
            try:
                metrics = inspect_glb(path)
                if kind == "body":
                    _validate_body(report, path, metrics, reference, standard)
                else:
                    _validate_face(report, path, metrics, standard)
            except (KeyError, IndexError, OSError, ValueError) as error:
                report.add("FAIL", f"{kind}.read", str(error), f"{kind}{part_id}")
    summary = {status: sum(check["status"] == status for check in report.checks) for status in ("PASS", "WARNING", "FAIL")}
    output = {"schema_version": 1, "standard": standard["standard"], "status": report.status, "summary": summary, "checks": report.checks}
    if args.json_output:
        output_path = args.json_output if args.json_output.is_absolute() else ROOT / args.json_output
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"CHARACTER_ASSET_STANDARD_V1: {report.status} ({summary['PASS']} pass, {summary['WARNING']} warning, {summary['FAIL']} fail)")
    return 1 if report.status == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
