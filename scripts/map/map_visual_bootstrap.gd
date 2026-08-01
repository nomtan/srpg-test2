extends Node

## Applies the first-pass visual polish preset before battle map nodes run _ready().
##
## The tactical grid remains cell-based, while rendering uses the existing
## transition overlays, painted grass carpet and denser grass props to reduce
## the visible "one box per tile" repetition.

const TARGET_GRASS_PROP_CHANCE := 0.325
const TARGET_GRASS_TRANSITION_FRINGE := 0.24
const TARGET_PAINTED_GRASS_FRINGE := 0.22


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_apply_to_existing_nodes(get_tree().root)


func _on_node_added(node: Node) -> void:
	_apply_visual_preset(node)


func _apply_to_existing_nodes(node: Node) -> void:
	_apply_visual_preset(node)
	for child in node.get_children():
		_apply_to_existing_nodes(child)


func _apply_visual_preset(node: Node) -> void:
	if node is VoxelMap:
		_apply_map_preset(node as VoxelMap)
	elif node is DirectionalLight3D:
		_apply_light_preset(node as DirectionalLight3D)


func _apply_map_preset(map: VoxelMap) -> void:
	map.grass_prop_chance = TARGET_GRASS_PROP_CHANCE
	map.grass_transitions_enabled = true
	map.grass_transition_fringe_width = TARGET_GRASS_TRANSITION_FRINGE
	map.painted_grass_overlays_enabled = true
	map.painted_grass_edge_fringe_width = TARGET_PAINTED_GRASS_FRINGE


func _apply_light_preset(light: DirectionalLight3D) -> void:
	# Contact shadows are essential for grounding props and characters against
	# the terrain. Keep the existing warm key-light direction and energy.
	light.shadow_enabled = true
	light.shadow_opacity = 0.42
	light.shadow_bias = 0.035
