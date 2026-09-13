# Phase 9: AI Production Pipeline

Phase 1-8 の機能は置き換えない。Asset Creator と Asset Library の**間**に制作レイヤーを追加する。
正式 Base Body は `assets/characters/base/base_1.bbmodel`。**Phase 9 では Base Body を一切変更していない**
（Source / Rig / Animation / Scale Rule すべて未変更。Phase 5 で確定した Normalization をそのまま使う）。

```
Asset Creator ─ Asset Definition
        │
        ▼
AI Production Package ── Model Prompt / Texture Prompt / Technical Spec
        │                Reference Information / Validation Spec
        ▼
External AI / Codex / 3D Agent        (Phase 9 では自動送信しない)
        │
        ▼  .bbmodel / .glb / .png
Asset Creator Import ─ Validation ─ Approve ─► Asset Library (Phase 7)
        │                  │                        │
        │                  └─ Revision Prompt        ├─► Character Builder (Phase 5)
        └─ Revision History                          └─► Variation Generator (Phase 8)
```

| Route | 画面 |
| --- | --- |
| `/creator` | Asset Creator に **AI Production** パネルを追加（Package 生成 / Preview / Copy All / Export / Reference / Tag） |
| `/production` | **Production Queue**（Filter / 検索 / Batch Export / Job Detail: Import・Validation・Preview・Approve） |
| `/dashboard` | AI Production Jobs と Needs Revision / Error のカウントを追加 |

## 1. Production Package 構造

1 Asset = 1 Package。`<assetId>-ai-package/` として ZIP 出力する。

```
hair_short_001-ai-package/
├─ asset-definition.json   Machine readable な Asset Definition
├─ model-prompt.md         3D Model Prompt
├─ texture-prompt.md       Texture Prompt
├─ technical-spec.md       座標規格・実測寸法・Budget・Naming・Animation
├─ validation-spec.json    Import 時の Validation が読む契約
├─ asset.json              成果物に同梱させる metadata（そのままコピーさせる）
├─ README.md               使い方と非目標
└─ reference/              登録した Reference 画像（あれば）
```

`domain/production-package.ts` が全ファイルを組み立てる。**Package は AI Provider に依存しない
Source of Truth**（spec section 57）で、Provider が無くても完結する。

`asset-definition.json` は spec section 5 のキー（`specVersion` / `asset` / `target` /
`appearance`）をその順で保持し、その後ろに `attachment`（socket transform 込み）/ `equipment` /
`hairPolicy` / `hideParts` / `texture` / `geometry` / `paletteReference` / `references` /
`production` / `tags` / `outputDirectory` / `assetMetadata`（Phase 4 の asset.json そのもの）を足す。

Batch Export（spec section 56）は同じ構造を 1 つの ZIP に複数ディレクトリとして並べ、
索引用の `README.md` を添える。

## 2. Prompt Template 構造

巨大な 1 本の文字列にしない（spec section 26）。

```
src/prompt/
  promptTypes.ts          PromptContext（実測値・Budget・Attachment・Reference を含む）
  promptBuilder.ts        Draft -> PromptContext -> 2 つの Prompt
  modelPromptTemplate.ts  Model Prompt の節構成（spec section 6 の 17 見出し固定）
  texturePromptTemplate.ts Texture Prompt の節構成
  templates/
    types.ts      TypeTemplate インターフェース（geometry / negatives / texture / extraSections）
    common.ts     STYLE / ISOMETRIC / NEGATIVE / SCALE / PROPORTION / ATTACHMENT / ORIGIN /
                  ORIENTATION / POLYGON / MATERIAL / UV / NAMING / OUTPUT / VALIDATION / REFERENCE
    hair.ts  headgear.ts  armor.ts  shoulder.ts  weapon.ts  shield.ts  back.ts
    index.ts      AssetType -> TypeTemplate のレジストリ + テンプレートファイル名
```

Model Prompt の見出しは spec section 6 の順で固定:

```
PURPOSE / REFERENCE MODEL / ASSET TYPE / STYLE / ISOMETRIC READABILITY / SCALE / PROPORTION /
ATTACHMENT / ORIGIN / PIVOT / ORIENTATION / GEOMETRY / POLYGON REQUIREMENTS / MATERIAL / UV /
NAMING / REFERENCE INFORMATION / OUTPUT FORMAT / DO NOT / VALIDATION TARGET
（Weapon のみ WEAPON ORIENTATION を追加）
```

