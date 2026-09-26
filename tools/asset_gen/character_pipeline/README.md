# Character Pipeline Tools

Tripoで生成したFace/Bodyのraw GLBを、Blender MCPでGodot用キャラクターへ変換するための補助ツール。

## Source layout

```text
assets/characters/tripo/
├─ face/<id>/model.glb
├─ body/<id>/model.glb
└─ characters/<character_id>.json
```

raw `model.glb` は原本として扱い、直接変更・上書きしない。

## Validate sources

```bash
python tools/asset_gen/character_pipeline/scan_sources.py
```

正常時はFace/Body件数を表示して終了コード0を返す。

## Generate catalog

```bash
python tools/asset_gen/character_pipeline/scan_sources.py --write-catalog
```

以下を生成する。

```text
assets/characters/tripo/catalog.json
```

## Blender/Codex flow

仕様:

```text
docs/character/tripo-character-pipeline.md
```

Codex + Blender MCPへ最初に実行させるGolden Path指示書:

```text
.codex/character_pipeline.md
```

現在のサンプルは `body/001 + face/001`、`body/002 + face/002`、
`body/003 + face/003` の3体を使用する。Blender MCPから
`build_characters.py` の `build('001')`、`build('002')`、`build('003')` を実行する。
Godot側の検証は `verify_characters.gd` と
`scripts/world_jrpg/verify_tripo_switching.gd` を使用する。
以前のGolden Path出力や旧ロスター用のモデル資源は整理済み。
