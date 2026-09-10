# Godot Import Guide — Phase 5 Baked Character

Output of Character Builder → **Export for Godot** → **Download ZIP**:

```
<id>.zip
└─ <id>/
   ├─ <id>.glb              Final mesh + rig node hierarchy + node-TRS animation clips + equipment
   ├─ <id>.png              Palette reference (64×64, 6 bands). Colours are ALSO baked into the
   │                        GLB material baseColorFactor — this PNG is documentation, not required.
   ├─ <id>.character.json   Runtime metadata: animation mapping, activeAnimationSet, palette, assets
   ├─ godot_import_guide.md Short version of this file
   └─ thumbnail.png         (only if a thumbnail was captured)
```

## 1. Place files

Copy `<id>.glb` **and** `<id>.character.json` into `res://test/exports/` (test scene) or your
own character directory. Keep them side by side — the test scene finds the JSON next to the GLB.

## 2. Import settings

Select `<id>.glb` in the FileSystem dock → **Import** tab:

| Setting | Value | Why |
| --- | --- | --- |
| Nodes → Apply Root Scale | on | |
| Nodes → Root Scale | `1.0` | 1 glTF unit = 1 m = 1/12 Blockbench unit. Same rule as `assets/world_jrpg/explorer_base_1.glb` (`tools/asset_gen/export_explorer_model.py`, `SCALE = 1/12`). A baked character is ~1.845 m tall, identical to the in‑game explorer base. |
| Nodes → Root Type | `Node3D` | Root transform is already identity at the feet. |
| Animation → Import | on | |
| Animation → FPS | `30` | matches `explorer_base_1.glb.import` |
| Animation → Trimming | off | keep source clip lengths |
| Skins → Use Named Skins | on | (base_1 has no skin; harmless) |

Click **Reimport**.

`base_1.bbmodel` is **rigid‑node animated** — there is no `Skeleton3D`/skin. The "rig" is the
named node hierarchy (`ganmen`, `dou`, `kahanshi`, `hand_right_te`, …). Equipment nodes
(`MainHand`, `ChestArmor`, …) are children of their socket nodes, so they follow the animation.

## 3. Keep the pixel / blocky look (prompt 11 / 27)

A GLB cannot fully carry Godot's texture filter. Pick one:

- **Project‑wide:** Project Settings → Rendering → Textures → *Default Texture Filter* = **Nearest**.
- **Per material:** select the imported material(s) → Sampling → *Filter* = **Nearest**.
- **Import script:** attach a script in the Import tab that walks `BaseMaterial3D`s and sets
  `texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST`.

The palette is in `baseColorFactor` (linear), so Three.js and Godot show the same colours with
**no shader‑side palette swap** in v1. If a future asset ships a real texture, also set its
material `texture_filter` to Nearest.

Materials are low‑poly `StandardMaterial3D`, `metallic 0 / roughness 1`, single‑sided. If a mesh
looks inside‑out, enable *Cull → Disabled* on that material (report it back — the source face
winding should be fixed instead).

## 4. Animation mapping (`<id>.character.json`)

```json
{
  "activeAnimationSet": "onehand_sword",
  "animations": {
    "default":       { "walk": "animation.walk_mcp_test", "run": "animation.run" },
    "onehand_sword": { "idle": "animation.onehand_sword_idle", "run": "animation.onehand_sword_run", "attack": "animation.onehand_sword_attack" },
    "great_sword":   { "idle": "animation.great_sword_idle", "run": "animation.great_sword_run", "attack": "animation.gread_sword_attack" }
  }
}
```

Resolve a role as: `animations[activeAnimationSet][role]` → else `animations["default"][role]` →
else substring match. Clip names keep the **source spelling**, including the
`animation.gread_sword_attack` typo — normalise through this map, do **not** rename clips in the GLB.

`activeAnimationSet` comes from the equipped Main Hand weapon's `animationSet` (spec section 5.2 /
14). With no weapon it is `"default"` (only `walk` / `run` are baked for `default`).

## 5. Test scene

`res://test/character_export_test.tscn` (script `res://test/character_export_test.gd`):

- loads the newest `.glb` in `res://test/exports/` (fallback: `res://assets/world_jrpg/explorer_base_1.glb`),
- reads the sibling `*.character.json`,
- prints mesh / material / animation counts and the AABB height vs the explorer base,
- keys: `1` idle, `2` run, `3` attack, `R` reload, `TAB` cycle raw clips.

It is standalone and does not touch `Main.tscn` or gameplay scripts.
