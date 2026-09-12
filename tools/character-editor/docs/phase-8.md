# Phase 8: Character Variation Generator

Phase 1-7 の機能は置き換えない。Asset Library / Character Library の**上**に生成レイヤーを追加する。
正式 Base Body は `assets/characters/base/base_1.bbmodel`。Rig / Animation / Export 経路は未変更。

```
Asset Library (tags / rarity / weight)
        │
        ▼
Variation Preset ──► Generator (Seed + Weighted Random + Compatibility) ──► Preview
                                                                             │ 確定
                                                                             ▼
                                                        Character Recipe ──► Character Library
                                                                             │
                                                                             ▼
                                                              Batch Export (Phase 7) ──► GLB
```

生成するのは **Character Recipe だけ**。GLB は Export 時にのみ Bake する（spec section 30 / 33 / 35）。

| Route | 画面 |
| --- | --- |
| `/variations` | Variation Generator（Preset 一覧 / Generate / Preset Editor / Palette Sets / 選択 Character の 3D Preview） |

## 1. Variation Preset Schema

`domain/variation-preset.ts`。1 Preset = 1 JSON = `library-data/variation-presets/<id>.json`。

```jsonc
{
  "specVersion": 1,
  "presetVersion": 3,
  "id": "kingdom_soldier",
  "name": "Kingdom Soldier",
  "description": "",

  "faction": "kingdom",          // Character Tag に継承 (section 36)
  "role": "soldier",             // Character Tag に継承 (section 37)
  "suggestedRole": "soldier",    // Metadata のみ。Job/Stats とは非結合 (section 38-39)

  "bodyTypes": ["adult"],        // adult / child
  "genderExpression": "any",     // any | male_style | female_style | neutral
  "count": 20,                   // 1 - 100
  "seed": 12345,

  "bodyScale": {
    "profile": "normal",         // normal | slightly_large | slightly_slim | wide_variation | custom
    "height":    { "min": 0.95, "max": 1.05 },
    "bodyWidth": { "min": 0.95, "max": 1.05 },
    "headScale": { "min": 0.97, "max": 1.03 }
  },

  "shoulderMode": "symmetric",   // both | left | right | none | random | symmetric

  "slots": {                     // 13 装備スロットすべてに同じ形
    "mainHand": {
      "presence": "required",    // required | optional | forbidden
      "probability": 0.5,        // optional のときだけ使用
      "tags": ["kingdom"],       // いずれか一致（any-of）。空 = 制約なし
      "excludeTags": [],
      "assetIds": [],            // Allowed Assets の明示指定。空 = tag 条件に合う全て
      "weaponTypes": ["sword", "spear"],   // mainHand / offHand のみ
      "weights": { "sword_kingdom_001": 20 }  // Asset 個別 Weight 上書き
    }
    // hair / headgear / headAccessory / chestArmor / shoulderLeft / shoulderRight /
    // armArmor / gloves / waist / boots / offHand / back
  },

  "palette": {
    "setId": "kingdom",
    "slots": {
      "primary":   { "mode": "set"  },   // set | pool | fixed
      "secondary": { "mode": "set"  },
      "metal":     { "mode": "set"  },
      "leather":   { "mode": "set"  },
      "hair":      { "mode": "pool" },
      "skin":      { "mode": "pool" }
    }
  },

  "tags": [],                    // faction / role に追加する Character Tag
  "idPrefix": "kingdom_soldier", // 生成 Character ID の接頭辞
  "namePrefix": "Kingdom Soldier",
  "updatedAt": "..."
}
```

`parsePreset()` は寛容パース（未知キー破棄・欠損キーは既定値）なので、
手書き JSON や旧 Preset を Import しても壊れない。初回起動時に
`builtinPresets()` の 8 種（kingdom_soldier / empire_soldier / kingdom_archer /
empire_knight / bandit / villager / elf_warrior / elf_archer）が `variation-presets/` へ
seed される。以後はディレクトリが正で、削除した Preset は復活しない。

## 2. Random Generator 構造

