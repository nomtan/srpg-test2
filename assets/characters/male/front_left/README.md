# Male front-left pixel rig

This directory is generated from `assets/characters/base/front.png`.

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

The builder maps normalized anatomical geometry to the source's visible bounds,
then writes the resolved canvas, pivots, and motion step to `rig_manifest.json`.
The Godot rig reads that manifest, so a source resolution change does not leave
stale hard-coded joint coordinates in the scene.
