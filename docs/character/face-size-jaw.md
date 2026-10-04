# Faceサイズ基準：顎幅（jaw_width_chin_plus_4cm_v1）

[Face007基準のサイズ統一](face-size007.md)（Head+Hair全体の横幅0.419525mに揃える方式）を置き換える。

## 旧方式の問題

全体幅には髪のボリュームが含まれる。001〜006は髪が横に張り出しているのに対し、
007はポニーテールで髪が頭に沿っているため、同じ全体幅でも007の頭部（顔・頭蓋）が大きかった
（高さ0.510 / 奥行0.527 vs 他 約0.41 / 0.42）。

## 基準

- 指標: **顎幅** = 正面平行投影（flat albedo）で、顎先から4cm上の高さにおける顔の肌の連続幅。
  髪の影響をほぼ受けない。顎先は中心線を下から走査し、6cm以上肌が途切れない最初の点（顎の下に垂れた髪束を除外）。
- 目標値: **0.2035m**（調整前の001・002・003・005・006の中央値。全体の見た目を保つため）。
- `character_asset_standard_v1.json` の `face_size`（metric / jaw_width_m / tolerance_m 1mm / exceptions）。
- 例外: **Face004**（閉じた兜で顎が見えない）は旧方式の幅0.419525mを維持する。
- 等方スケールのみ。高さ・奥行・髪型差は保持し、pivotは既存の `position`（首の接続位置）のまま。

## 測定値と結果

| Face | 調整前の顎幅 | 倍率 | 新scale | 全体幅 |
|---|---:|---:|---:|---:|
| 001 | .2050 | .9927 | .4346 | .4165 |
| 002 | .2050 | .9927 | .4317 | .4165 |
| 003 | .2035 | 1.0000 | .5112 | .4195 |
| 005 | .1968 | 1.0343 | .4443 | .4339 |
| 006 | .1910 | 1.0654 | .4604 | .4470 |
| 007 | .2203 | .9240 | .4989 | .3876 |

再測定では全Faceが目標の ±1.5mm（画素量子化）以内。全体幅の範囲は髪型差を許容するよう
`face_head_space.width` を recommended .38〜.46 / hard .35〜.50 に変更した。

## データと再生成

- `normalization.json` の `head_metrics`（`jaw_width_source` = 原本単位の顎幅、`chin_height_source`）。
  scaleに依存しない原本単位で記録し、resizeはこの記録値だけを使う（実行時・ビルド時に推定しない）。
- `size_baseline` は最初のサイズ統一前のscale／position。007は `profile_origin` に既定の表情投影を作った位置を持つ。
- 表情profileは名前を変えずに `legacy_size007_NNN.tres` を同じ変換で更新した。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/measure_face_jaw.py -- --ids 001,002,003,005,006,007 --write
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/resize_faces_by_jaw.py
python tools/asset_gen/character_pipeline/validate_modular_parts.py
```

`--write` なしの `measure_face_jaw.py` は確認用で、`artifacts/face_size_jaw/front_NNN_jaw.png`（赤＝測定線、青＝顎先）を出力する。
新規Faceも同じ手順で測定値を記録してからresizeする。

検証: `validate_modular_parts.py` 0 FAIL、`verify_modular_parts.gd` PASSED、
`capture_character007.gd` → `artifacts/character007/lineup_{front,side}.png`。
