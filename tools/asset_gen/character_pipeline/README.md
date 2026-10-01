# Character Pipeline Tools

正式な Phase 4 仕様と新規アセット手順:

- `docs/character/character-asset-standard-v1.md`
- `docs/character/character-asset-golden-path.md`
- `inspect_character_asset.py`: source / modular の機械可読メトリクス
- `validate_modular_parts.py`: Standard v1 の PASS / WARNING / FAIL 判定

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

新規パーツは `build_modular_parts.py` でTripo原本からBody/Face/Hairを個別出力し、
`validate_modular_parts.py` と `verify_modular_parts.gd` で検証する。
`build_characters.py`、`export_modular_parts.py`、`verify_characters.gd` は
旧統合GLBの再現・回帰比較用として保持する。新規パーツの正式手順には使わない。
