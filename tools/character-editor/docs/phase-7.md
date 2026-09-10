# Phase 7: Asset / Character Management Layer

Phase 6 までの機能（Asset Creator / Character Builder / Godot Export / Character Registry）は
置き換えず、その上に **管理レイヤー** を追加する。正式 Base Body は
`assets/characters/base/base_1.bbmodel`。既存の Source / Rig / Animation 構造は未変更。

```
Asset Creator ─┐                       ┌─ Godot Export ─ Character Registry ─ Game
               ├─ Library (index) ─ Validation ─┤
Character Builder ─┘                    └─ (Batch Export / Registry Sync)
```

## 追加画面 / ナビゲーション

| Route | 画面 | 内容 |
| --- | --- | --- |
| `/dashboard` | Library Dashboard | Assets / Characters / Validation Errors / Re-export Required / Registry Issues / Missing Deps のカウント、Recently Updated、Registry Sync、Export Library Index |
| `/assets` | Asset Library | カテゴリツリー・検索・Sort・一覧・Detail/Edit/Duplicate/Version/Used-By/Delete・Import Package |
| `/characters` | Character Library | 検索・Tag/状態フィルタ・一覧・Detail・Re-export・Batch Export・Register・Duplicate Recipe・Import Recipe |
| `/validation` | Library Validation | Validate All Assets / Characters、Error/Warning 一覧（クリックで Detail へ） |
| `/` `/creator` | 既存 Builder / Creator | それぞれ「Save to Character Library」「Save to Asset Library」を追加 |

## Persistence（spec prompt 47-48）

ブラウザメモリのみに保持しない。ローカルの Next Route Handler
`src/app/api/library/[[...path]]/route.ts` が `node:fs` で
`tools/character-editor/library-data/` を読み書きする。

```
library-data/
  assets/<assetId>/index.json      AssetRecord   (+ model.glb / texture.png / thumbnail.png)
  characters/<characterId>/index.json  CharacterRecord (+ thumbnail.png)
  registry.json                    RegistryFile  (Godot character registry のミラー)
```

`library-data/` は開発マシンの作業インデックスなので `.gitignore` 済み（README のみ追跡）。
リリース対象の portable asset は従来どおり `assets/character-assets/<category>/<id>/`。
一覧は Thumbnail(PNG) と index.json のみ読み込み、GLB は 3D Preview を開いた時だけ
`GET /api/library/<kind>/<id>/file/<name>` で取得する（spec prompt 49）。

### API

| Method Path | 動作 |
| --- | --- |
| `GET /api/library` | LibraryIndex 全体（assets[] / characters[] / registry） |
| `GET /api/library/backup` | Export Library Index（index + versions + tags + dependencies、バイナリ無し） |
| `GET/PUT /api/library/registry` | RegistryFile |
| `PUT/DELETE /api/library/asset/<id>` | AssetRecord upsert / 削除（使用中は 409、`?force=1` で強制） |
| `PUT/DELETE /api/library/character/<id>` | CharacterRecord upsert / 削除（Registry 登録中は 409、`?force=1`） |
| `GET/PUT /api/library/<kind>/<id>/file/<model.glb|texture.png|thumbnail.png>` | バイナリ |

## データ構造

### AssetRecord（`domain/library-index.ts`）

`metadata: AssetMetadata`（`assetVersion` を含む。`description?` / `tags?` を追加）＋
`tags` / `favorite` / `validation {status, checkedAt, issues[]}` /
`versionHistory: {version, previousVersion, updatedAt, note}[]` / `createdAt` / `updatedAt` /
`files {model,texture,thumbnail,source}` / `origin`。

### CharacterRecord

`recipe: CharacterRecipe`（`characterVersion` を含む）＋ `name` / `tags` / `favorite` /
`validation` / `versionHistory` / `thumbnail` /
`export {status, exportedAt, exportedCharacterVersion, exportedAssetVersions, activeAnimationSet, lastError}` /
`registry {status, registeredAt, registeredCharacterVersion, lastError}` / `origin`。

## Dependency Tracking（`domain/library-dependency.ts`）

