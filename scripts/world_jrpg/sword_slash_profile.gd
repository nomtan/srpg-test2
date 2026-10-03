@tool
class_name SwordSlashProfile
extends Resource
## Settings for one attack's slash effect (see sword_slash.gd). One resource per attack clip and hand,
## so each attack is tuned in the inspector without touching code.

@export_group("Timing")
## Clip time (seconds) at which the arc starts to appear.
@export var start_time := 0.0
## Seconds from appearing to the full swing, when the arc is longest and brightest. Line this up with the hit.
@export var swing_time := 0.08
## Seconds the thin afterglow lingers after the full swing.
@export var afterglow_time := 0.18
## Playback rate on top of the attack clip's own speed (hit-stop also freezes the effect).
@export var speed := 1.0
## Move with the character after the cut starts; off leaves the arc where it was cut.
@export var follow_character := false

@export_group("Placement")
## Arc center in character space: +Z forward, -X the right-hand side, in skeleton units.
@export var offset := Vector3.ZERO
## Tilt of the arc plane. The arc starts on local +X and sweeps about local +Y.
@export var rotation_degrees := Vector3.ZERO
@export var scale := Vector3.ONE
## Mirror across the character's left and right (for the other hand).
@export var mirror := false

@export_group("Shape")
## Outer edge of the arc (the blade tip's path).
@export var radius := 1.0
## Radial width of the band, inward from the radius.
@export var width := 0.6
## Angle swept from start to full swing.
@export_range(10.0, 360.0) var sweep_degrees := 180.0
## Fraction of the arc lit behind the leading tip.
@export_range(0.05, 1.0) var trail_length := 0.75
## Crescent thickness behind the tip, as a fraction of the band width.
@export_range(0.0, 1.0) var thickness := 0.7

@export_group("Look")
@export var core_color := Color(1.0, 0.99, 0.93)
@export var glow_color := Color(1.0, 0.8, 0.3)
@export var fade_color := Color(0.95, 0.4, 0.08)
@export_range(0.0, 8.0) var intensity := 1.6
## Extra brightness at the full swing.
@export_range(0.0, 4.0) var peak_flash := 1.0
## Thickness of the afterglow line, as a fraction of the band width.
@export_range(0.0, 1.0) var afterglow_width := 0.07
## How far the afterglow stretches back along the arc as it fades (fraction of the arc).
@export_range(0.0, 1.0) var afterglow_stretch := 0.25
## Fade curve of the afterglow: above 1 lingers then drops, below 1 fades early.
@export_range(0.1, 6.0) var afterglow_fade := 1.6
## Transparent sort order against other effects (higher draws on top).
@export_range(-128, 127) var render_priority := 0

@export_group("Replacement")
## Finished material replacing the generated look. A ShaderMaterial receives `progress`, `peak` and `opacity`.
@export var material: Material
## Finished mesh replacing the generated arc (UV.x along the swing 0 → 1, UV.y inner edge 0 → outer edge 1).
@export var mesh: Mesh

func duration() -> float:
	return (swing_time + afterglow_time) / maxf(speed, 0.01)

## Arc placement in character space.
func placement() -> Transform3D:
	var basis := Basis.from_euler(rotation_degrees * PI / 180.0) * Basis.from_scale(scale)
	var origin := offset
	if mirror:
		basis = Basis.from_scale(Vector3(-1, 1, 1)) * basis
		origin.x = -origin.x
	return Transform3D(basis, origin)
