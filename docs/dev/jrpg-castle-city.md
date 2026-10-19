# JRPGWorldSample3 — 風翼の都 アウレリア

`samples/JRPGWorldSample3.tscn` is a walled castle city on an island in a lake, built by
`scripts/world_jrpg/castle_city_world.gd`. It extends JRPGWorldSample2 (`open_field_world.gd`)
and reuses its explorer, camera, HUD, weather, water and toon vegetation. Only the map is new.

## Layout (south → north along the main street, x = 200)

| Area | Where | Notes |
| --- | --- | --- |
| Spawn / shore meadow | (200, 338) | Dirt roads fan out, terraced bluffs ring the basin |
| 白石の大橋 | z 273–316 | Arched spans, lamps with blue-white banners; walkable deck (`_surface`) |
| Gatehouse | z 270 | Twin towers, red banners, pointed arch, raised portcullis, two guards |
| 下町通り (TIERS[0] = 16 m) | z 196–268 | Half-timbered houses on north-running lanes, gate-plaza market, bunting, windmills |
| 騎士の広場 / 騎士団本部 (TIERS[1] = 22 m) | inside R1 = 90 of APEX | Fountain plaza, knights' keep facing the street |
| 天翼の広場 / 風翼大聖堂 (TIERS[2] = 29 m) | inside R2 = 46 of APEX | Winged statue fountain, pavilions, Gothic cathedral |

Terraces are discs around `APEX` (200, 100). Each face is a cliff in the height field, covered
by a retaining wall. Stairs are a ramp along the main street with visual steps on top.

## Build notes

- Static parts go through `_part` and are merged into one mesh per material and 32 m cell.
  Parts under a node with the `dynamic` meta (windmill sails) stay as their own nodes.
- Walls, towers and churches use `castle_stone.gdshader`, world-space masonry registered in
  `Props.materials` so weather (wetness and snow) reaches it.
- Houses fill lots that `_lot_free` accepts: inside the wall, on one terrace, and clear of
  plazas, stairs, landmarks and the windmill sails' sweep.
- The scene starts at midday with clear weather. The time panel still changes it, and some
  windows light up after dusk.

## Commands

```sh
# Captures: bridge, gate, overview, street, plaza, statue, cathedral, keep, lake
godot --path . --resolution 1280x720 res://samples/JRPGWorldSample3.tscn -- --sample-capture --view=bridge --hide-hud --capture-dir=<dir>

# Walk the spawn → bridge → gate → both stairs → cathedral route with the explorer's rules
godot --headless --path . --script res://scripts/world_jrpg/verify_castle_city.gd
```

Keys 1–5 frame the overview, street, plaza, gate and bridge views.