`domain/variation-generator.ts`。完全ランダムではなく
`Rules + Asset Tags + Compatibility + Weighted Random`（spec section 2）。

1. **Body**: `bodyTypes` から bodyType を抽選 → `bodyScale` の範囲から height / bodyWidth /
   headScale を一様抽選 → `0.85 - 1.15` にクランプ → 小数 2 桁に丸め。
   `bodyPresetFor()` が bodyWidth から `adult_slim / adult_normal / adult_large / child` を決定。
2. **Equipment**: `SLOT_ORDER` の順に 1 スロットずつ決定する。順序には意味がある。
   - `mainHand` が最初 — Two Hand なら `offHand` を候補空間から外す（section 13）。
   - `headgear` / `headAccessory` は `hair` より前 — `hairPolicy: "hide"` の兜が
     optional な髪型を抑制する（section 11 Hair Policy）。
3. 各スロットで `presence` を評価 → `forbidden` は null、`optional` は
   `probability` を判定、`required` は必ず抽選。
4. 候補プールを `buildPool()` で作り、`pickWeighted()` で Weight 抽選。
5. **Palette** を Palette Set / Pool から抽選。
6. Recipe を組み立て、`generation` メタデータを付与。

失敗（required スロットの候補 0 件）はその 1 体だけを `failures[]` に落とし、
バッチ全体は継続する（section 45）。無限リトライは行わない（section 44）。

## 3. Seed 方式

`domain/variation-rng.ts`。`Math.random()` は **UI の Generate New Seed ボタンだけ**で使う。

```
streamRng(seed, presetId, index, salt, field) → mulberry32(FNV-1a("seed|preset|index|salt|field"))
```

名前付きストリームにしたことで 3 つの性質が同時に成立する。

| 要件 | 効果 |
| --- | --- |
| section 20 再現性 | 同じ Preset + Seed + Asset Library なら同じバッチ |
| section 26 単体 Reroll | `index` が違えば独立 → 007 の Reroll は 001-006 に影響しない |
| section 27 Lock | `field` が違えば独立 → Weapon を引き直しても Hair の抽選列は動かない |

Reroll は当該 Character の `salt` を +1 するだけ。Seed は Recipe の
`generation.seed` に保存される（section 21）。

## 4. Weight 処理

`resolveWeight(asset, rule)` の優先順位（section 9-10）:

```
Preset の slots[slot].weights[assetId]   （数値指定・最優先）
  → AssetMetadata.weight                （数値指定）
    → AssetMetadata.rarity              common 10 / uncommon 4 / rare 1
      → 10 (common 相当)
```

さらに Gender Expression 係数を掛ける（section 8）。

| Asset の style tag | any | 指定と一致 | neutral のみ | 指定と不一致 |
| --- | --- | --- | --- | --- |
| 係数 | 1 | 2 | 1 | 0（候補から除外） |

style tag を持たない Asset は常に係数 1。特定 Tag を必須にしないという方針（section 5）に合わせ、
Tag 条件は **any-of**（いずれか一致）で、tag 無指定なら制約なし。

`pickWeighted()` は weight 0 以下を飛ばし、全部 0 のときだけ一様抽選にフォールバックするので、
Tag 付けが不完全な Library でも行き止まりにならない。

Rarity / Weight は Asset Library の Detail → Edit タブで設定でき、`asset.json` に保存される。

## 5. Asset Compatibility 判定

`domain/variation-candidates.ts` の `checkCandidate()`。**抽選前に候補から除外**する方式で、
生成後に弾いてリトライしない。

