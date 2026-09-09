@tool
extends Node3D
## Procedural props: botanical trees and voxel buildings/rocks. Origins sit on the ground.
const Batch = preload("res://scripts/world_jrpg/voxel_batch.gd")
@export_enum("oak", "pine", "rock", "cottage", "tower") var kind: String = "oak":
	set(value):
		kind = value
		if is_inside_tree():
			_rebuild()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var batch := Batch.new()
	append(batch, kind, Vector3.ZERO)
	batch.commit(self)

static func append(b: RefCounted, type: String, p: Vector3, scale_factor: float = 1.0) -> void:
	match type:
		"oak", "pine":
			var seed_value := int(p.x * 7919 + p.z * 104729 + scale_factor * 313)
			b.vegetation.plant(type, p, scale_factor, fposmod(seed_value * 0.618, TAU), seed_value % 3)
		"rock":
			b.box(p + Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 1.3) * scale_factor, "cliff")
			b.box(p + Vector3(0.2, 0.95, 0), Vector3(0.9, 0.5, 1.0) * scale_factor, "cliff_light")
		"cottage":
			b.box(p + Vector3(0, 0.25, 0), Vector3(5.6, 0.5, 4.6), "rock")
			b.box(p + Vector3(0, 1.65, 0), Vector3(5, 2.5, 4), "plaster")
			for x in [-2.4, 0.0, 2.4]:
				b.box(p + Vector3(x, 1.6, 2.04), Vector3(0.18, 2.7, 0.18), "trunk")
			b.box(p + Vector3(0, 1.2, 2.12), Vector3(0.9, 1.9, 0.15), "wood")
			for x in [-1.4, 1.4]:
				b.box(p + Vector3(x, 1.8, 2.1), Vector3(0.8, 0.85, 0.12), "window")
				b.box(p + Vector3(x, 1.3, 2.2), Vector3(1, 0.15, 0.35), "wood")
			for i in 5:
				b.box(p + Vector3(0, 3.0 + i * 0.35, 0), Vector3(5.8, 0.35, 4.8 - i * 0.9), "roof" if i % 2 == 0 else "roof_light")
			b.box(p + Vector3(1.7, 4.2, -0.8), Vector3(0.6, 2, 0.6), "rock")
			# Timber framing, sill plants and slate roof tiles at sub-voxel scale.
			for z in [-2.04, 2.04]:
				for y in [0.6, 2.8]:
					b.box(p + Vector3(0, y, z), Vector3(5.1, 0.15, 0.15), "trunk")
			for x in [-2.52, 2.52]:
				for z in [-1.9, 0, 1.9]:
					b.box(p + Vector3(x, 1.7, z), Vector3(0.16, 2.5, 0.16), "trunk")
				b.box(p + Vector3(x, 1.8, 0.7), Vector3(0.1, 0.85, 0.7), "window")
			for x in [-1.4, 1.4]:
				b.box(p + Vector3(x, 1.8, 2.18), Vector3(0.08, 0.85, 0.06), "plaster")
				b.box(p + Vector3(x, 1.8, 2.18), Vector3(0.8, 0.08, 0.06), "plaster")
				b.box(p + Vector3(x, 1.4, 2.3), Vector3(0.7, 0.16, 0.25), "leaf")
			b.box(p + Vector3(0.25, 1.2, 2.22), Vector3(0.1, 0.1, 0.1), "gold")
			for i in 5:
				for tile in range(-5, 6):
					for side in [-1, 1]:
						b.box(p + Vector3(tile * 0.5, 3.19 + i * 0.35, side * (2.25 - i * 0.45)), Vector3(0.44, 0.05, 0.33), "roof_light")
		"tower":
			b.box(p + Vector3(0, 0.3, 0), Vector3(5, 0.6, 5), "rock")
			b.box(p + Vector3(0, 3.5, 0), Vector3(3.4, 7, 3.4), "rock_light")
			for y in [1.0, 3.0, 5.0, 7.0]:
				b.box(p + Vector3(0, y, 0), Vector3(3.6, 0.25, 3.6), "rock")
			b.box(p + Vector3(0, 7.4, 0), Vector3(4.5, 0.6, 4.5), "rock")
			for x in [-1.8, 0.0, 1.8]:
				for z in [-1.8, 1.8]:
					b.box(p + Vector3(x, 8.1, z), Vector3(0.8, 0.9, 0.8), "rock_light")
			b.box(p + Vector3(0, 5.3, 1.73), Vector3(0.5, 1.4, 0.08), "window")
			b.box(p + Vector3(0, 9.0, 0), Vector3(0.15, 3.0, 0.15), "trunk")
			b.box(p + Vector3(0.8, 10, 0), Vector3(1.5, 0.8, 0.12), "flag")