`recipeAssetRefs(recipe, knownIds)` が `body.assetId` + 埋まっている装備スロットの asset id を
返し、`buildDependencyGraph()` が

- `byCharacter[charId] → AssetRef[]`（`missing: boolean` 付き）
- `usedBy[assetId] → charId[]`（Asset Detail の "Used By Characters"）
- `missingByCharacter[charId] → assetId[]`（Character Library の ⚠ Missing Asset 表示）

を構築する。存在しない id を参照していても一覧は壊れない（spec prompt 21）。

## Version 管理（`domain/library-index.ts`）

`bumpVersionHistory(history, current, note)` が `version = current + 1` と
`{version, previousVersion, updatedAt, note}` を積む。

- Asset: Asset Creator からの **Update Existing**、Library の Edit 保存、手動 Bump Version で +1。
- Character: Builder / Library で recipe が変わって保存されたときに `characterVersion` +1。

v1 は Current / Previous / Updated At の追跡のみ。差分表示は将来拡張（`versionHistory` を保持）。

## Stale Detection（`domain/library-stale.ts`）

`evaluateExport(character, assetsById)`:

1. `export.exportedAt == null` → **not_exported**
2. `export.status == export_error` → **export_error**
3. それ以外は現在の recipe の asset 参照と `export.exportedAssetVersions` を突き合わせ:
   - asset の現在 `assetVersion` > baked version → `updated`
   - Export 後に追加 / 削除された asset → `added` / `removed`
   - 参照先が消えた → `missing`
   - `characterVersion` > `exportedCharacterVersion`
   いずれかあれば **reexport_required**（理由リスト付き）、なければ **up_to_date**

Export 成功時に `currentAssetVersionSnapshot()` を `export.exportedAssetVersions` に保存。

## Validation 構造（`domain/library-validation.ts`）

`ValidationStatus = valid | warning | error | unknown`（UI: ✓ / ⚠ / ✕ / ?）。
`LibIssue {level, code, message, targetId?}` を `rollUpStatus()` で status に集約。

- `validateAssetRecord`: snake_case id / name / bodyTypes / model.glb 有無 / palette slot /
  weapon(handling, animationSet, grip) / headgear の hairPolicy。
- `validateCharacterRecord`: id、palette hex、**使用 Asset の存在**（missing → error）、
  BodyType 互換、asset model 有無、Weapon handling 干渉（two_hand + off_hand）、
  Animation Set 解決、Stale/Export 可否。
- Bulk: `/validation` の Validate All → `runBulkValidation()` が全 record を再検証し、
  status が変わったものだけ PUT。結果カウントを表示。

Asset Creator の `validateDraft()`（GLB/Texture の深い検査）は authoring 時のまま。

## Registry Sync（`domain/library-registry.ts`）

`library-data/registry.json` が Godot 側 registry のミラー。`diffRegistry(characters, file)`:

- `missingInRegistry`: Library にあるが未登録
- `unknownInRegistry`: registry にあるが Library に無い（spec prompt 32）
- `versionMismatch`: `characterVersion` 不一致

Character Detail の **Register Character** で `upsertRegistryEntry()` → `PUT /registry` し、
record の `registry.status` を更新。Character Library の "Export 時に自動 Registry 更新"
チェックで Export 成功時に自動登録。Dashboard に Registry Sync サマリ。

## Batch Export（`features/library/export-helpers.ts`）

`reexportCharacter(record, library, index, opts)` が Phase 5 の `bakeCharacter()` を
そのまま再利用（activeAnimationSet は装備中 Main Hand 武器から解決）。成功で
`recordCharacterExport()` が `export` 状態＋任意で Registry 更新、ZIP をダウンロード。
Character Library でチェックした複数キャラを順に実行するのが Batch Export。

## Builder / Creator 連携

- `features/library/creator-save.tsx`: Asset Creator に "Save to Asset Library" を追加。
  同一 ID が index にあれば **Update Existing (v n → v n+1)**、無ければ **Create New**。