`promptVersion`（現在 **2**）は Prompt と Package と Revision に埋め込み、Template を変えた時に
どの版で作られた Asset かを追跡できる（spec section 50）。Package を再生成すると現在の版が
押し直され、すでに納品済みの Revision は作られた時の版を保持する。

- v1: Phase 9 初版
- v2: `.bbmodel` を**必須成果物**化し、納品フォルダ構造の固定と asset.json の逐語提示を追加
- v3: 左右の訂正（キャラクターの左は -Z）と、Character Builder が Hand Socket に適用する
  Grip Rotation の明示
- v4: Model Prompt が「フィットする体の部位の寸法」だけでなく **Asset 自身の目標サイズ**を明示。
  Shoulder は Coverage 1.5 倍（実生成が小さすぎたため）
- v5: **添付された全身1枚絵の扱い**を明文化。どの部位に絞るか、何を取り込み何を捨てるか、
  この文書が優先する範囲を Model / Texture 双方に記載

### 成果物フォルダ（promptVersion 2）

Model Prompt の `## DELIVERABLES` で、AI に渡す成果物の形を固定した。

```
sword_iron_001/
├─ source/
│   └─ sword_iron_001.bbmodel    editable Blockbench source (REQUIRED — the master file)
├─ model.glb                     runtime mesh, exported from the .bbmodel
├─ texture.png                   32x32, nearest-neighbor
└─ asset.json                    metadata, copied verbatim from this prompt
```

- `.bbmodel` は「できれば」ではなく **必須**。`model.glb` はその `.bbmodel` から export させる。
- ファイル名固定。zip などダウンロード可能な 1 フォルダとして返させ、`source/` を潰させない。
- `## ASSET.JSON` に実際の asset.json を逐語で埋め込み、そのままコピーさせる
  （Package 内の `asset.json` と同一内容）。`source.path` は常に `source/<id>.bbmodel`。
- `thumbnail.png` は Workshop 側が作るので AI には生成させない旨も明記。
- Grip Point は `.bbmodel` と `.glb` の**両方**に要求する。
- `DO NOT` に「`.glb` だけの納品」「ファイル名・構造の変更」を追加。
- Validation 側も `.bbmodel` 欠落を Info → **Warning**（`source_missing`）に格上げし、
  Revision Prompt で `<id>/source/<id>.bbmodel` を要求する文面を自動生成する。

## 3. Asset Type 別 Prompt 設計

| Type | Template | 主な内容 |
| --- | --- | --- |
| hair | `hair.ts` | 既存 head にフィット / 顔を作らない / clipping 回避 / silhouette / socket_hair / headgear 互換 |
| headgear | `headgear.ts` | 既存 head にフィット / hairPolicy (hide・overlay) / face visibility / head clearance |
| head_accessory | `headgear.ts` | 小型 / 髪と共存 / 極小ディテール禁止 |
| chest_armor | `armor.ts` | 既存 torso にフィット / 不要な全身置換禁止 / hideParts 尊重 / clipping / limb articulation |
| arm_armor, gloves, waist, boots | `armor.ts` | 部位ごとの追従 bone・可動域・接地 |
| shoulder_left / right | `shoulder.ts` | 左右独立 / shoulder socket / 腕と一緒に動く / head・chest との衝突回避 |
| weapon | `weapon.ts` | weapon type / handling / grip_main（two_hand は grip_sub）/ animation set / character scale / **weapon orientation** |
| shield | `shield.ts` | off_hand / grip_main / 前面 / hand clearance / body clearance |
| back | `back.ts` | socket_back / body clearance / weapon clearance / silhouette |

共通で必ず入るもの:

- **Style**（spec section 9）: low-poly / blocky / voxel-inspired / simple geometry /
  2.5-3 head-tall / isometric 可読 / strong silhouette / minimal tiny details / flat surfaces。
  既存ゲームの模倣は明示的に禁止し、本プロジェクト独自の blocky 表現として書く。
- **Isometric Readability**（section 10）、**Negative Requirements**（section 34）、
  **Asset 単体生成**（section 8: `Generate only the X asset.` + 生成禁止物の列挙）。

## 4. Technical Specification 構造

`technical-spec.md` と `validation-spec.json` は同じ数値から生成する。

