# Male back-right pixel rig

Generated from `assets/characters/base/male-back.png`.

- 15 transparent RGBA body-part PNGs
- `idle_back_right.png`: six horizontal idle frames
- `walk_back_right.png`: six horizontal walk frames
- `rig_manifest.json`: resolved canvas, visible bounds, pivots, and motion step
- Idle keeps both lower legs and feet planted

Regenerate both directions:

```powershell
python tools/asset_gen/build_pixel_character_rig.py
python tools/asset_gen/build_pixel_character_rig.py --source assets/characters/base/male-back.png --output assets/characters/male/back_right --direction back_right
```

These normal commands preserve existing part PNGs. Add `--rebuild-parts` only
when intentionally discarding manual part edits and repeating decomposition.

The shared Godot rig switches textures and pivots between `front_left` and
`back_right`, then rebuilds its animation tracks for the selected geometry.
