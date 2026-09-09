@tool
extends Node3D
## Reusable procedural voxel assets. Origins sit on the ground plane.
const Batch = preload("res://scripts/map/open_world/voxel_batch.gd")
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
			b.box(p + Vector3(0, 1.4, 0) * scale_factor, Vector3(0.5, 2.8, 0.5) * scale_factor, "trunk")
			if type == "pine":
				for i in 5:
					var width := 3.3 - i * 0.55
					b.box(p + Vector3(0, 2.0 + i * 0.65, 0) * scale_factor, Vector3(width, 0.8, width) * scale_factor, "pine" if i % 2 == 0 else "pine_light")
			else:
				b.box(p + Vector3(0, 3.0, 0) * scale_factor, Vector3(3.4, 1.6, 2.8) * scale_factor, "leaf")
				b.box(p + Vector3(-0.4, 4.0, 0.2) * scale_factor, Vector3(2.4, 0.8, 2.3) * scale_factor, "leaf_light")
				b.box(p + Vector3(1.3, 2.7, 0.5) * scale_factor, Vector3(1.2, 1.1, 1.7) * scale_factor, "leaf_light")
		"rock":
			b.box(p + Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 1.3) * scale_factor, "rock")
			b.box(p + Vector3(0.2, 0.95, 0), Vector3(0.9, 0.5, 1.0) * scale_factor, "rock_light")
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
