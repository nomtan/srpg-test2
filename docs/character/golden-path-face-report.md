# Golden Path Face Controller 実装記録

## 実装

- `scripts/character/face_controller.gd`: Head の各 surface material を個体ごとに複製し、`set_expression`、`reset_expression`、`blink` を提供。表情テクスチャを初回にキャッシュし、欠落時は normal、normal もない場合は元のHead textureへ戻す。
- `scripts/unit/battle_unit.gd`: Golden Path GLB を生成した直後に Controller を bind。manifest の初期表情と `face_surface` のUV補正を読む。
- `assets/characters/_shared/materials/character_toon.gdshader`: alpha付き表情PNGをbase colorへ合成した後、従来の3段階toon照明を適用。depth設定は変更しない。
- `assets/characters/_shared/face/face_{001,002}/`: 各4種類、512×512 RGBAの技術検証用PNG。正式な表情アートではない。
- `tools/asset_gen/character_pipeline/`: UV調査、PNG生成、Controller検証のスクリプトを追加。

## UVと表情

両Faceのsource albedoは512×512。`inspect_face_uv.py`で正面からメッシュへrayを投げ、eye、eyebrow、mouthの候補UVを求めた。配置点は `artifacts/golden_path/face_001_uv_guide.png` と `face_002_uv_guide.png` に記録した。TripoのUVは正面顔の単一連続領域ではなく複数islandに分かれる。特にFace 002は前髪を含む単一Head meshで、眉の候補が髪のUVに当たる可能性がある。PNGは切り替え経路とUV調査用の仮マークであり、画面上の完成した顔表現としては未確認。

## Golden Path契約

GLB、Body/Head geometry、fit、skin、65 bone skeleton、animation bufferには変更を加えていない。Face 001は髪なし、Face 002は髪をHeadに統合した既存構造。表情はHead material上で合成するため、髪のdepth判定を迂回しない。manifestの既存 `face` は維持し、両方にidentityの `face_surface` UV補正を追加した。

## 検証結果

- source GLB 3件のSHA-256は既存 `source_hashes.json` と一致。
- Blenderで両Face GLBのmeshとUVを読み、UVガイドを生成。
- Godot 4.6.1 headless editorで新規PNGのimportは完了。ただし既存の `addons/godot_mcp` に重複したglobal classのparse errorがあり、独立したheadless runtime検証はログ初期化時に停止した。`verify_face_controller.gd` の成功、および描画証跡は未取得。

## 未解決・次フェーズ

1. Godot実行環境の既存MCP plugin parse errorとログ出力権限を解消し、`verify_face_controller.gd`を実行する。
2. Face 001/002を同時に描画し、4表情、blink、前髪遮蔽、idle/walk/attack/hitとの併用を撮影する。指定された `artifacts/golden_path/face/{normal,closed,surprised,squint,blink,fringe_occlusion}.png` は未作成。
3. 正式Face Artでは各UV islandと実際の顔表面の対応を手作業で確認し、検証用PNGを差し替える。Face間のUV共通化は今回判断しない。
