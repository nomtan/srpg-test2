class_name ExpressionProfile
extends Resource

## Shared rest-space projection. Face variants may select a different profile.
@export var face_rect := Vector4(-0.23, 0.848, 0.46, 0.36)
@export var surface_depth := Vector2(0.18, 0.33)
## Optional legacy-only map of the deepest front-facing layer (the skin) over
## face_rect, baked by build_skin_depth_maps.py. Features are drawn only near it,
## so bangs in front of the skin hide them instead of carrying slices of them.
@export var skin_depth: Texture2D
