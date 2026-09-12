# Character Workshop — Phase 9 AI Production Pipeline

正式素体は `assets/characters/base/base_1.bbmodel` です。Builder/Creatorで初期表示するGLBは
このSourceから生成しています。仮のBase Bodyは一覧から除外しました。

Phase 7 で Asset / Character の一覧・検索・複製・バージョン管理・依存追跡・一括Validation・
Stale検出・Batch Export・Registry Sync を行う管理レイヤーを追加しました
（`/dashboard` `/assets` `/characters` `/validation`）。永続化は Next Route Handler 経由の
`tools/character-editor/library-data/`。詳細は [Phase 7](./docs/phase-7.md) を参照してください。
Phase 8 で Character Variation Generator（`/variations`）を追加しました。Variation Preset /
Asset Tag / Weighted Random / Asset Compatibility / Deterministic Seed で Character Recipe を
一括生成し、Preview・単体Reroll・項目Lock・完全一致Duplicate検出を経て Character Library へ
登録します。生成時に GLB は作らず、Export は従来どおり Character Library の Batch Export です。
詳細は [Phase 8](./docs/phase-8.md) を参照してください。
Phase 9 で AI Production Pipeline（`/production` と Asset Creator の AI Production パネル）を
追加しました。Asset 定義から Provider 非依存の Production Package
（`asset-definition.json` / `model-prompt.md` / `texture-prompt.md` / `technical-spec.md` /
`validation-spec.json` / `README.md`）を生成し、外部 AI が作った `.bbmodel` / `.glb` / `.png` を
Import して自動 Validation・Base + Asset Preview・Animation Test・Revision Prompt 生成・
Revision History・Approve / Reject / Needs Revision まで行います。Approve した Asset だけが
Asset Library に登録され、Character Builder と Variation Generator から使えます。
Prompt には base_1 から実測した寸法（head / hand / socket / 推奨武器全長）が入り、成果物は
`<id>/source/<id>.bbmodel` + `model.glb` + `texture.png` + `asset.json` の固定フォルダ構造で
返させます（`.bbmodel` は必須成果物）。
詳細は [Phase 9](./docs/phase-9.md) を参照してください。
解析結果・再生成・ゲームとの未解決の差分は [Phase 2](./docs/phase-2.md) と
[解析一覧](./docs/base-model-analysis.md) を参照してください。
Asset Creator（`/creator`）の定義・Preview・Validation・Prompt生成・保存は
[Phase 4](./docs/phase-4.md) を参照してください。
Character Builder（`/`）は装備13スロット + Body Scale + Palette + Animation + Recipe save/load を
持つ合成ツールで、**Export for Godot** で `<id>.glb` + `<id>.png` + `<id>.character.json` を ZIP 出力します。
Bake方式・Palette Bake・Scale変換・Round-trip・Test Scene は [Phase 5](./docs/phase-5.md)、
Godot側の取り込み手順は [Godot Import Guide](./docs/godot-import-guide.md) を参照してください。
`npm run verify:export` で Base GLB / Scale / Animation Mapping の headless チェックが走ります。
以下のPhase 1説明は初期基盤の説明で、素体・Libraryの現在の扱いはPhase 2/4/5を優先します。

既存 `nomtan/srpg-test2` 内で独立して動く Next.js / TypeScript / Three.js ツール。
基準は [character-asset-tool-spec-v1.md](./character-asset-tool-spec-v1.md)。
Godot のシーン・スクリプト・アセットには依存せず、`.gdignore` でツール全体をGodotのインポートから除外する。

## 起動

Node.js 22.18以上（変換スクリプトのTypeScript読込に必要、開発確認は24系）。Windows PowerShellでは実行ポリシーに影響されない `npm.cmd` を使用できる。

```powershell
cd tools/character-editor
npm.cmd ci
npm.cmd run build:base
npm.cmd run verify:base
npm.cmd run dev
```

http://127.0.0.1:3000/ がCharacter Builder、`/creator` がAsset Creator、`/variations` が Variation Generator、
`/production` が AI Production Queue。
同ポート使用中なら `npm.cmd run dev -- --port 3100`。

```powershell
npm.cmd run typecheck
npm.cmd run lint
npm.cmd run build
npm.cmd run generate:demo
npm.cmd run verify:variation
npm.cmd run build:measurements
npm.cmd run verify:production
```

