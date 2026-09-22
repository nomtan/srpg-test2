# Phase 5: Godot Export (Baked Character)

Character Builder で構成したキャラクターを、Godot へ Import 可能な 1 キャラクター Asset
（`<id>.glb` + `<id>.png` + `<id>.character.json`）として Bake / Export する。基準 Base Body は
`assets/characters/base/base_1.bbmodel`。既存の Source / Rig / Animation / Pivot / Group 構造は
変更していない。Bake は毎回 GLTFLoader で読み込んだコピー Scene 上で行い、Source は書き換えない
（prompt 29）。

## Export Pipeline

`src/features/character-builder/export/bake.ts` の `bakeCharacter()` が 8 工程を順に実行し、
各工程を UI に表示する（prompt 20）。失敗は `BakeError { step }` で「どの工程か」を UI に出す
（prompt 30）。

| # | Step | 実装 | 内容 |
| --- | --- | --- | --- |
| 1 | Validating character | `export/export-validation.ts` | Error があれば停止、Warning のみは続行（prompt 3） |
| 2 | Baking palette | `export/palette-bake.ts` | Palette → 64×64 PNG（6 バンド） |
| 3 | Preparing meshes | `character-scene.ts` `buildCharacterScene()` | Base GLB + 装備 GLB を Socket へ合成、Palette / hideParts / hairPolicy / Body Scale を反映 |
| 4 | Exporting animations | — | 必要 clip（idle/walk/run/attack × activeSet + default）の充足チェック |
| 5 | Creating GLB | `export/glb-export.ts` | `GLTFExporter`（`binary` / `onlyVisible` / `animations` / `trs`） |
| 6 | Generating metadata | `domain/character-export.ts` | `character.json` を固定キー順で生成 |
| 7 | Packaging files | `features/asset-creator/zip.ts` `createZip()` | `<id>/` 配下に glb / png / json / import guide (+ thumbnail) を store-only zip |
| 8 | Round-trip validation | `export/round-trip.ts` | 生成 GLB を GLTFLoader で再 Import して検証（prompt 22-23） |

完了後、`Export Complete` カードにファイル一覧・サイズ・Round-trip 結果・`Download ZIP`・
`Exported GLB Preview`（再 Import した GLB を Three.js で再生、clip 切替可）を表示（prompt 21-22）。

Browser Export のみ（prompt 19）。リポジトリへの自動 commit はしない。

## Body Part Colors

Base Body の色は Palette の `skin` が全体に適用されるが、`recipe.bodyPartColors` で
**パーツ単位の上書き**ができる。

```jsonc
"bodyPartColors": {
  "ganmenn": "#d8aa85",   // 顔だけ別の色
  "te_left": "#aa3333"
}
```

- 指定のあるパーツはその色、**無いパーツは `palette.skin`** にフォールバックする。
- キーは Base Model の mesh 名（`BASE_PARTS` と同じ 18 種）。未設定なら JSON にキー自体を書かない。
- `ashikubi` / `ashisaki` は Base に左右2つずつ同名で存在するため、**左右同時に色が変わる**
  （`hideParts` と同じ制約）。Builder の一覧では「左右同時」と表示する。
- 不正な色は警告として捨て、Recipe 全体は失敗させない（`skin` に必ずフォールバックできるため）。
- Export した `character.json` にも `bodyPartColors` が入る（未設定時はキーごと省略）。

実装は `viewer/palette/bodyPartTint.ts`。Base GLB は **20 mesh すべてが 1 つの Material を共有**
しているので、mesh の material に直接色を書くと全身が塗り変わる。上書きのあるパーツだけ Material
を clone し、同じ色のパーツは clone を使い回す。フォールバックのパーツは共有 Material のまま
`skin` を受け取る。

### パーツの特定は名前ではなく element UUID で行う

**GLTFLoader は重複するノード名に連番を付けて一意化する。** Base GLB を読み込むと:

```
ashisaki → ashisaki, ashisaki_1     (左右2つ)
ashikubi → ashikubi, ashikubi_1     (左右2つ)
dou      → dou_1                    (グループ `dou` と衝突するため mesh 側が改名される)
```

そのため名前一致では**足の片側しか塗られず、胴体は一度も一致しない**。各 mesh ノードには
Blockbench の element UUID が `extras.sourceUuid`（読み込み後は `userData.sourceUuid`）として
入っているので、`basePartNameOf()`（`features/asset-creator/base-parts.ts`）がこれで解決する。

