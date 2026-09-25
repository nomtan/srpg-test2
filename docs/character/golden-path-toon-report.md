# Golden Path Toon Shader 統合レポート

2026-09-26。Godot 4.6.1 で Golden Path 001 / 002 を再 import し、`BattleUnit.setup_visual()` 経由で検証した。

## 変更ファイル

- `assets/characters/_shared/materials/character_toon.gdshader`：両キャラクター共通の Shader。
- `tools/asset_gen/character_pipeline/golden_path_import.gd`：各 Mesh の全 surface に ShaderMaterial を生成。
- `tools/asset_gen/character_pipeline/verify_golden_path.gd`：Shader、texture、既存の skeleton / animation 契約を検証。
- `artifacts/golden_path/toon_{idle,walk,attack,hit}.png`：Godot 描画証跡。
- 本レポート。

## Shader 仕様と import

従来の `tripo_roster/toon.gdshader` と同じ3段階（light / middle / shadow）を初期値 `middle_band=0.84`、`shadow_band=0.68` で実装した。`base_color_texture` をそのままサンプリングし、`METALLIC=0`、`ROUGHNESS=1`、`SPECULAR=0` とした。Shader resource は共有し、ShaderMaterial は surface ごとに別インスタンスとして保持する。将来の Head 表情 texture と Body palette の個別設定を妨げない。

import 時に Body と Head（Face 002 の一体化した髪を含む）の全 surface を走査し、元の BaseMaterial3D の albedo texture を新しい ShaderMaterial の `base_color_texture` に渡す。texture がない場合は import error とする。GLB、Blender material、UV、texture 画像の加工はしていない。outline mesh は増やしていない。

## 検証結果

| 項目 | 001 | 002 |
|---|---|---|
| Body / Head の ShaderMaterial と共有 Shader | PASS | PASS |
| 全 surface の Base Color texture | PASS | PASS |
| Skeleton3D 1個、65 bones、`head` bone | PASS | PASS |
| Body / Head の共通 Skeleton bind | PASS | PASS |
| idle / walk / attack / hit 再生、idle / walk loop | PASS | PASS |
| `BattleUnit.setup_visual()` と自動 idle | PASS | PASS |
| 001 の animation resource を 002 へ適用した bone pose 一致 | 対照 | PASS |

Godot 検証スクリプトの最終結果は `GOLDEN_PATH_VALIDATION: PASSED`。正面寄りの通常 SRPG カメラ距離で2体を同時描画し、4 clip の画像を保存した。Body / Head 間に目立つ照明差はなく、Face 002 の髪にも同じ toon 表示が適用されている。元の Tripo texture の色は保たれ、金属的な反射は見られない。旧 Tripo Toon と同じ lighting 計算と初期値を用いたため、同系統のセルルックとなる。

画像：`artifacts/golden_path/toon_idle.png`、`toon_walk.png`、`toon_attack.png`、`toon_hit.png`。戦闘距離の全景は `godot_battle_distance.png`。

source GLB 3点の SHA-256 は `assets/characters/generated/golden_path_001/source_hashes.json` の作業前記録と一致した。Body 001 は `e40ece9d…b16f8fd`、Face 001 は `fdf20014…2734e`、Face 002 は `5a882814…9b244`。生成済み `character.glb` も変更していない。

## 残件と Face Controller への引き継ぎ

Face Controller、表情 texture、palette、emblem、damage flash、selection emission、outline は今回の範囲外。次回は Head の ShaderMaterial を runtime で取得し、そのインスタンスへ `expression_texture` と有効フラグを設定する。Head と Body の ShaderMaterial はすでに分離しており、共有 Shader 側に必要な uniform を追加できる。

Godot editor 起動時には既存の `addons/godot_mcp` のクラス重複エラーと editor 設定保存エラーが表示された。GLB の再 import と standalone 検証、描画は完了した。