`verify:variation` は Phase 8 生成ロジック（決定性 / Weight / Compatibility / Two-Hand /
Duplicate / Lock 付き Reroll / 生成不可能 Preset の事前検出）を合成 Asset Library に対して
headless で検証します。

`build:measurements` は `analysis.json` を再走査して
`public/generated-assets/base_body/measurements.json`（head / hand / socket などの実測寸法）を
生成します。Phase 2 の three.js 製 bounds と 1e-6 以内で一致することを自己検証してから書き出し、
Source には一切書き込みません。`verify:production` は Phase 9 の Package 構成・Asset Type 別
Prompt・Validation 判定（Scale / Grip / Texture / Palette / UV）・Revision Prompt 生成を
headless で検証します（79 チェック）。左右の取り違え（キャラクターの左は -Z）に対する
回帰チェックもここに含まれます。

## 構成と実装範囲

- `src/app/`: App Routerのページと共通レイアウト。
- `src/domain/`: フレームワーク非依存のMetadata／Recipe型と仕様定数。
- `src/features/asset-library/`: ID索引、カテゴリ／BodyType絞り込み、仮データ。
- `src/features/character-builder/`: 一覧選択、単体Preview、Metadata表示。
- `src/features/asset-creator/`: 定義入力のレイアウトと仮GLB Preview。入力は保存・反映しない。
- `src/features/production/`: Phase 9 の AI Production（Package 生成 / Queue / Import / Validation / Approve）。
- `src/prompt/templates/`: Asset Type 別 Prompt Template（共通 + hair / headgear / armor / shoulder / weapon / shield / back）。
- `src/components/preview/`: GLTFLoader、OrbitControls、Grid、読込状態、視点リセット、リサイズ、破棄処理。
- `public/demo-assets/`: 自作の素体・剣・盾のGLB。`scripts/generate-demo-assets.mjs` から再生成可能。

仮GLBは未Rigging・単色Materialの動作確認用。製品用素体、Texture、Skeleton、正規化規格のサンプルではない。
Previewはモデルを変形せず、Bounding Boxからカメラを合わせる。
Libraryはメモリ上の静的データ。永続保存・Import・合成・装備操作は実装しない。

## データ設計上の補足

- `as const`配列とliteral unionでJSON値・選択肢を共有。カテゴリ、装備スロット、Recipeスロットは別概念として定義。
- Metadataの`model`等はアセットディレクトリ相対。Libraryの`baseUrl`でブラウザ公開先を別管理。
- `source`は任意の`.bbmodel`参照。ブラウザで読込／編集／変換しない。Runtimeは`.glb`。
- Texture単体カテゴリを表現するため`model`は任意。Texture／Thumbnail未作成も許容。
- `equipment.weaponType`、`source`、Recipeの`body.assetId`は拡張用の任意項目。
- Recipeは仕様15章のJSONキーを維持し、省略可能な装備はPartial、未装備はnull。左右肩は独立。
- 仕様24章と15章の例の差に合わせRecipeの`assetVersion`は任意、Metadataは必須。`specVersion`は1固定。
- `hideParts`とAssetの取り付け点は既存モデルの命名移行が未確定なので文字列。複雑なValidationは行わない。
- Body Presetの数値、BlockbenchのNormalization Scaleは未確定。定数名と型のみ定義し変換は行わない。

## 段階的な実装計画

1. **今回**: 型・定数、Library基盤、両画面レイアウト、仮GLBの選択・回転・ズーム。
2. Import／Metadata編集／Library・Recipe保存の設計と実装。
3. Baseと装備の合成、Socket・Grip対応、Body Scale、基本Validation。
4. Animation統合、Palette、Godot Export。

後続フェーズは別途着手。AI Agent連携、高度なPrompt生成、Blockbench編集は今回の対象外。

## 手動確認

実装時にTypeScript、ESLint、本番ビルド、両ページのHTTP 200、全仮GLBの
GLTFLoader解析・Bounding Box・HTTP配信を確認済み。
接続可能なブラウザがないため、以下の目視・操作確認は未実施。

1. Builderで素体・剣・盾を選択し、見た目と詳細が切り替わること。
2. カテゴリをWeaponにすると剣のみ、Hairにすると空状態になること。
3. ドラッグ回転、ホイール／ピンチでズーム、視点リセットを確認。
4. Creatorへ移動して仮アセットを切り替え、画面幅を縮めても操作できること。
5. GLBのリクエストをブラウザ開発者ツールでブロックして再読込するとエラー表示になること。
