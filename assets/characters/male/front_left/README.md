# Male front-left pixel rig

This directory is generated from `assets/characters/base/male-front.png`.

- Every body-part PNG uses the current source canvas size, RGBA transparency,
  and the original pixel coordinates.
- Anatomical left/right names are used. In this view, the right limbs appear on
  the left side of the image.
- `idle_front_left.png` and `walk_front_left.png` contain six horizontal frames;
  each frame uses the current source canvas size.
- Godot scene: `res://scenes/characters/rig/male_front_left.tscn`
- Animation names: `idle`, `walk`
- During `idle`, both feet and lower legs stay planted while the body above the
  knees moves vertically by one pixel.

Regenerate after replacing the authored base image:

```powershell
python tools/asset_gen/build_pixel_character_rig.py
```

The normal command preserves all 15 existing part PNGs and only rebuilds the
animation sheets and manifest from those hand-edited parts. It also refuses to
continue if only some part files exist or their canvas differs from the source.

To deliberately discard manual edits and decompose the source again, the
destructive intent must be explicit:

```powershell
python tools/asset_gen/build_pixel_character_rig.py --rebuild-parts
```

The corresponding rear-view assets are generated under `../back_right/` from
`assets/characters/base/male-back.png`.

Side-by-side animation preview scene:

```text
res://scenes/characters/rig/male_front_back_preview.tscn
```

The builder maps normalized anatomical geometry to the source's visible bounds,
then writes the resolved canvas, pivots, and motion step to `rig_manifest.json`.
The Godot rig reads that manifest, so a source resolution change does not leave
stale hard-coded joint coordinates in the scene.