- **Coordinate system**: `+Y up / +X forward / -Z left（+Z right）`、1 unit = 1 m、Godot scale 1.0、
  1 field cell = 1 m、`metersPerSourceUnit = 1/12`。**Phase 5 の実装値をそのまま引用**しており、
  Phase 9 で新しい Scale Rule は作っていない。
- **Measured base body**（spec section 12）: `npm run build:measurements` が
  `public/generated-assets/base_body/measurements.json` を生成する。
  - `character`: 高さ 1.8454 m、bounds、head 0.5833 m、約 3.16 heads tall
  - `regions`: head / head_with_ears / neck / torso / shoulder L,R / upper_arm / forearm /
    hand / pelvis / thigh / ankle / foot の world bounding box（19 領域）
  - `sockets`: 14 socket の Phase 2 定義値（position / rotation / scale）＋実測 world position
  - `recommendedLength`: weapon type 別の推奨全長（character height 比から算出）
  - `referenceProps`: source 内の既存 prop 実測値（多くは hidden placeholder なので
    「サイズ標準ではない」と明記）
- 生成スクリプトは Outliner を build-base-model.mjs と同じ変換モデルで再走査し、
  **結果が Phase 2 の three.js 製 bounds と 1e-6 以内で一致することを自己検証**してから書き出す。
- **Attachment**: socket、asset attachment point、grip alignment（`GRIP_ALIGNMENT` 由来）、
  socket transform（`pivot_only_uncalibrated` である旨も渡す）。
- **Handedness（Phase 9 で訂正）**: 右手系では `forward × left = up` なので `+X × -Z = +Y`、
  すなわち**キャラクターの左は -Z、右は +Z**。Source のグループ名は左右が逆に付いており
  （`hand_left_te` が実際の右手）、`base-rig.ts` の `SOURCE_NODE_BY_SIDE` が物理的な左右から
  Source ノード名を解決する。Source の綴りは変更していない。
- **Attachment Alignment**: `viewer/equipment/gripAlignment.ts`。Grip 取り付けの Asset は
  Socket に「原点」ではなく**宣言された取り付け点**を合わせる。
  - `attachment.main.assetPoint`（既定 `grip_main`）のノードがあれば、そのノードが Socket に来る
  - 無い場合、Shield は **Bounding Box の中心**を Socket に合わせる（腕は盾の中心の裏に来るため）
  - 無い場合、Weapon は原点のままにして警告する（Grip が無いこと自体が Validation の Error）
  Asset を親に付ける前（＝Asset 自身のローカル空間）で測るため、Socket 側の姿勢に影響されない。
- **Reference（添付画像）**: 全身デザインの1枚絵を AI セッションに添付して実行する運用が主なので、
  REFERENCE INFORMATION は **Package に Reference が登録されていなくても常に**指示を出す
  （画像はツールではなく AI 側に添付されるため、Package からは存在を知りようがない）。
  `REFERENCE_FOCUS`（`templates/common.ts`）が Asset Type ごとに「絵のどの部分に絞るか」を
  日本語でなく英語の名詞句で持つ。Shoulder など左右のある Type は
  `attachment.side` から「LEFT のみ・-Z 側」といった取り違え防止の一文を足す。
  優先順位は **この文書 > 1枚絵**（Scale / Proportion / Style / Budget / Attachment は文書が勝つ）。
  Texture Prompt では色・素材の区切りに焦点を当てた文面へ切り替える。
  登録済み Reference には `view: "full_body"` を用意し、Production Panel の既定値にしてある。
- **Grip Orientation**: `GRIP_ORIENTATION_DEGREES`（main_hand `[-180, 0, 90]` /
  off_hand `[0, 0, 90]`、Blockbench ZYX degrees）。Source が `onehand_sword` /
  `gread_sword` / `spear` に与えている回転そのままで、Prompt が要求する「刃は local +Y」で
  作られた Asset を刃が前方（+X）を向く姿勢にする。Grip 取り付けの Asset にのみ適用し、
  位置・スケールは触らない。
- **Coverage / 目標サイズ**（`TYPE_COVERAGE` in `base-measurements.ts`）: Fit Region の
  Bounding Box に対して Asset がどれだけ大きいべきかの倍率。既定 1.0 だが、体の上に**被せる**
  装備は部位と同寸だと小さく見える。Shoulder は **1.5**（0.2084 → 0.3126 m）。
  Prompt の PROPORTION / GEOMETRY に実寸 m で出し、Validation の longestAxis レンジも
  これに合わせて `[0.12, 0.24]`（= 0.2214 - 0.4429 m）に絞ってあるので、素の肩と同寸の成果物は
  `scale_too_small` で検出される。値を変えるときは実際の生成物を根拠にすること。