**`hideParts` も同じ経路に統一した**。Phase 4 のドキュメントは「左右同名パーツは同時に隠れる」と
書いていたが、実際には同じ理由で片側しか隠れておらず、`dou` は一度も隠せていなかった。

`verify:export` に回帰チェックがある。実際の Base GLB を GLTFLoader で読み込み、
ashisaki / ashikubi が 2 mesh とも解決されること、dou が解決されること、両足が同時に塗られること、
色の漏れ出しが無いこと、clone 数、Recipe 往復を検証する。

## GLB 生成方式

- `GLTFExporter.parse(CharacterRoot, …, { binary:true, onlyVisible:true, animations:baseClips, trs:true })`。
- **Flatten しない**：`CharacterRoot > Base(base_1 の 46 group + 可視 20 mesh) > …` の Node 階層をそのまま保持。
  装備は Socket 親ノード（`ganmen` / `dou` / `hand_right_te` …）の子として追加し、意味的な Node 名
  （`Hair` / `Headgear` / `ChestArmor` / `ShoulderLeft` / `MainHand` / `OffHand` …）を付ける（prompt 5）。
- base_1 は **skin なしの rigid-node アニメーション**。Skeleton3D は存在せず、"Rig" は名前付き Node 階層。
  Animation clip（node TRS チャンネル）を `animations` オプションで GLB に含めるため、装備は親 Node の
  アニメーションに追従する。
- **Socket Transform の Bake**：装備は Preview と同じ親子付けのまま Export するので、`grip → socket` の
  位置関係が Node の local TRS として GLB に焼き込まれ、Godot 再 Import 後も同じ（prompt 7）。Round-trip で
  各装備 Node のワールド座標を Bake 前と比較（許容 0.15 m）。
- **hideParts の Bake**：選択装備の `hideParts` に一致する Base mesh を `visible=false` にし、`onlyVisible`
  で GLB から除外（prompt 8）。除外方式のみ。mesh 削除・skinning 改変はしない。
- **hairPolicy の Bake**：Headgear の `hairPolicy==="hide"` のとき Hair 装備 Node を `visible=false` →
  GLB から除外。Recipe には「Hair として何を選んだか」は残る（選択状態 ≠ Export visibility, prompt 9）。
  `character.json.visibility.hairPolicy` に状態を記録。

## Palette Bake 方式

- v1 は per-texel palette swap をしない（prompt 10）。
- Preview で各 material の `color` に Palette 色を適用（Base body = `skin`、装備 = その asset の
  `appearance.paletteSlots[0]`）。同じ material を GLTFExporter が `baseColorFactor` として書き出すため、
  **Three.js Preview と Godot が同じ色**になる（Godot 側 shader 不要）。
- `<id>.png` は 64×64 の Palette 参照（6 スロットのバンド）。「Base Texture + Palette → Final Texture PNG」
  の簡易版で、ファイルは常に存在する。将来テクスチャ付き asset を扱うときの拡張ポイント。

## Animation Export 方式

- `scripts/build-base-model.mjs` が Source の 17 clip を node-TRS で焼いた
  `public/generated-assets/base_body/model.glb` の clip を、そのまま `GLTFExporter` の `animations` に渡す。
- clip 名は Source のまま（`animation.onehand_sword_attack`、typo の `animation.gread_sword_attack` を含む）。
  GLB 内では **rename しない**（prompt 12-13）。
- `idle / walk / run / attack` を最低ラインとしてカバー（`default` は walk / run のみ焼かれているため、
  idle / attack は weapon set 側から解決）。

## Character Metadata Schema

`domain/character-export.ts`。spec section 15 準拠。固定キー順で `characterMetadataText()` が出力。

