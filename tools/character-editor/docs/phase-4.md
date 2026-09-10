# Phase 4: Asset Creator

新規 Asset（Hair / Armor / Shoulder / Weapon など）をブラウザ上で定義・Preview・
Validation し、AI Agent 向けの制作 Prompt を生成する。基準 Base Body は
`assets/characters/base/base_1.bbmodel`。既存 Source / Rig / Animation は変更していない。

## 画面

- `/creator` … Asset Creator（`src/features/asset-creator/`）
- `/` … Character Builder。Asset Creator で保存した Asset が Asset Library に合流する。

## Base GLB へのアニメーション bake（Phase 4 の差分）

`scripts/build-base-model.mjs` が、Source の 17 clip を **プレビュー専用**の
node TRS チャンネルとして `public/generated-assets/base_body/model.glb` へ焼き込む。

- Source（`.bbmodel`）、geometry、hierarchy、Rest Pose は不変。SHA-256 も不変。
- 回転は Blockbench の加算 Euler モデル（rest + keyframe、ZYX）。非線形補間は linear 近似。
- clip 名は Source のまま（`animation.onehand_sword_attack` 等）。
  `src/viewer/animation/animationMapping.ts` がそのまま解決する（Phase 3 の仕組みを再利用）。
- `scripts/verify-base-model.mjs` の Phase 2 ガード（animations === 0）を、
  「bake clip は Source clip の部分集合」「対象ノードは既存 Group のみ」へ更新。
  Explorer との Rest 形状・Scale・向きの数値一致（1e-6 m）は従来どおり検証。

## Asset 保存

`localStorage`（`src/features/asset-library/user-assets.ts`）に metadata + data URL で保存し、
`useMergedLibrary()` が静的 Library（base + demo）へ合流させる。リポジトリへは書かない。
併せて `asset.json` 単体 DL と store-only zip（`asset.json` / `model.glb` / `texture.png` /
`thumbnail.png`）を出力できる。

Asset ディレクトリ規約（出力先の目安、書き込みはしない）:

```
assets/character-assets/<category>/<id>/
  source/<id>.bbmodel
  model.glb  texture.png  thumbnail.png  asset.json
```

## 制約 / Phase 5 以降

- パリティゲート（`comparison.json`）の「実画面 目視確認」「equipmentAssemblyAllowed:false」は
  未解決のまま。Phase 4 はユーザー指示により Base + Asset Preview を先行実装している。
- Socket は既存 Group Pivot に取り付けるだけ（校正なし）。IK なし、Grip は位置整合の目視まで。
- hideParts は Body Part の mesh 名一致で非表示（左右同名パーツは同時に隠れる）。
- AI API 送信 / 3D・Texture 自動生成 / Blockbench・Blender 操作 / Godot Export /
  Character GLB Bake / Physics / Runtime Modular は Phase 5 以降。