| 対象 | 判定 |
| --- | --- |
| Socket / カテゴリ | `SLOT_CATEGORY[slot]`（Phase 5 と同一表）に `asset.type` が含まれるか |
| BodyType | `bodyTypes` が空、または Character の bodyType を含むか |
| Export 可能性 | `model.glb` がない Asset は候補にしない |
| Weapon Handling | mainHand に `off_hand` 武器は不可 / offHand に `two_hand` 武器は不可 |
| Two Hand | mainHand が `two_hand` なら offHand を丸ごとスキップ（section 13） |
| Weapon Type | `rule.weaponTypes` による制限（section 12） |
| hideParts | 既に装備した Asset の `hideParts` が塞ぐスロットは optional ならスキップ |
| Hair Policy | `hairPolicy: "hide"` の Headgear は `hair` を hidden 扱いにする |
| left / right | `shoulderMode` が左右の装備可否を決める（section 16） |
| Animation Set | mainHand の `animationSet` は Phase 5 の `activeAnimationSetFor()` がそのまま解決 |
| 重複装備 | 同じ Asset を 1 体の 2 スロットに使わない |

Symmetric Only（統一感が必要な兵士向け）は `pairShoulder()` が左肩の相方を探す。
ID 規約（`_left` ↔ `_right`）が最優先、なければ Tag 重なり + 名前一致でスコアリングする。

## 6. Palette Set 構造

`domain/variation-palette.ts` / `library-data/palette-sets.json`。完全な RGB Random は行わない。

```jsonc
{
  "specVersion": 1,
  "sets": [
    { "id": "kingdom", "name": "Kingdom",
      "colors": { "primary": ["#263f70", "#314f82"], "secondary": ["#d8d8d8"],
                  "metal": ["#929292"], "leather": ["#6b4a2f"], "hair": [], "skin": [] } }
  ],
  "skinPool": ["#f3d3bd", "#e8bda0", "..."],
  "hairPool": ["#1d1613", "#36251c", "..."]
}
```

- 既定 Set: `kingdom` / `empire` / `elf` / `villager` / `bandit`。
- Set の slot が空なら skin / hair は共通 Pool へ、その他は Recipe 既定色へフォールバック。
- Preset 側の per-slot モード: `set`（Palette Set から抽選）/ `pool`（Skin・Hair Pool から抽選）/
  `fixed`（固定色）。
- Palette Sets タブで Set の追加・削除・色の追加削除、Skin / Hair Pool の編集ができる。
  不正な hex は保存時に除去される。

## 7. Duplicate Detection 方式

section 28-29 のとおり **完全一致のみ**。見た目の類似判定は行わない。

```
signature = "<bodyType>:<height>/<bodyWidth>/<headScale>|<slot=assetId × 13>|<palette × 6>"
```

バッチ生成中は `Map<signature, id>` を持ち、衝突したら salt を +1 して最大 6 回まで引き直す。
それでも一致する場合は捨てずに `duplicate: true` + Warning を付けて残し、
Preview のカードに赤枠と `Duplicate` バッジを出す。
Generate Characters は duplicate を除外して登録するか確認する。
Reroll 後は `markDuplicates()` が一覧全体の重複フラグを付け直す。

## 8. Character Recipe 生成方式

生成物は Phase 5 と同じ `CharacterRecipe` で、`generation` ブロックだけが追加される
（手動 Character には付かない / section 32）。

```json
{
  "specVersion": 1,
  "characterVersion": 1,
  "id": "kingdom_soldier_001",
  "body": { "base": "adult", "preset": "adult_normal", "assetId": "base_body",
            "scale": { "height": 1.02, "bodyWidth": 0.98, "headScale": 1.0 } },
  "assets": { "hair": "hair_short_001", "chestArmor": "armor_kingdom_001", "mainHand": "sword_kingdom_001", "...": null },
  "palette": { "primary": "#263f70", "secondary": "#d8d8d8", "metal": "#929292",
               "leather": "#6b4a2f", "hair": "#36251c", "skin": "#d8aa85" },
  "generation": {
    "type": "variation", "preset": "kingdom_soldier", "seed": 12345,
    "index": 0, "salt": 0, "presetVersion": 1, "generatedAt": "..."
  }
}
```

- **ID**: `<idPrefix>_001` から連番。Character Library の既存 ID と、同一バッチ内の ID を
  両方スキップする（section 22）。