```jsonc
{
  "specVersion": 1,
  "characterVersion": 1,          // 再 Export 用（prompt 17）。v1 は手動、自動採番なし
  "id": "vein",                   // snake_case 必須。不正文字は Validation Error（prompt 18）
  "name": "Vein",
  "body": { "base": "adult", "preset": "adult_normal",
            "scale": { "height": 1, "bodyWidth": 1, "headScale": 1 } },
  "assets": {                     // 選択状態（Recipe 由来）。base + 13 装備スロット
    "base": "base_body", "hair": null, "headgear": null, "headAccessory": null,
    "chestArmor": null, "shoulderLeft": null, "shoulderRight": null,
    "armArmor": null, "gloves": null, "waist": null, "boots": null,
    "mainHand": "demo_sword_001", "offHand": "demo_shield_001", "back": null
  },
  "palette": { "primary": "#8c2430", "secondary": "#303030", "metal": "#a0a0a0",
               "leather": "#654321", "hair": "#36251c", "skin": "#d8aa85" },
  "activeAnimationSet": "onehand_sword",   // 装備中 Main Hand 武器の animationSet（spec 5.2 / prompt 14）
  "animations": {                          // Mapping Layer（prompt 13）。clip 名は正規化せず参照だけ
    "default": { "walk": "animation.walk_mcp_test", "run": "animation.run" },
    "onehand_sword": { "idle": "...idle", "run": "...run", "attack": "...attack" },
    "great_sword": { "attack": "animation.gread_sword_attack" }
    // ... spear / bow / dagger
  },
  "visibility": { "hiddenParts": ["..."], "hairPolicy": "hide" | "overlay" | null },
  "model": "vein.glb",
  "texture": "vein.png",
  "thumbnail": "thumbnail.png",   // 任意
  "generator": { "tool": "srpg-character-editor", "phase": 5,
                 "exportedAt": "<iso>", "scaleRule": "1 glTF unit = 1 m = 1/12 BB unit; ..." }
}
```

Recipe（`*.recipe.json`、再編集用・localStorage 自動保存）と character.json（Godot Runtime 用）は
別ファイル。役割が違うので統合しない（spec section 16 / prompt 16）。

## Godot Scale 変換方式

推測はしていない。既存パイプラインを調査した結果：

- `tools/asset_gen/export_explorer_model.py` は `SCALE = 1/12` で `base_1.bbmodel` を
  `assets/world_jrpg/explorer_base_1.glb` に出力。
- `assets/world_jrpg/explorer_base_1.glb.import` は `apply_root_scale=true`, `root_scale=1.0`。
- `scripts/world_jrpg/explorer_actor.gd` はモデルに追加スケールを掛けない。
- `tools/character-editor/src/domain/base-rig.ts` の `metersPerSourceUnit = 1/12`、
  `scripts/build-base-model.mjs` も同じ 1/12 で Preview GLB を生成 → **Editor の Base GLB は既に Godot スケール**。

結論：**1 glTF unit = 1 metre = 1/12 Blockbench unit。Export は再正規化しない**。Godot は
`root_scale = 1.0` で Import、1 field cell = 1 m。Baked Character の rest-pose 身長 ≈ **1.845 m**
（`22.144 BB units × 1/12`）で、既存の `explorer_base_1.glb` と一致。

## Godot Import 結果

`test/character_export_test.tscn` を headless 実行（`--headless --quit-after 20`）した実測：

```
source: res://assets/world_jrpg/explorer_base_1.glb  (fallback; test/exports 未配置時)
meshes: 20   materials: 4
animations: idle, run, walk
AABB size (m): 0.583 x 1.845 x 1.216
height 1.845 m vs explorer base 1.845 m (Δ 0.000 m, 0.0%)
```

Baked Character GLB（`<id>.glb`）を `res://test/exports/` に置いた場合の目視確認
（ブラウザ Export → Godot Editor 再 Import → シーン実行）は本セッションでは未実施。
上の headless 実行で「シーンが GLB を読み、rig / mesh / material / animation を取得し、
AABB 身長が 1.845 m」までは確認済み。

## Test Scene 結果

- `test/character_export_test.tscn` + `test/character_export_test.gd`：既存シーン非依存の専用シーン。
- `--check-only` で GDScript 構文 PASS。`--headless` 実行でエラーなし、上記レポートを出力。
- キー `1/2/3` = idle/run/attack、`R` = reload、`TAB` = raw clip 巡回。
- `test/exports/` に Export した `<id>.glb` (+ `<id>.character.json`) を置くと最新を自動ロード。
- fallback の `explorer_base_1.glb` には `attack` clip がないので `attack` → `run` に解決（Baked Character
  では weapon set の attack clip が入る）。

## Round-trip Validation 結果

`export/round-trip.ts` が生成 GLB を `GLTFLoader.parse` で再 Import し、以下を検証：

- Mesh > 0（error）/ Material > 0（error）/ 埋め込み Texture 0 は warning（色は baseColorFactor 済み）
- 必須 rig ノード（`ganmen` `dou` `kahanshi` `hand_right_te` `hand_left_te` `foot_*`）の存在
- Bounding Box：NaN / 0 / 負は error。身長 0.8–3.0 m 外は warning。Bake 前後の各軸寸法差 5% 超で warning
- Animation：0 clip は error。必要 clip 欠落は warning
- 装備 Node：可視装備ごとに Bake 前ワールド座標との距離 0.15 m 超で warning、一致で info