- **Geometry budget**: profile（low / medium / high）と、その裏の作業値
  （low 400/1200 tris・medium 1200/3000・high 3000/6000、max material 2/3/4）。
  Prompt が名乗るのは profile 名、Validation が測るのは数値で、後から数値だけ調整できる。

## 5. Import Pipeline

```
Job Detail → Model(.glb) / Texture(.png) / Source(.bbmodel) を選択
   → PUT /api/library/production/<id>/file/incoming/<name>
   → 新しい Revision を open（Asset ID は Job 固定。ユーザーは再入力しない — spec section 38）
   → 即 Validation（spec section 39）
   → verdict fail なら status=validation_error、それ以外は imported
```

- ファイル名は `model_r<n>.glb` / `texture_r<n>.png` / `source_r<n>.bbmodel` に正規化。
- `.bbmodel` はブラウザで解析しない。Source として保持し、Preview は GLB を使う（spec section 37）。
- Staging は `library-data/asset-production/<assetId>/{incoming,approved,rejected,reference}/`
  （spec section 36）。Approve / Reject で `incoming → approved / rejected` へ移動する。
- 拡張子ホワイトリスト・ファイル名パターン・stage 名を route handler 側で検証し、
  path traversal は 500 で弾く（実際に `../evil.png` / `evil.exe` / 未知 stage で確認済み）。

## 6. Validation Pipeline

`domain/production-validation.ts` が **Package に同梱した `validation-spec.json` と同じ契約**で判定する。

| Check | 判定 |
| --- | --- |
| Model readable | GLB が読めない / Mesh 無し → **Error** |
| Texture readable | 未 Import → Warning |
| Bounding Box | 0 / NaN 軸 → **Error** |
| Scale | 想定レンジ外 → Warning、`errorMargin`(1.5倍) を超えたら **Error** |
| Origin / Pivot | 中心が原点から離れすぎ → Warning |
| Polygon Count | Budget 超過 → Warning |
| Material Count | 上限超過 → Warning |
| UV | UV 無し Mesh あり → **Error** |
| Grip Point | 必要な `grip_main` / `grip_sub` が無い → **Error** |
| Clipping Check | clearance 領域と Bounding Box が重なる → Warning（section 44: BBox 判定まで） |
| Texture Resolution | 仕様と不一致 → **Error**、非正方形 → Warning |
| Transparency | alpha policy 違反 → Warning |
| Palette Slots | 未宣言 → Warning、Hair に `hair` slot 無し → **Error** |
| Socket | 未定義 socket → **Error** |
| BodyType | 未指定 → **Error** |
| Animation compatibility | base が再生できない Animation Set → Warning / 個別 clip 欠落 → Info |
| Source | `.bbmodel` が無い → Warning（promptVersion 2 で必須成果物になったため） |

Score（spec section 40）は `100 − (Error×25 + Warning×8)`。**Score だけで登録可否を決めない**:
Error が 1 つでもあれば verdict は `fail` で、UI 側も Approve ボタンを無効化する。

Clipping は socket の実測 world position に Asset の BBox を置いて、clearance 領域の
world BBox と交差体積を取る簡易判定。Mesh Collision までは行わない。

## 7. Revision Prompt 生成方式

`domain/production-revision.ts` が **Validation の issue code → Issue / Revision の対**に変換する
（spec section 46-47）。対応コード:

```
scale_too_large / scale_too_small / origin_offset / grip_missing / socket_unknown /
polygon_over_budget / material_over_budget / uv_missing / texture_wrong_size /
texture_not_square / texture_missing / alpha_not_allowed / alpha_required /
palette_slot_missing / palette_missing / possible_clipping / bounding_box_invalid /
model_unreadable / animation_unavailable / bodytype_missing / source_missing
```

出力例（実測値から自動生成）:

```
Issue:
The asset is approximately 1.80x too large (longest axis 1.9265 m, expected at most 1.0703 m).

Revision:
Reduce the overall dimensions to fit within 0.7751 - 1.0703 m on the longest axis,
while preserving the grip_main position relative to the mesh.
```

