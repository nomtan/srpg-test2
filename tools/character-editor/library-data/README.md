# library-data/ — Phase 7 Library Index

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
```

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
asset index, character index, versions, tags and dependencies (no binaries).