headless（ブラウザ非依存）側の検証は `npm run verify:export`（`scripts/verify-export.mjs`）：
Base GLB の rig ノード 21 個・baked clip 17 個・`metersPerSourceUnit = 1/12`・身長 1.8454 m・
Animation Mapping（`gread_sword` typo の正規化を含む）・id validator を **ALL PASS**。

## 変更 / 追加ファイル

追加（character-editor）:

- `src/domain/character-export.ts` — character.json 型・`buildCharacterMetadata` / `buildAnimationMapping` / `characterMetadataText` / id validator / scale rule
- `src/domain/builder-recipe.ts` — Phase 5 Recipe ヘルパー（slot→category / slot→socket / slot→node 名 / scale clamp / `emptyRecipe` / `validateRecipeShape` / `recipeText`）
- `src/features/character-builder/character-scene.ts` — `buildCharacterScene()`（Preview と Export で共有）
- `src/features/character-builder/character-preview.tsx` — 合成キャラクターの live Three.js Preview
- `src/features/character-builder/export/` — `export-validation.ts` / `palette-bake.ts` / `glb-export.ts` / `character` metadata（domain 参照）/ `round-trip.ts` / `godot-import-guide.ts` / `bake.ts` / `exported-glb-preview.tsx` / `export-panel.tsx`
- `scripts/verify-export.mjs` + `package.json` に `verify:export`
- `docs/godot-import-guide.md` / `docs/phase-5.md`

変更（character-editor）:

- `src/domain/character-recipe.ts` — `characterVersion?: number` を追加（後方互換）
- `src/features/character-builder/builder-screen.tsx` — Phase 2 の単体ビューアから、13 装備スロット +
  Body Scale + Palette + Animation + Recipe save/load + Export を持つ合成ツールへ全面書き換え
- `src/app/globals.css` — Phase 5 用スタイル追記

追加（リポジトリルート）:

- `test/character_export_test.tscn` / `test/character_export_test.gd` / `test/README.md` / `test/exports/.gitkeep`

`assets/characters/base/base_1.bbmodel` および既存 Godot シーン・スクリプト・生成物は未変更。

## 現在の制約

- ブラウザ実 UI と Godot Editor での目視確認は未実施（本セッションは browser / Editor GUI を起動できない）。
  Static（typecheck / lint / next build）+ headless（Godot `--check-only` / `--headless`、`verify:export`、
  `verify:base`）は PASS。
- Merged Library には現状 `base_body` / `demo_sword_001` / `demo_shield_001`（+ Asset Creator で保存した
  user asset）しか無いので、多くの装備スロットは "None"。Hair / Armor などは Asset Creator（Phase 4）で
  作成・保存すると Builder に出る。
- Palette は per-texel bake ではなく material `baseColorFactor` bake。テクスチャ付き asset の色合成は最小限
  （asset 自身の texture を貼るのみ、パレット swap は色 tint）。
- Socket は既存 group pivot に無校正で取り付け（Phase 2-4 と同じ）。IK / grip 微調整・grip_sub の個別
  socket 割当（両手武器）はしていない。両手武器も Main Hand socket 一括取り付け。
- Body Scale は base root への非一様スケール（height=Y, bodyWidth=X/Z）+ head 一様スケール。傾いた四肢
  Rest Pose のため極端値でわずかにシアーが出る。許容 0.7–1.4、範囲外は Export warning。
- `characterVersion` の自動採番なし（v1 は手動）。
- `parity gate`（Phase 2 の `comparison.json` 実画面目視・`equipmentAssemblyAllowed:false`）は
  Phase 4 と同じく未解決のまま先行実装。

## Phase 6 へ残した課題

prompt 31 のとおり：Godot Runtime での装備変更 / GitHub 自動 commit / AI Asset 自動生成 / AI Agent 自動実行 /
Blockbench・Blender 自動操作 / IK / Cloth・Hair Physics / Animation Retargeting / Asset Dependency 自動解決 /
NPC 大量自動生成。加えて Phase 5 で見えた宿題：per-texel palette bake、grip_sub の個別 socket、
非一様 Body Scale のシアー対策（leaf 単位スケール等）、character.json の自動 version 採番、
実ブラウザ / 実 Godot Editor での目視サインオフ。
