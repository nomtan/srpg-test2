# Ashen Vow Character Asset Standard v1

`ashen_character_v1` は、Tripo 由来の Body / Face を個別の Godot コード変更なしで追加するための正式な入口規格である。001〜006 は規格を決めるための Reference Set であり、既存例外をすべて新規アセットへ継承するものではない。

## 構成

```text
Immutable Tripo source
  → Asset Inspector
  → Blender Normalizer
  → Asset Validator
  → modular asset
  → CharacterAssembler
  → Body + Face + Expression
```

- source: `assets/characters/tripo/{body,face}/NNN/model.glb`（上書き禁止）
- generated: `assets/characters/modular/{body,face}/NNN/model.glb`
- metadata: 各 generated asset の `normalization.json`
- Skeleton Contract: `assets/characters/_shared/rigs/humanoid_v1.glb`
- 機械可読規格: `assets/characters/_shared/character_asset_standard_v1.json`
- 列挙用 registry: `assets/characters/modular/registry.json`

## Coordinate System

- Blender: 1 unit = 1 meter、Z-up
- Godot import: Y-up、scale 1.0
- GLB の render mesh transform: position zero、rotation identity、scale one
- Body は `humanoid_v1` の rest pose に一致させる。
- Face は `humanoid_v1_rest` 空間へ焼き込み、独自 Skeleton / Skin / Animation を持たない。
- runtime は Body の `head` に `FaceSocket` を作り、rest transform を1回だけ相殺する。Body ごとの Face offset は禁止する。

## Contracts

- [Body Asset Standard v1](body-asset-standard-v1.md)
- [Face Asset Standard v1](face-asset-standard-v1.md)
- [Expression Asset Standard v1](expression-asset-standard-v1.md)
- [Golden Path](character-asset-golden-path.md)
- [Face003 normalization analysis](face003-normalization-analysis.md)

## Directory Contract

```text
assets/characters/
├─ _shared/
│  ├─ rigs/humanoid_v1.glb
│  ├─ materials/character_toon.gdshader
│  ├─ face/expression/
│  └─ character_asset_standard_v1.json
├─ tripo/
│  ├─ body/NNN/model.glb
│  └─ face/NNN/model.glb
└─ modular/
   ├─ registry.json
   ├─ body/NNN/{model.glb,normalization.json}
   ├─ face/NNN/{model.glb,normalization.json}
   └─ definitions/
```

Body / Face は再利用可能な部品であるため、追加時に `CharacterDefinition` を自動生成しない。実キャラクターを定義するときだけ `body_id` と `face_id` を持つ definition を作る。

## Metadata Contract

全アセットは最低限 `standard`、`version`、`asset_type`、3桁 `id`、`rig_profile`、`coordinate_space`、`source_sha256` を持つ。Face はさらに `expression_profile`、`position`、`scale` を持つ。旧 `rig_source_body_id` は廃止し、新規 Body の生成は Body001 ではなく `humanoid_v1.glb` のみに依存する。

## Validation

```powershell
python tools/asset_gen/character_pipeline/inspect_character_asset.py --kind body --id 007
python tools/asset_gen/character_pipeline/validate_modular_parts.py --json-output artifacts/character_standard_v1/validation.json
godot --headless --path . --script tools/asset_gen/character_pipeline/verify_modular_parts.gd
```

Validator は修正を行わず、`PASS` / `WARNING` / `FAIL` を区別する。修正責務は Blender normalizer にある。数値検査の PASS だけでは完了とせず、front-ish / back-ish の実ゲームカメラで首、前髪、表情、outline、shadow、clipping を確認する。

## Reference Set Result

- Body001〜006: `humanoid_v1` の65 bones、hierarchy、rest transform、4 clips、weight contract に一致
- Face001〜006: static、identity transform、共通 head-space の hard bounds 内
- 6 Body × 6 Face = 36組: assemble、4 clips、Face follow、expression が成功
- legacy regression: `charcter001`〜`charcter004` が成功
- roster / BattleUnit: 001〜006 が成功
- 60体混在: 120 mesh node、12 unique mesh、12 unique base texture、1,078,140 triangles、expression isolation が成功

既知の WARNING は、legacy combined Head/Hair、Face003 の意図的な高い silhouette、Body006 / Face003 に残る runtime 非使用 normal texture である。新規アセットでは許容しない。

## Naming Migration

既存の `charcterXXX` は多数の scene 参照と互換性があるため v1 では rename しない。将来 `characterXXX` へ移行するときは、resource path、scene path、loadout key、save data を一括で更新する別 migration とする。

