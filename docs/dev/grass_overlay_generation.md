# Low ground-cover grass generation

The four runtime textures are original transparent decals generated with the
built-in image generation tool. The user-provided map screenshot was supplied
only as a visual reference for the short ground carpet's palette, mark size,
and softness. Tall grass is deliberately excluded and remains a separate map
decoration asset.

Final prompt set (the last sentence changes the requested density per image):

> Use image 1 only as a visual style reference. Create one original game
> asset: an orthographic straight top-down ground-cover decal for an isometric
> tactical RPG. Reproduce the character of the short grass carpet visible
> across the ground in the reference: pale yellow-green and muted olive, warm
> sunlit palette, broad hand-painted pixel clusters and soft chunky dabs, low
> cropped grass and tiny ground-cover shapes. It must read as a flat low meadow
> surface, not as upright plants. Irregular organic patch silhouette with
> broken edges and generous empty area around it. Flat perfectly uniform
> `#ff00ff` chroma-key background. No soil, dirt, baked ground, shadow,
> gradient, or lighting outside the grass shapes. Absolutely no tall grass,
> long blades, fern leaves, radial tufts, bushes, flowers, rocks, characters,
> props, UI, text, border, tile grid, or watermark. Avoid fine hair-like
> detail; use larger readable painterly clusters matching the reference at
> game scale. Square image, subject centered, crisp clean chroma-key boundary.
> Create a sparse / medium / medium-dense / dense-but-broken variant.

The image-generation chroma background is removed by the imagegen skill's
`remove_chroma_key.py` helper with a soft matte, edge contraction, and despill.
The resulting `low_grass_rgba_01.png` through `_04.png` sources are retained in
`tools/asset_gen/grass_overlay_sources/`, which is excluded from Godot import.

`process_grass_overlay_variants.py` reduces them to 32 px and an 18-color
shared palette without synthesizing soil or forcing artificial tile seams. It
keeps the original organic alpha openings and writes
`assets/terrain/reference/grass_overlay_01.png` through `_04.png`.

At runtime `flat_painted_grass_overlay.gdshader` places these decals over the
dirt-colored grass boxes. `VoxelMap` supplies four edge and four diagonal
flags; only a same-height dirt neighbor trims the decal inward with a seeded,
pixel-shaped fringe. Grass-to-grass neighbors keep their complete irregular
patches. Separate tall-grass decoration assets can then be placed above this
low ground cover without being baked into every tile.

## Tall-grass decoration sprites

Three additional built-in image generations use the same screenshot only for
style and camera-angle reference. Final shared prompt:

> Use image 1 only as a visual style and viewing-angle reference. Create one
> original isolated tall-grass game sprite asset for the isometric tactical
> RPG map. A dense natural clump of upright meadow grass like the tall grass
> masses along the left and lower edges of the reference: long tapered blades,
> overlapping irregular heights, dark muted olive-green at the roots, pale
> warm yellow-green sunlit tips, hand-painted pixel-art clusters, chunky
> readable marks, restrained contrast. Three-quarter isometric viewing angle
> matching the reference camera, with the grass rising vertically from a very
> narrow root line. The clump should be broad and dense but retain transparent
> gaps between outer blades. Flat perfectly uniform `#ff00ff` chroma-key
> background. No soil patch, ground plane, cast shadow, rocks, flowers,
> characters, props, UI, text, border, tile grid, or watermark. No rectangular
> grass carpet and no top-down flat moss; this is a freestanding tall-grass
> decoration sprite. Crisp clean chroma-key boundary, centered with generous
> margin, square image. Create a wide asymmetric / compact tall / long low-wide
> variant.

The same chroma-key helper creates `tall_grass_rgba_01.png` through `_03.png`.
`process_tall_grass_variants.py` crops each to its visible bounds, aligns the
root line, reduces it to a 128 px transparent sprite, and writes
`assets/terrain/reference/tall_grass_01.png` through `_03.png`. The validation
scene places these as unshaded billboard assets around the grassy rim only.
