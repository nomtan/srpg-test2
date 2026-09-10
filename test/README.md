# test/ — Character Export test scene

`character_export_test.tscn` is a standalone Godot scene for verifying Phase 5
"Export for Godot" output from `tools/character-editor`. It does **not** load
`Main.tscn` or any gameplay script.

## Use

1. In the Character Builder (`tools/character-editor`, `npm run dev`), build a
   character and press **Export for Godot** → **Download ZIP**.
2. Unzip. Copy `<id>/<id>.glb` and `<id>/<id>.character.json` into
   `res://test/exports/`.
3. In the Godot editor let the `.glb` reimport, then set (Import dock, `.glb` selected):
   - Nodes → Apply Root Scale: on, Root Scale: `1.0`
   - Animation → Import: on
   - See `tools/character-editor/docs/godot-import-guide.md` for the pixel-filter step.
4. Open `res://test/character_export_test.tscn`, press **F6**.

The scene loads the newest `.glb` in `res://test/exports/` (or falls back to
`res://assets/world_jrpg/explorer_base_1.glb`), reads the sibling
`*.character.json` animation mapping, and prints mesh/material/animation counts
and the AABB height compared with the explorer base (~1.845 m).

## Keys

| Key | Action |
| --- | --- |
| `1` | idle |
| `2` | run |
| `3` | attack |
| `R` | reload newest export |
| `TAB` | cycle raw clip names |
