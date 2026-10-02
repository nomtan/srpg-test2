# Character Asset Golden Path

以下は Body007 / Face007 以降にも同じ手順を使う。ID 固有の Godot 分岐や Body ごとの Face offset を追加してはならない。

## 1. Immutable source を配置

```text
assets/characters/tripo/body/007/model.glb
assets/characters/tripo/face/007/model.glb
```

raw GLB は以後上書きしない。`normalization.json` に `source_sha256` を記録する。

## 2. Inspector

```powershell
python tools/asset_gen/character_pipeline/inspect_character_asset.py --kind body --id 007 --output artifacts/body007-inspection.json
python tools/asset_gen/character_pipeline/inspect_character_asset.py --kind face --id 007 --output artifacts/face007-inspection.json
```

Body は source geometry / material / texture / transform / rig を確認する。Face は bounds、origin、Head/Hair materials、UV、neck fit を確認する。

## 3. Metadata を作る

新規Faceは Head/Hair authoring → ExpressionUV authoring → ExpressionMask を明示してからNormalizerへ進む。[v2契約と作業用GLB手順](face-expression-rendering-v2.md) を使用する。原本に境界がない場合は別working GLBを作り、`--authored-face`で指定する。

既存ファイルをコピーせず、対象 source の hash と実測 fit を書く。Face は `Head*` / `Hair*` material を両方持たせる。分類できない geometry を normalizer に推測させない。

## 4. Blender normalizer を staging へ実行

```powershell
blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind body --id 007 --output-root artifacts/modular_staging
blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind face --id 007 --output-root artifacts/modular_staging
```

Body は `humanoid_v1` へ fit / weight transfer し、4 clips を作る。Face は `humanoid_v1_rest` へ transform を焼き込み、Head/Hair contract を確認する。どちらも base-color-only toon material へ整理する。

## 5. Validator

```powershell
python tools/asset_gen/character_pipeline/validate_modular_parts.py --root artifacts/modular_staging --json-output artifacts/modular_staging/validation.json
```

FAIL は Blender / metadata へ戻す。Validator 自身は修正しない。WARNING は理由を明文化して承認するまで正式 assets へ入れない。

## 6. 正式配置と Godot import

staging の検証済み `model.glb` だけを `assets/characters/modular/{body,face}/007/` へ配置する。source GLB は変更しない。`registry.json` の Reference Set は規格試験集合なので、通常の追加だけで無条件に増やさない。

## 7. Combination / runtime test

- 新規 Body × Reference Faces 001〜006
- Reference Bodies 001〜006 × 新規 Face
- `idle`, `walk`, `attack`, `hit`
- normal / angry / smile と個別 channel
- 同一 Face 3個体の expression isolation
- roster / BattleUnit で実際に使用する CharacterDefinition がある場合はその経路

```powershell
godot --headless --path . --script tools/asset_gen/character_pipeline/verify_modular_parts.gd
```

## 8. Game camera validation

front-ish / back-ish / battle distance で、首接続、前髪、表情、outline、shadow、armor clipping を見る。数値 PASS だけで正式化しない。

## 9. PASS

Inspector report、Validator report、runtime test、camera review が揃った時点で正式ゲームアセットとする。Body / Face を追加しただけでは CharacterDefinition は作らない。