- `features/library/builder-save.tsx`: Character Builder に "Save to Character Library"。
- `features/asset-library/use-library.ts` の `useMergedLibrary()` が
  static(base+demo) + **filesystem library** + localStorage(legacy) をマージするので、
  保存した Asset は Character Builder / Asset Creator の Picker に即時反映される。

## ID Stability（spec prompt 43-44）

Asset ID / Character ID は write-once。Rename は表示名（`name`）のみ。ID 変更機能は
Phase 7 では **実装しない**（dependency 書き換えを安全にできないため、prompt 44 の推奨に従う）。
Duplicate は `nextDuplicateId()` で `…_001 → …_002`（連番が無ければ `…_copy`）。

## Delete Policy（spec prompt 20, 45）

- Asset: 使用中は `409 in_use`（`usedByCount` / `usedBy` を返す）。UI は "used by N characters"
  を出し、明示的な Force Delete のみ許可。
- Character: Registry 登録中は `409`。UI で unregister → 削除の確認。
- Generated Export（ZIP / GLB）: 再生成可能なので保存しない（ダウンロードのみ）。

## 変更 / 追加ファイル

追加（domain）: `library-index.ts` / `library-ids.ts` / `library-dependency.ts` /
`library-stale.ts` / `library-validation.ts` / `library-registry.ts`

追加（features/library）: `use-library-index.ts` / `api.ts` / `derive.ts` / `mutations.ts` /
`import.ts` / `export-helpers.ts` / `server/store.ts` / `components/badges.tsx` /
`dashboard-screen.tsx` / `asset-library-screen.tsx` / `asset-detail-panel.tsx` /
`character-library-screen.tsx` / `character-detail-panel.tsx` / `validation-screen.tsx` /
`creator-save.tsx` / `builder-save.tsx`

追加（app）: `api/library/[[...path]]/route.ts` / `dashboard/` / `assets/` / `characters/` /
`validation/` の `page.tsx`

変更: `app/layout.tsx`（nav）/ `app/globals.css`（Phase 7 スタイル）/ `domain/asset.ts`
（`description?` / `tags?`）/ `features/asset-library/use-library.ts`（fs マージ）/
`features/asset-creator/creator-screen.tsx`（`CreatorLibrarySave`）/
`features/character-builder/builder-screen.tsx`（`BuilderLibrarySave`）/ `.gitignore`

`assets/characters/base/base_1.bbmodel` および既存 Godot / Source / Rig / Animation は未変更。

## 現在の制約

- 実ブラウザでの目視サインオフ未実施（typecheck / lint / `next build` PASS、
  `/api/library` の GET/PUT/DELETE・delete guard(409/force)・4 画面 HTTP 200 は
  ローカル dev サーバで確認済み）。
- `library-data/` は `.gitignore` 済みの作業インデックス。チーム共有は Export Library Index
  の JSON を手動でやり取りする前提。複数ユーザー同時編集は非対応（prompt 50）。
- Godot 側の registry.json 実読み込みコードは本 Phase では追加していない（editor 側で
  ミラーを書き出すところまで）。実際の Godot import 連携は次段階。
- Version History は番号と時刻のみ。差分ビューアは無し。
- Thumbnail は Builder/Creator で Capture したものを保存。Library 一覧からの一括再生成は無し。
- Stale 判定は `assetVersion` の数値比較。GLB 内容ハッシュの比較は行わない。
- Batch Export は逐次実行（並列化なし）。大量時は時間がかかる。

## Phase 8 へ残した課題

spec prompt 50 のとおり: AI Agent 直接実行 / 自動 3D・Texture 生成 / GitHub 自動 commit /
複数ユーザー / Cloud DB / Asset Marketplace / Runtime 装備変更・Character Creator / LOD /
Async Asset Streaming / IK / Physics / NPC 大量自動生成。加えて本 Phase で見えた宿題:
Godot 側 registry.json ローダー、Asset ID 変更＋dependency 一括書き換え、Version 差分ビューア、
GLB ハッシュベースの stale 判定、Thumbnail 一括再生成、Batch Export の並列化、
`library-data/` のチーム同期方式。
