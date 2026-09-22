class_name AdventurerAppearance
extends Resource
## Each character owns its face and hair choice; the job body is shared.
## Replacement GLBs follow the same feet origin / 2.2 m / +Z-facing contract.

@export var face_scene: PackedScene = preload("res://assets/characters/meshy_adventure/face_default.glb")
@export var face_texture: Texture2D
@export var hair_scene: PackedScene = preload("res://assets/characters/meshy_adventure/hair_tousled.glb")
@export var hair_tint: Color = Color.WHITE
@export_enum("neutral", "smile", "blink", "angry") var expression: String = "neutral"