末尾に「変えてはいけないもの」（identity / silhouette 方向 / palette slot 構成 / socket 契約 /
出力形式 / base を変更しない）を必ず付ける。未知コードは Validation メッセージにフォールバックする。

## 8. Revision History 構造

`ProductionJob.revisions[]`。1 Import = 1 Revision。

```jsonc
{
  "revision": 3,
  "createdAt": "...",
  "stage": "approved",                       // incoming | approved | rejected
  "files": { "model": "model_r3.glb", "texture": "texture_r3.png", "source": "source_r3.bbmodel" },
  "validation": { "verdict": "warning", "score": 92, "checkedAt": "...", "issues": [...] },
  "decision": "approved",                    // approved | rejected | needs_revision | null
  "decidedAt": "...",
  "revisionPrompt": "# Revision Prompt — ...",
  "note": "",
  "promptVersion": 1
}
```

Job Detail の Revision History 表から過去 Revision を選ぶと、その Validation 結果・Preview・
Revision Prompt をそのまま再表示できる（`Revision 1 Fail / Revision 2 Warning / Revision 3 Approved`）。

## 9. Production Queue 構造

`/production` は左に Queue、右に Job Detail。

- Filter（spec section 55）: `All / Draft / Prompt Ready / Generated / Needs Revision /
  Approved / Rejected`。内部 status をバケットに写像する（`generated` は
  generated / imported / validation_error をまとめる）。
- 検索: id / name / type / tag。
- Batch Export: チェックした Job の Package を 1 ZIP で出力（spec section 56）。
- Status（spec section 3）:
  `draft → prompt_ready → generating → generated → imported → validation_error →
   needs_revision → ready → rejected → registered`。
  AI と直接通信しなくても `prompt_ready / generating / generated / imported` は
  Job Detail のセレクトから手動で進められる。
- **バックグラウンド AI 実行はしない**。Queue は制作状態管理用（spec section 54）。

## 10. Asset Library との統合

Approve（spec section 45, 52）:

1. Revision の files を `incoming/ → approved/` へ移動
2. `draftToAssetJson()` で AssetMetadata を作り、`tags` と `production` を付与
3. Phase 7 の `saveAsset()` を**そのまま再利用**して `library-data/assets/<id>/` に
   `index.json` / `model.glb` / `texture.png` を書く（既存 id なら assetVersion を +1、
   versionHistory に `AI production revision n` を記録）
4. Job status を `registered` に更新

`AssetMetadata.production`（spec section 49）:

```json
{ "method": "ai_assisted", "revision": 3, "status": "approved", "promptVersion": 1, "producedAt": "..." }
```

AI Provider 名は持たない。Approve していない Revision は Library に入らない。

Character Builder は `useMergedLibrary()` が filesystem library を合流させるため、
Approve 直後から装備 Picker に出る（spec section 52）。

## 11. Variation Generator との統合

Phase 8 の候補プールは `CandidateAsset.tags`（= `AssetRecord.tags`）を見る。Approve 時に
Job の Tag を metadata と record の両方へマージするので、Tag を設定した Approved Asset は
**Preset 側を触らずに**そのまま Variation の候補へ入る（spec section 53）。
Tag は Asset Creator の AI Production パネルで登録する。

## 12. 将来の AI Adapter / Security

`domain/production-provider.ts` に `AIProductionProvider`（`generateModel` / `generateTexture` /
`reviseModel`）と `ProductionRequest` / `ProductionResult` を**型だけ**定義した（spec section 58）。
実装は無く、`PRODUCTION_PROVIDERS` は空配列。UI は Provider が 1 つも無い前提で完結している。

API Key はブラウザバンドルに一切入れない（spec section 59）。将来 Provider を足す場合も
Library API と同じくサーバー側 route から環境変数を読む前提にしてある。

## 13. 変更 / 追加ファイル

追加（domain）: `base-measurements.ts` / `production-status.ts` / `production-profile.ts` /
`production-job.ts` / `production-package.ts` / `production-validation.ts` /
`production-revision.ts` / `production-provider.ts`

追加（prompt）: `templates/types.ts` / `templates/common.ts` / `templates/hair.ts` /
`templates/headgear.ts` / `templates/armor.ts` / `templates/shoulder.ts` /
`templates/weapon.ts` / `templates/shield.ts` / `templates/back.ts` / `templates/index.ts`

