# library-data/ — Phase 7 Library Index + Phase 8 Variation Presets + Phase 9 AI Production

File-backed store for the Asset / Character **management layer** (spec prompt 47-48). Written by
the local Next route handler at `src/app/api/library/[[...path]]/route.ts`.

```
library-data/
  assets/<assetId>/
    index.json       AssetRecord — metadata + tags + assetVersion history + validation status
    model.glb        (optional) imported / creator-saved runtime model
    texture.png      (optional)
    thumbnail.png    (optional) list view loads only this, never the GLB
  characters/<characterId>/
    index.json       CharacterRecord — recipe + characterVersion history + export + registry state
    thumbnail.png    (optional)
  registry.json      RegistryFile — mirror of the Godot character registry (spec prompt 30-32)
  variation-presets/<presetId>.json
                     VariationPreset — Phase 8 generation rules (tags, presence, probability,
                     weights, body scale ranges, palette plan). Seeded with the 8 built-in
                     presets on first read; the directory is authoritative afterwards.
  palette-sets.json  PaletteLibrary — Phase 8 Palette Sets + shared Skin / Hair pools
  asset-production/<assetId>/
    job.json         ProductionJob — Phase 9 Asset Definition snapshot, status, references,
                     prompt version and the full revision history
    incoming/        files delivered by an external AI, awaiting validation / decision
    approved/        files promoted by Approve (the ones registered in the Asset Library)
    rejected/        files a Reject moved out of the way, kept for comparison
    reference/       reference images (shape / style / color / concept)
```

Production file names are normalized on import to `model_r<n>.glb`, `texture_r<n>.png` and
`source_r<n>.bbmodel`; only `.glb / .png / .jpg / .jpeg / .webp / .bbmodel` are accepted, and
path traversal is rejected by the route handler.

## Source of truth (spec prompt 42, 48)

```
Source Asset (.bbmodel + asset.json)  ->  Character Recipe  ->  Generated GLB  ->  Godot
```

- Committed, portable assets still live under `assets/character-assets/<category>/<id>/`.
- `library-data/` is the **working index** for the editor: it tracks versions, tags, dependency
  and validation state, and caches creator/import binaries. It is not the canonical home for
  release assets and is git-ignored by default (see `.gitignore`).
- Never edit a generated GLB and feed it back to a source. Re-run the Builder export instead.

## Backup

`Dashboard -> Export Library Index` (`GET /api/library/backup`) writes a single JSON with the
asset index, character index, versions, tags and dependencies (no binaries). Phase 8 adds the
Variation Presets and Palette Sets to the same blob; a single preset can also be exported from
the Variation Generator as `<presetId>.json`. Phase 9 adds a production summary (status, prompt
version, per-revision verdict / score) — the Production Packages themselves are regenerated from
`job.json` on demand rather than stored.
