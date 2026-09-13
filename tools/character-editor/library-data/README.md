# library-data/ — the editor's Git-tracked library

Local JSON, one file per record, plus the asset binaries. **Committed to the repository**: this is
source data, not a cache. Written by the local Next route handler at
`src/app/api/library/[[...path]]/route.ts` through `src/features/library/server/store.ts`.

```
library-data/
  assets/<assetId>/
    index.json       AssetRecord — metadata + tags + assetVersion history + validation status
    model.glb        runtime model
    texture.png      32x32 (or the weapon's own resolution)
    thumbnail.png    list-view image; the list never loads the GLB
  characters/<characterId>/
    index.json       CharacterRecord — recipe + characterVersion history + export + registry state
    thumbnail.png
  registry.json      RegistryFile — mirror of the Godot character registry
  variation-presets/<presetId>.json
                     VariationPreset — Phase 8 generation rules. Seeded with the 8 built-ins on
                     first read; the directory is authoritative afterwards.
  palette-sets.json  PaletteLibrary — Palette Sets + shared Skin / Hair pools
  asset-production/<assetId>/
    job.json         ProductionJob — Asset Definition, status, references, revision history
    approved/        files promoted by Approve — the provenance of the registered asset
    reference/       reference images (shape / style / color / concept)
    incoming/        NOT committed — AI deliveries awaiting a decision
    rejected/        NOT committed — deliveries moved aside, kept locally for comparison
```

## What is committed, and why

Asset binaries are small: `model.glb` is 9–17 KB, `texture.png` is 110–200 bytes (it is a 32×32
pixel-art texture), `thumbnail.png` is 15–20 KB. An asset costs roughly **25–40 KB**, so a hundred
assets is a few megabytes. No Git LFS, and a commit shows the whole change: metadata diff plus the
model and texture that go with it.

What stays out (see `.gitignore`):

| Path | Why |
| --- | --- |
| `asset-production/*/incoming/` | Every AI revision is a full GLB copy, and most are superseded |
| `asset-production/*/rejected/` | Kept locally for comparison; no value in history |
| Character export GLB / ZIP | Regenerated from the recipe on demand, and large. Never written here in the first place |

`job.json` **is** committed even for rejected revisions: it is text, it diffs, and it carries the
prompt version, validation verdicts and revision history that make a result reproducible.

## Diff hygiene

Records are written through `canonical()` in `server/store.ts`, so the same logical record always
serialises byte-identically: fixed top-level key order, unknown keys preserved and sorted after the
known ones, 2-space indent, trailing newline.

**Derived fields are not persisted.** `AssetRecord.files.model / texture / thumbnail` and
`CharacterRecord.thumbnail` are recomputed from disk on every read, so writing them would only
produce noise and drift out of date. Only `files.source` — real data — is stored.

Saving an unchanged record is a no-op in Git terms; re-saving the same record twice produces an
identical file.

## Source of truth

```
Source Asset (.bbmodel + asset.json)  ->  Character Recipe  ->  Generated GLB  ->  Godot
```

- `library-data/` is the editor's authoritative store, in Git.
- `assets/character-assets/<category>/<id>/` remains the layout for assets published into the Godot
  project — the same shape the Phase 9 production prompts ask an AI agent to deliver. Nothing
  writes there yet; the editor exports through the Builder's **Export for Godot** ZIP.
- Never edit a generated GLB and feed it back to a source. Re-run the Builder export instead.

## Backup

`Dashboard -> Export Library Index` (`GET /api/library/backup`) writes a single JSON with the asset
index, character index, versions, tags, dependencies, Variation Presets, Palette Sets and a
production summary (no binaries). With the directory in Git this is a convenience export rather
than the backup — `git log` is the history.