追加（features/production）: `mutations.ts` / `package-export.ts` / `production-panel.tsx` /
`production-screen.tsx` / `job-detail.tsx`

追加（app / scripts / generated）: `app/production/page.tsx` / `scripts/build-measurements.mjs` /
`scripts/verify-production.mjs` / `public/generated-assets/base_body/measurements.json` /
`docs/phase-9.md`

変更: `prompt/promptTypes.ts`・`promptBuilder.ts`・`modelPromptTemplate.ts`・
`texturePromptTemplate.ts`（テンプレート分割と Phase 9 コンテキスト）/ `domain/asset.ts`
（`production?`）/ `domain/asset-validation.ts`＋`features/asset-creator/inspect.ts`（UV 統計）/
`domain/library-index.ts`（`productions`）/ `app/api/library/[[...path]]/route.ts`＋
`features/library/server/store.ts`（production 永続化）/ `features/library/api.ts`（client）/
`features/library/derive.ts`＋`dashboard-screen.tsx`（カウント）/
`features/asset-creator/creator-screen.tsx`（パネル設置）/ `app/layout.tsx`（nav）/
`app/globals.css` / `package.json` / `scripts/ts-resolve-hook.mjs`（JSON / index 解決）/
`library-data/README.md` / `README.md`

`assets/characters/base/base_1.bbmodel`、既存 GLB、Godot 側、Rig、Animation は未変更。

## 14. 現在の制約

- **実ブラウザでの目視サインオフ未実施**。`typecheck` / `lint` / `next build` /
  `verify:production`（75 チェック）は PASS、`/production` `/creator` の HTTP 200 と
  production API の PUT / GET / move / DELETE・traversal 拒否はローカル dev サーバで確認済み。
  3D Preview・Animation Test・Approve の一連操作の目視確認は未実施。
- Geometry Budget の数値は暫定。実 Asset が溜まってから再調整する前提（profile 名が契約）。
- Size レンジ（`TYPE_LONGEST_AXIS_RATIO`）も character height 比の暫定値。
- Socket は Phase 2 のまま `pivot_only_uncalibrated`。Prompt / Spec にもその旨を明記しており、
  「校正済み grip pose」としては渡していない。
- Clipping は Bounding Box 交差のみ。Mesh Collision・アニメーション中の衝突は見ない。
- Animation Test は clip 解決の静的チェックと Preview 再生まで。自動的な破綻検出はしない。
- base_1 の default Animation Set に `idle` clip が無いため、非武器 Asset の idle テストは
  Info（Base 側の制約）として報告する。Asset の修正対象にはしない。
- Reference 画像は Package に同梱するだけ。AI への自動送信はしない。
- Thumbnail は Approve 時に生成しない（Asset Creator の Capture Thumbnail は従来どおり）。
  Prompt では AI に thumbnail.png を作らせない方針を明示している。
- `.bbmodel` の中身は検証しない。存在の有無だけを見るため、`.glb` と実際に一致しているかは
  人の目視確認が必要。
- Production Job は 1 Asset ID = 1 Job。同じ Asset を並行して別ラインで作る運用は想定外。
- 複数ユーザー同時編集は非対応（Phase 7 から変わらず）。

## 15. Phase 10 へ残した課題

spec section 60 のとおり、特定 AI API への完全自動送信 / AI 生成ジョブのバックグラウンド実行 /
Blender・Blockbench の自動操作 / 自動 Approve / AI による完全自動 Character 生成 /
Game Stats 生成 / NPC 名前生成 / Map 自動配置 / Runtime AI 生成 / Cloud Asset Storage /
Multi-user Workflow は対象外のまま。加えて本 Phase で見えた宿題:

- Geometry Budget / Size レンジの実測ベースでの数値確定
- Socket の校正（`pivot_only_uncalibrated` の解消）と、それに伴う grip 位置の Validation 強化
- Mesh レベルの Clipping 判定とアニメーション中の衝突チェック
- base_1 への `default.idle` clip 追加（Base 側の課題）
- `.bbmodel` のブラウザ内解析（現状は Source として保持のみ）
- Approve 時の Thumbnail 自動生成
- Prompt Template のバージョン差分ビューアと、旧 promptVersion Asset の一括再生成
- Reference 画像を実際に扱える Provider Adapter の実装（型は用意済み）
