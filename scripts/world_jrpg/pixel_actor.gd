extends Node3D
## Original 24 x 32 pixel characters, four directions and three walking frames.
## Palette and silhouette are shared by the sample and atlas export tool.
const PALETTES := {
	"hero": ["26314a", "e9b887", "4a3539", "397e99", "71bbc2", "e7d5ad"],
	"sage": ["2c3540", "e6bb95", "d3d0bb", "657d53", "9eaf75", "f0deb6"],
	"merchant": ["3c2d36", "dba780", "694435", "ab6050", "e19b69", "eed8a6"],
	"knight": ["293544", "ddb593", "66534a", "798fa1", "b8cbd0", "bc7254"],
	"enemy": ["302935", "b6bd87", "4b4549", "805367", "b87c83", "d4b47e"]
}
@export_enum("hero", "sage", "merchant", "knight", "enemy") var palette_name := "hero"
var sprite: Sprite3D
var walking := false
var facing := 0
var elapsed := 0.0

static func atlas(kind: String) -> Image:
	var image := Image.create(72, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var colors: Array = PALETTES.get(kind, PALETTES.hero)
	for direction in 4:
		for frame in 3:
			var ox := frame * 24
			var oy := direction * 32
			var bob := 1 if frame == 1 else 0
			var rects := [
				[7, 3, 10, 9, 0], [8, 4, 8, 8, 1], [7, 2, 10, 4, 2], [7, 5, 2, 5, 2],
				[8, 12, 8, 14, 0], [9, 13, 6, 11, 3], [10, 14, 2, 8, 4],
				[5, 13, 3, 10, 0], [6, 14, 2, 7, 3], [6, 21, 2, 3, 1],
				[16, 13, 3, 10, 0], [16, 14, 2, 7, 3], [16, 21, 2, 3, 1],
				[8, 22, 8, 2, 2], [11, 22, 2, 2, 5], [8, 12, 8, 2, 5]
			]
			if kind == "hero":
				rects.append_array([[4, 14, 2, 11, 3], [4, 14, 1, 11, 4], [18, 19, 2, 9, 5], [17, 19, 4, 1, 2]])
			elif kind == "sage":
				rects.append_array([[7, 2, 10, 3, 3], [6, 5, 2, 7, 3], [16, 5, 2, 7, 3], [7, 23, 10, 5, 3], [8, 26, 8, 2, 5]])
			elif kind == "merchant":
				rects.append_array([[9, 16, 6, 10, 5], [10, 20, 4, 2, 3], [7, 1, 10, 3, 3], [6, 4, 12, 1, 5]])
			elif kind == "knight":
				rects.append_array([[6, 13, 3, 4, 4], [15, 13, 4, 4, 4], [9, 15, 6, 5, 4], [11, 12, 2, 12, 5]])
			elif kind == "enemy":
				rects.append_array([[6, 3, 3, 2, 1], [15, 3, 3, 2, 1], [7, 14, 2, 9, 2], [15, 14, 2, 9, 2]])
			if direction == 3:
				rects.append_array([[8, 5, 8, 6, 2], [8, 15, 8, 10, 3], [9, 15, 2, 9, 4]])
			else:
				rects.append_array([[10, 7, 1, 2, 0], [14, 7, 1, 2, 0], [12, 10, 2, 1, 2]])
			if direction == 1 or direction == 2:
				rects.append_array([[7, 4, 4, 7, 2], [15, 8, 2, 2, 1], [10, 15, 4, 8, 4]])
			for rect in rects:
				var px: int = rect[0]
				if direction == 2: px = 24 - px - int(rect[2])
				image.fill_rect(Rect2i(ox + px, oy + rect[1] + bob, rect[2], rect[3]), Color(colors[rect[4]]))
			var step := frame - 1
			for leg in 2:
				image.fill_rect(Rect2i(ox + 8 + leg * 5, oy + 25, 3, 5 + (step if leg == 0 else -step)), Color(colors[0]))
	return image

func _ready() -> void:
	sprite = Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(atlas(palette_name))
	sprite.hframes = 3
	sprite.vframes = 4
	sprite.pixel_size = 0.072
	sprite.position.y = 1.12
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	add_child(sprite)
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.015
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.15, 0.18, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material = mat
	shadow.mesh = disc
	shadow.position.y = 0.04
	add_child(shadow)

func _process(delta: float) -> void:
	elapsed += delta
	sprite.frame = facing * 3 + (int(elapsed * 8) % 3 if walking else 1)
