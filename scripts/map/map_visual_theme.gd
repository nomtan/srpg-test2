class_name MapVisualTheme
extends Resource

@export_group("Terrain scenes")
@export var grass_top: PackedScene
@export var dirt_top: PackedScene
@export var stone_top: PackedScene
@export var stone_road_top: PackedScene
@export var water_plane: PackedScene
@export var water_top: PackedScene
@export var bridge_floor: PackedScene
@export var bridge_top: PackedScene
@export var stair_block: PackedScene
@export var stair_top: PackedScene
@export var cliff_side: PackedScene
@export var cliff_corner: PackedScene
@export var bridge_railing: PackedScene

@export_group("Decoration scenes")
@export var grass_patch: PackedScene
@export var broken_stone: PackedScene
@export var flag_placeholder: PackedScene

func top_scene_for(terrain: String) -> PackedScene:
	match terrain:
		"stone", "stone_road", "rock", "wall": return stone_top if stone_top else stone_road_top
		"water": return water_plane if water_plane else water_top
		"bridge": return bridge_floor if bridge_floor else bridge_top
		"stair": return stair_block if stair_block else stair_top
		"dirt", "forest": return dirt_top
		_: return grass_top

func decoration_scene_for(kind: String) -> PackedScene:
	match kind:
		"grass_patch": return grass_patch
		"broken_stone": return broken_stone
		"flag_placeholder": return flag_placeholder
		_: return null
