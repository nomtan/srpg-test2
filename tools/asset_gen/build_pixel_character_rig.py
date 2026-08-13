#!/usr/bin/env python3
"""Build a reusable cutout rig from the authored male front-left base PNG.

Geometry is authored once in normalized reference coordinates and mapped to the
opaque bounds of the current source. Part extraction never resamples source
pixels; only rendered animation frames use nearest-neighbour transforms.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass, replace
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "assets/characters/base/front.png"
DEFAULT_OUTPUT = ROOT / "assets/characters/male/front_left"
REFERENCE_BBOX = (8, 0, 55, 92)


@dataclass(frozen=True)
class Part:
    name: str
    parent: str | None
    pivot: tuple[int, int]
    polygon: tuple[tuple[int, int], ...]
    z_index: int


@dataclass(frozen=True)
class Geometry:
    source_bbox: tuple[int, int, int, int]
    scale_x: float
    scale_y: float

    @classmethod
    def from_source(cls, source: Image.Image) -> "Geometry":
        bbox = source.getbbox()
        if bbox is None:
            raise ValueError("Source image has no visible pixels")
        ref_l, ref_t, ref_r, ref_b = REFERENCE_BBOX
        l, t, r, b = bbox
        return cls(bbox, (r - l) / (ref_r - ref_l), (b - t) / (ref_b - ref_t))

    def point(self, point: tuple[int, int]) -> tuple[int, int]:
        ref_l, ref_t, _, _ = REFERENCE_BBOX
        l, t, _, _ = self.source_bbox
        return (
            round(l + (point[0] - ref_l) * self.scale_x),
            round(t + (point[1] - ref_t) * self.scale_y),
        )

    def radius(self, value: int) -> tuple[int, int]:
        return max(1, round(value * self.scale_x)), max(1, round(value * self.scale_y))

    @property
    def motion_step(self) -> int:
        return max(1, round((self.scale_x + self.scale_y) * 0.5))


# Coordinates below describe anatomy, not a particular source resolution.
# Anatomical right limbs appear on the left side of this front-left image.
REFERENCE_PARTS = (
    Part("waist", None, (29, 59), ((19, 51), (40, 51), (41, 64), (38, 69), (20, 69), (19, 63)), 10),
    Part("torso", "waist", (29, 55), ((16, 29), (40, 29), (43, 35), (40, 39), (40, 57), (37, 63), (19, 63), (18, 57), (18, 39), (14, 35)), 0),
    Part("head", "torso", (29, 33), ((7, -1), (55, -1), (55, 30), (38, 33), (36, 40), (21, 40), (19, 33), (7, 30)), 40),
    Part("arm_r_upper", "torso", (18, 35), ((10, 29), (24, 29), (23, 49), (14, 54), (8, 47)), -20),
    Part("arm_r_lower", "arm_r_upper", (14, 48), ((7, 42), (20, 42), (17, 59), (8, 59)), -19),
    Part("hand_r", "arm_r_lower", (11, 58), ((6, 54), (19, 54), (19, 68), (6, 68)), -18),
    Part("arm_l_upper", "torso", (40, 35), ((34, 29), (47, 31), (53, 49), (43, 54), (37, 46)), 30),
    Part("arm_l_lower", "arm_l_upper", (46, 48), ((39, 41), (55, 41), (53, 59), (40, 59)), 31),
    Part("hand_l", "arm_l_lower", (49, 58), ((42, 54), (55, 54), (55, 68), (42, 68)), 32),
    Part("leg_r_upper", "waist", (23, 61), ((14, 55), (32, 55), (32, 76), (18, 79), (13, 65)), -10),
    Part("leg_r_lower", "leg_r_upper", (23, 73), ((15, 68), (31, 68), (29, 88), (12, 90), (14, 80)), -9),
    Part("foot_r", "leg_r_lower", (20, 84), ((9, 78), (30, 78), (30, 92), (9, 92)), -8),
    Part("leg_l_upper", "waist", (35, 61), ((27, 55), (44, 55), (46, 76), (33, 80), (28, 69)), 20),
    Part("leg_l_lower", "leg_l_upper", (38, 74), ((31, 68), (47, 68), (50, 91), (32, 92)), 21),
    Part("foot_l", "leg_l_lower", (40, 87), ((30, 81), (52, 81), (52, 92), (30, 92)), 22),
)


def _map_parts(geometry: Geometry) -> tuple[Part, ...]:
    return tuple(
        replace(
            part,
            pivot=geometry.point(part.pivot),
            polygon=tuple(geometry.point(point) for point in part.polygon),
        )
        for part in REFERENCE_PARTS
    )


def _mask_for(part: Part, size: tuple[int, int]) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(part.polygon, fill=255)
    return mask


def _sample(source: Image.Image, geometry: Geometry, logical_point: tuple[int, int]) -> tuple[int, int, int, int]:
    x, y = geometry.point(logical_point)
    x = min(max(x, 0), source.width - 1)
    y = min(max(y, 0), source.height - 1)
    return source.getpixel((x, y))


def _darkest_opaque(source: Image.Image) -> tuple[int, int, int, int]:
    opaque = (pixel for pixel in source.get_flattened_data() if pixel[3] >= 200)
    return min(opaque, key=lambda pixel: pixel[0] + pixel[1] + pixel[2])


def _draw_joint_completion(layer: Image.Image, part_name: str, source: Image.Image, geometry: Geometry) -> None:
    """Restore source-hidden joint caps using only colors sampled from source."""
    draw = ImageDraw.Draw(layer)
    skin = _sample(source, geometry, (30, 20))
    skin_shadow = _sample(source, geometry, (20, 35))
    cloth = _sample(source, geometry, (29, 45))
    outline = _darkest_opaque(source)

    def joint(point: tuple[int, int], radius: int, fill: tuple[int, int, int, int]) -> None:
        x, y = geometry.point(point)
        rx, ry = geometry.radius(radius)
        edge_x, edge_y = geometry.radius(1)
        draw.ellipse((x - rx, y - ry, x + rx, y + ry), fill=outline)
        draw.ellipse(
            (x - rx + edge_x, y - ry + edge_y, x + rx - edge_x, y + ry - edge_y),
            fill=fill,
        )
        draw.rectangle((x + rx - edge_x, y, x + rx - 1, y + edge_y - 1), fill=skin_shadow if fill == skin else fill)

    completions = {
        "arm_r_upper": (((14, 48), 4, skin),),
        "arm_r_lower": (((14, 48), 4, skin), ((11, 58), 3, skin)),
        "hand_r": (((11, 58), 3, skin),),
        "arm_l_upper": (((46, 48), 4, skin),),
        "arm_l_lower": (((46, 48), 4, skin), ((49, 58), 3, skin)),
        "hand_l": (((49, 58), 3, skin),),
        "leg_r_upper": (((23, 73), 4, skin),),
        "leg_r_lower": (((23, 73), 4, skin), ((20, 84), 3, skin)),
        "foot_r": (((20, 84), 3, skin),),
        "leg_l_upper": (((38, 74), 4, skin),),
        "leg_l_lower": (((38, 74), 4, skin), ((40, 87), 3, skin)),
        "foot_l": (((40, 87), 3, skin),),
    }
    for point, radius, fill in completions.get(part_name, ()):  # type: ignore[misc]
        joint(point, radius, fill)


def _build_parts(source: Image.Image, output: Path, specs: tuple[Part, ...], geometry: Geometry) -> dict[str, Image.Image]:
    output.mkdir(parents=True, exist_ok=True)
    images: dict[str, Image.Image] = {}
    for part in specs:
        layer = Image.new("RGBA", source.size, (0, 0, 0, 0))
        _draw_joint_completion(layer, part.name, source, geometry)
        layer.paste(source, (0, 0), _mask_for(part, source.size))
        images[part.name] = layer
    # The rest pose has hands touching the torso/upper legs. Give those source
    # pixels exclusively to hand layers so they cannot remain as moving ghosts.
    hand_union = ImageChops.lighter(
        images["hand_l"].getchannel("A"), images["hand_r"].getchannel("A")
    ).point(lambda alpha: 255 if alpha else 0)
    keep_non_hand = ImageChops.invert(hand_union)
    for name in (
        "head", "torso", "waist",
        "leg_l_upper", "leg_l_lower", "foot_l",
        "leg_r_upper", "leg_r_lower", "foot_r",
    ):
        images[name].putalpha(ImageChops.multiply(images[name].getchannel("A"), keep_non_hand))
    for name, layer in images.items():
        layer.save(output / f"{name}.png", optimize=True)
    return images


def _validate_hands_are_not_baked_into_body(parts: dict[str, Image.Image]) -> None:
    non_arm_names = (
        "head", "torso", "waist",
        "leg_l_upper", "leg_l_lower", "foot_l",
        "leg_r_upper", "leg_r_lower", "foot_r",
    )
    for body_name in non_arm_names:
        for hand_name in ("hand_l", "hand_r"):
            overlap = ImageChops.multiply(parts[body_name].getchannel("A"), parts[hand_name].getchannel("A"))
            if overlap.getbbox() is not None:
                raise AssertionError(f"{body_name} still contains pixels owned by {hand_name}")


def _validate_visible_source_coverage(source: Image.Image, parts: dict[str, Image.Image]) -> None:
    union = Image.new("L", source.size, 0)
    for image in parts.values():
        union = ImageChops.lighter(union, image.getchannel("A"))
    missing = sum(
        1
        for source_alpha, part_alpha in zip(source.getchannel("A").get_flattened_data(), union.get_flattened_data())
        if source_alpha > 1 and part_alpha == 0
    )
    if missing:
        raise AssertionError(f"{missing} visible source pixels are not assigned to any body part")


def _mat_mul(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, ...]:
    return (
        a[0] * b[0] + a[1] * b[3], a[0] * b[1] + a[1] * b[4], a[0] * b[2] + a[1] * b[5] + a[2],
        a[3] * b[0] + a[4] * b[3], a[3] * b[1] + a[4] * b[4], a[3] * b[2] + a[4] * b[5] + a[5],
    )


def _inverse(m: tuple[float, ...]) -> tuple[float, ...]:
    det = m[0] * m[4] - m[1] * m[3]
    return (m[4] / det, -m[1] / det, (m[1] * m[5] - m[4] * m[2]) / det, -m[3] / det, m[0] / det, (m[3] * m[2] - m[0] * m[5]) / det)


def _global_matrix(part: Part, pose: dict[str, tuple[float, float, float]], by_name: dict[str, Part], cache: dict[str, tuple[float, ...]]) -> tuple[float, ...]:
    if part.name in cache:
        return cache[part.name]
    dx, dy, degrees = pose.get(part.name, (0.0, 0.0, 0.0))
    angle = math.radians(degrees)
    c, s = math.cos(angle), math.sin(angle)
    parent_pivot = by_name[part.parent].pivot if part.parent else (0, 0)
    local = (c, -s, part.pivot[0] - parent_pivot[0] + dx, s, c, part.pivot[1] - parent_pivot[1] + dy)
    result = local if part.parent is None else _mat_mul(_global_matrix(by_name[part.parent], pose, by_name, cache), local)
    cache[part.name] = result
    return result


def _render_pose(images: dict[str, Image.Image], specs: tuple[Part, ...], pose: dict[str, tuple[float, float, float]]) -> Image.Image:
    size = next(iter(images.values())).size
    frame = Image.new("RGBA", size, (0, 0, 0, 0))
    by_name = {part.name: part for part in specs}
    cache: dict[str, tuple[float, ...]] = {}
    for part in sorted(specs, key=lambda item: item.z_index):
        node_global = _global_matrix(part, pose, by_name, cache)
        px, py = part.pivot
        source_to_world = _mat_mul(node_global, (1.0, 0.0, -px, 0.0, 1.0, -py))
        transformed = images[part.name].transform(size, Image.Transform.AFFINE, _inverse(source_to_world), resample=Image.Resampling.NEAREST)
        frame.alpha_composite(transformed)
    return frame


def _idle_poses(step: int) -> list[dict[str, tuple[float, float, float]]]:
    offsets = (0, step, 0, -step, 0, 0)
    angles = (0, -1, 0, 1, 0, 0)
    return [
        {"waist": (0, offsets[i], 0), "leg_l_lower": (0, -offsets[i], 0), "leg_r_lower": (0, -offsets[i], 0), "head": (0, 0, angles[i])}
        for i in range(6)
    ]


def _walk_poses(step: int) -> list[dict[str, tuple[float, float, float]]]:
    root_y = (0, -step, step, 0, -step, step)
    channels = {
        "leg_l_upper": (14, 7, 0, -14, -7, 0), "leg_r_upper": (-12, -6, 0, 12, 6, 0),
        "arm_l_upper": (-10, -5, 0, 10, 5, 0), "arm_r_upper": (12, 6, 0, -12, -6, 0),
        "leg_l_lower": (-6, -3, 0, 7, 3, 0), "leg_r_lower": (7, 3, 0, -6, -3, 0),
    }
    poses: list[dict[str, tuple[float, float, float]]] = []
    for i in range(6):
        pose = {name: (0, 0, values[i]) for name, values in channels.items()}
        pose.update({"waist": (0, root_y[i], 0), "foot_l": (0, 0, -channels["leg_l_lower"][i] * 0.5), "foot_r": (0, 0, -channels["leg_r_lower"][i] * 0.5)})
        poses.append(pose)
    return poses


def _validate_idle_feet_are_fixed(poses: list[dict[str, tuple[float, float, float]]], specs: tuple[Part, ...]) -> None:
    by_name = {part.name: part for part in specs}
    reference: dict[str, tuple[float, ...]] = {}
    for frame_index, pose in enumerate(poses):
        cache: dict[str, tuple[float, ...]] = {}
        for node_name in ("leg_l_lower", "foot_l", "leg_r_lower", "foot_r"):
            matrix = tuple(round(v, 6) for v in _global_matrix(by_name[node_name], pose, by_name, cache))
            if frame_index == 0:
                reference[node_name] = matrix
            elif matrix != reference[node_name]:
                raise AssertionError(f"Idle frame {frame_index + 1} moves fixed node {node_name}")


def _save_sheet(images: dict[str, Image.Image], specs: tuple[Part, ...], poses: list[dict[str, tuple[float, float, float]]], path: Path) -> None:
    width, height = next(iter(images.values())).size
    sheet = Image.new("RGBA", (width * len(poses), height), (0, 0, 0, 0))
    for index, pose in enumerate(poses):
        sheet.alpha_composite(_render_pose(images, specs, pose), (index * width, 0))
    sheet.save(path, optimize=True)


def _save_manifest(source: Image.Image, output: Path, specs: tuple[Part, ...], geometry: Geometry) -> None:
    data = {
        "source": "res://assets/characters/base/front.png", "direction": "front_left",
        "canvas_size": list(source.size), "source_bbox": list(geometry.source_bbox),
        "motion_step": geometry.motion_step, "frame_count": 6, "fps": 6,
        "parts": [{"name": p.name, "parent": p.parent, "pivot": list(p.pivot), "z_index": p.z_index} for p in specs],
    }
    (output / "rig_manifest.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGBA")
    geometry = Geometry.from_source(source)
    specs = _map_parts(geometry)
    images = _build_parts(source, args.output, specs, geometry)
    _validate_hands_are_not_baked_into_body(images)
    _validate_visible_source_coverage(source, images)
    idle_poses = _idle_poses(geometry.motion_step)
    _validate_idle_feet_are_fixed(idle_poses, specs)
    _save_sheet(images, specs, idle_poses, args.output / "idle_front_left.png")
    _save_sheet(images, specs, _walk_poses(geometry.motion_step), args.output / "walk_front_left.png")
    _save_manifest(source, args.output, specs, geometry)

    assert len(images) == 15 and all(image.size == source.size and image.mode == "RGBA" for image in images.values())
    assert Image.open(args.output / "idle_front_left.png").size == (source.width * 6, source.height)
    assert Image.open(args.output / "walk_front_left.png").size == (source.width * 6, source.height)
    rebuilt = _render_pose(images, specs, idle_poses[0])
    changed = sum(px != (0, 0, 0, 0) for px in ImageChops.difference(source, rebuilt).get_flattened_data())
    print(f"Mapped visible bbox {geometry.source_bbox} at x={geometry.scale_x:.3f}, y={geometry.scale_y:.3f}")
    print(f"Built 15 RGBA parts and two 6-frame sheets at {source.size}; motion step={geometry.motion_step}px")
    print("Validated source coverage, fixed idle feet, and zero body/hand mask overlap")
    print(f"Rest-pose changed pixels (joint alpha overlap): {changed}/{source.width * source.height}")


if __name__ == "__main__":
    main()