- **Name**: `<namePrefix> 001`。固有名詞生成はしない（section 23）。
- `generation.modified` は `saveCharacter()` が付ける。Character Builder で recipe を変更して
  保存すると `true` になり、自動生成物を手で直したことが残る（section 49）。

## 9. Character Library との統合

- `commitVariations()` が `CharacterRecord` を作って `PUT /api/library/character/<id>`。
  `origin: "variation"`、Tag は `faction` / `role` / `generated` / Preset の追加 Tag。
  GLB は焼かない（section 30 / 33 / 35）。
- Character Library に **Generated (Variation)** フィルタと **Variation Preset** 絞り込みを追加。
  一覧の副題に生成元 Preset を表示。
- Character Detail に `Generated by` / `Seed` 行（section 31）と
  **Open in Character Builder**（recipe を Builder の作業スロットへ渡す / section 48）。
- Dashboard に `Variation Presets` / `Generated Characters` カードを追加。
- Batch Export / Re-export / Registry / Dependency Tracking / Stale 検出は Phase 7 の仕組みを
  そのまま使う。Variation Character 専用の別管理は作っていない（section 46）。

## 10. Performance 対策

| 項目 | 方式 |
| --- | --- |
| 生成 | Recipe のみ。GLB / Texture / Three.js シーンには一切触れない |
| 100 体生成 | 純ドメイン処理で約 15 ms（`npm run verify:variation` 同等条件で計測） |
| Preview 一覧 | Asset の `thumbnail.png` と Palette スウォッチのみ。`<img loading="lazy">`（section 24） |
| 3D Preview | 選択した 1 体だけ `CharacterPreview` を生成（section 25） |
| Preset Editor | 候補プールは `useMemo` でスロット単位に計算。Asset の metadata のみ参照 |
| Count 上限 | 1 - 100 に clamp。超過は Validation エラーで生成前に止める（section 34） |
| Export | 従来どおり Character Library の Batch Export（逐次） |

## 11. Validation（section 43-45）

`domain/variation-validation.ts` の `validatePreset()` が、生成前に以下を判定する。
error が 1 件でもあれば **Preview Variations を実行しない**。

- Preset ID が空 / snake_case でない / 他 Preset と重複
- Count が 1 - 100 の外
- BodyType が 0 件
- Palette Set が存在しない / `fixed` の色が `#RRGGBB` でない
- Probability が 0 - 1 の外
- Body Scale の min > max（範囲外は warning + クランプ）
- required カテゴリの候補 Asset が 0 件（除外理由の内訳付き）
- **生成不可能な組み合わせ**: required bow（両手）+ required Off Hand、
  Main Hand の候補が両手武器のみ + Off Hand required、
  Weapon Type 制限が両手武器のみ + Off Hand required
- Symmetric Only なのに右肩候補が無い（warning）

各スロットの候補数は Preset Editor のヘッダに常時表示され、0 件なら赤くなる。

## 12. 追加 / 変更ファイル

追加（domain）: `variation-rng.ts` / `variation-preset.ts` / `variation-palette.ts` /
`variation-candidates.ts` / `variation-generator.ts` / `variation-validation.ts` /
`character-generation.ts`

追加（features）: `variation/adapt.ts` / `variation/variation-screen.tsx` /
`variation/preset-editor.tsx` / `variation/palette-set-editor.tsx` /
`variation/variation-grid.tsx` / `variation/variation-detail.tsx` /
`character-builder/builder-storage.ts`

追加（app / scripts）: `app/variations/page.tsx` / `scripts/verify-variation.mjs` /
`scripts/register-ts-alias.mjs` / `scripts/ts-resolve-hook.mjs`

変更: `domain/constants.ts`（`ASSET_RARITIES` / `RARITY_WEIGHT`）/ `domain/asset.ts`
（`rarity?` / `weight?`）/ `domain/character-recipe.ts`（`generation?`）/
`domain/builder-recipe.ts`（`generation` の往復保持）/ `domain/library-index.ts`
（`LibraryIndex.presets` / `.palettes`、`origin: "variation"`）/
`features/library/server/store.ts`（preset / palette 永続化 + 初回 seed）/
`app/api/library/[[...path]]/route.ts`（`presets` / `palettes` / `preset/<id>`）/
`features/library/api.ts` / `features/library/mutations.ts`（`commitVariations` /
`generation.modified`）/ `features/library/derive.ts` / `dashboard-screen.tsx` /
`character-library-screen.tsx` / `character-detail-panel.tsx` / `asset-detail-panel.tsx` /
`features/asset-library/library.ts`（`thumbnailUrl`）/
`features/character-builder/builder-screen.tsx` / `app/layout.tsx` / `app/globals.css` /
`package.json`

`assets/characters/base/base_1.bbmodel` および Godot 側は未変更。

## 13. 現在の制約

- 実ブラウザでの目視サインオフは未実施。`npm run typecheck` / `lint` / `build` /
  `verify:variation`（47 チェック）PASS、production サーバで `/variations` `/characters` `/`
  の HTTP 200、`/api/library` の preset・palette GET/PUT/DELETE、生成 Recipe の PUT 往復、
  `generation` メタデータの保存を確認済み。
- 生成候補は **Merged Asset Library**（静的 base/demo + Phase 7 `library-data`）から採る。
  一方 Phase 7 の Dependency / Validation は `library-data` の Asset しか知らないため、
  静的 demo Asset を引いた Character は Character Library で `Missing Asset` になる。
  これは Phase 7 からの既存挙動（Character Builder で demo Asset を装備した場合も同じ）で、
  Asset Creator から Asset Library へ登録すれば解消する。
- Tag 条件は any-of 固定。all-of（全 Tag 必須）や Tag ごとの重み付けは未実装。
- Gender Expression は「不一致 style tag の除外 + 一致 tag の weight ×2 + bodyWidth の微調整」まで。
  専用の体型プリセットや顔まわりの出し分けは行わない。
- `hideParts` 判定は `SLOT_HIDE_KEYS` の名前一致ヒューリスティック。Base Model の
  part map が確定していないため、厳密な部位干渉判定ではない。
- Duplicate は完全一致のみ（section 29 の方針どおり）。見た目 Similarity は判定しない。
- Reroll の Lock 単位はスロット / Body Scale / Palette。Palette の slot 単位 Lock は無い。
- Preset ID は保存後は変更不可（Asset / Character ID と同じ write-once 方針）。Duplicate で新 ID を作る。
- Preview 状態はメモリのみ。ページを離れると Preview は消える（Seed を控えれば再現できる）。
- `Regenerate from Preset` は「Preset を編集 → Preview Variations をやり直す」操作で、
  既存 Character を上書きしない。ID は既存を避けるため新規採番になる。
- Preset Editor の Allowed Assets 一覧は BodyType = `bodyTypes[0]` を前提に候補数を出す。
  adult / child 併用 Preset では adult 基準の件数表示になる。

## 14. Phase 9 へ残した課題

spec section 50 のとおり: AI による Asset 自動制作 / AI Agent への直接 Prompt 送信 /
自動 NPC 名前生成 / Unit Stats 自動生成 / Job 自動割り当て / Map への NPC 自動配置 /
Runtime Random Character 生成 / GitHub 自動 Commit / Cloud DB / Multiplayer / IK / Physics / LOD。

本 Phase で見えた宿題:

- Phase 7 の Dependency / Validation に静的 base・demo Asset を認識させる（上記の Missing Asset）。
- Preview 結果の保存（Preset + Seed + Lock 状態のスナップショット）と、
  既存 Character を対象にした差分 Regenerate。
- Tag の all-of / 重み付き Tag マッチ、Tag の階層化（faction > unit > tier）。
- 見た目 Similarity（色距離・シルエット）による近似重複の検出。
- Preview 一覧用の Thumbnail 自動生成（現状は Asset Thumbnail の寄せ集め）。
- 生成 Character の一括 Thumbnail Bake と Batch Export の並列化。
- Preset の Version 履歴（現状は `presetVersion` の番号のみ）。
