# Face Expression Rendering v2

## Contract

Face は Head + Hair を含む1 GLB / 1 Face ID。Skeleton、Skin、Animation は0。
CharacterDefinition と ExpressionController の既存 API、3つの共有 atlas は維持する。
同一 mesh の複数 surface と、複数 mesh の構造を runtime は扱える。

| 用途 | Blender | glTF | Godot |
|---|---|---|---|
| Base color | 第1 UV layer | TEXCOORD_0 | UV / ARRAY_TEX_UV |
| Expression | 第2 layer `ExpressionUV` | TEXCOORD_1 | UV2 / ARRAY_TEX_UV2 |
| 前面マスク | active `ExpressionMask` のR | COLOR_0.r | COLOR.r / ARRAY_COLOR |

Blender 5.1.2 → GLB → Godot 4.6.1 Compatibility の fixture で実測確認済み。
Exporter は `export_vertex_color="NAME"`, `export_vertex_color_name="ExpressionMask"`,
`export_all_vertex_colors=False` を使う。既定の MATERIAL + all-colors は白い
COLOR_0 とマスク COLOR_1 を作る場合があるため禁止。
UVMap の名前は GLB で保証されない。作業用GLBの再importでは第2 UVとactive colorを正式名へ戻す。

Head* のみに atlas と `expression_uv_v2=true` を設定する。Hair* は
`expression_parts_enabled=false`、atlas未設定。v2 Head は UV2 の0..1と
COLOR.r > 0.5で描画し、3D position / normal / profile depthを参照しない。
同じ toon shader 内で合成し、通常のdepth testによってHairがHeadの表情を遮る。
COLORはbase colorへ乗算しない。マスクは色ではなく許可属性として使う。

ExpressionUV は顔正面の共有座標。上が0、下が1、左が0、右が1。
Blender authoring のUV表示では上下が反転し、上がV=1になる。
基準線は共有atlasの図柄に揃える：眼中心は概ね (0.31/0.69, 0.40)、眉は
V=0.24、口はV=0.72。実際のatlas図柄を最終基準とする。
顔幅・高さ・中心・眼／眉／口ラインをartistが明示し、顔形状の違いをauthoringで吸収する。
耳・後頭部・首はR=0。正面はR=1。境界の補間を考慮してfeature領域に余裕を持たせる。
Hair側にmaskは不要。色・位置・法線からHead/Hairを自動推測しない。

## Legacy and sharing

Head/Hair分離、またはHeadのUV2をv2構造マーカーとして使う。
旧001〜006はHead名の単一combined材質もあるため、Head名だけではv2にしない。
分離されたassetにunknown材質、Head/Hair不足、HeadのUV2／COLOR不足があればbindを拒否する。
Legacy は従来のrest projection、depth、normalとExpressionProfileを維持する。
Assembler の既存face004 helmet互換方針は維持し、新規ID分岐は追加していない。

Head表情材質は個体ごとにduplicate、Hair材質・Mesh・base texture・shader・atlasは共有。
shaderは分割しない。instance uniformはGodotの候補APIとして調査したが、
実キャラクター60体で改善を実測できていないため、今回置き換えない。
ExpressionProfileのlegacy fieldsは削除せず、v2では無視する。

## Normalizer and validation

新規metadataは `expression_rendering: "uv_v2"` を宣言する。
未分類原本は不変のまま、別のworking GLBを明示authoringする。
metadataには原本の `source_sha256` とworking GLBの `authored_sha256` を記録する。
正規化scale/positionはworking GLBの座標に対して測定する。

```powershell
blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind face --id 007 --authored-face artifacts/face007-authored.glb --output-root artifacts/modular_staging
python tools/asset_gen/character_pipeline/validate_modular_parts.py --root artifacts/modular_staging --json-output artifacts/modular_staging/validation.json
```

NormalizerはUV0を保持し、既存の明示UV/maskを検証して出力する。自動landmark推定はしない。
複数meshにも対応。ValidatorはHead/Hair分類、HeadのUV0/UV1/COLOR_0、頂点数一致、
0..1、NaN/Inf、許可領域の退化UV三角形、許可／禁止mask領域を検査する。
Hairにmaskを要求しない。新規legacyはFAIL、旧combinedはWARNING。
maskが実際の顔正面と一致するかはartistによるcamera reviewが必要。

## Reproducible checks

```powershell
blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_expression_v2_fixture.py
python tools/asset_gen/character_pipeline/test_expression_v2_validator.py
godot --headless --path . --log-file artifacts/phase5_v2_engine.log --script tools/asset_gen/character_pipeline/verify_expression_v2.gd
godot --path . --log-file artifacts/phase5_capture_engine.log --script tools/asset_gen/character_pipeline/capture_expression_v2.gd
python tools/asset_gen/character_pipeline/check_expression_v2_captures.py
godot --headless --path . --log-file artifacts/phase5_legacy_verify.log --script tools/asset_gen/character_pipeline/verify_modular_parts.gd
```

fixtureは矩形Headと左眼／眉を覆う矩形Hair。**Tripo Face007ではない**。
5 preset × front / front-left / front-rightの15画像を
`artifacts/phase5_fixture_captures/` に出力する。
正式Face007配置後はcaptureに `-- --face007` を付ける。

2026-10-03検証結果：

- Legacy 6 Body × 6 Face、idle/walk/attack/hit、roster/BattleUnit、60体：PASS。
- Legacy mix: 120 mesh nodes、12 unique meshes、66 unique materials、12 base textures、1,078,140 triangles。
- Blender/GLB/Godot fixture channel、全preset／全channel、60個体isolation：PASS。
- Normalizerでworking GLBの複数meshを再import／exportし、geometry・UV0・ExpressionUV・maskの一致を確認：PASS。
- Fixture 60体: 2 unique meshes、61 unique materials、2 base textures。Head60＋共有Hair1。
- Validator positive／missing UV／missing mask／unknown material／NaN UVの5テスト：PASS。
- Legacy asset validator: 274 PASS、16 WARNING、0 FAIL。
- Fixture正面capturesのHair内部 (90,100)-(310,285) は5preset間でpixel差0。
  可視Headにはpreset差があり、front_angryの目視でも左眼／眉がHairに遮蔽される。
- 実行環境にcertificate store／shader cache／editor settingsの書き込み警告あり。
  dummy rendererは終了時にmaterial警告を出すがlegacy suite自体はPASS。

## Phase 5 remaining work

Face007原本は1 mesh / 1 combined material、UV0のみ、6,821 vertices / 6,087 triangles。
Head/Hair境界・UV/mask・normalization metadataがない。
初回はBlender MCPへ接続できなかったが、ユーザーの再接続後にBlender 5.1.2へ接続確認済み。
`artifacts/face007_authoring/face007-working.blend` に専用作業シーンとHead/Hair材質スロットを準備した。
原本は695 UV島で、継ぎ目の重複頂点を仮想的につないでもHead/Hairの明示境界がなかった。
原本を推測分類せず、ポリゴンの明示割当待ち。既存001〜006も再生成していない。
[作業手順](../../artifacts/face007_authoring/README.md)と原本正面renderをworking directoryへ保存した。

**Phase 5全体は未完了**。明示authoringされたFace007 working assetが必要。
それを使った正式GLB、Body001〜006との組合せ、4 animations中のv2、ゲームカメラ確認、
Face007入り60体とPhase4の実レンダリング性能比較、正式reference captureは未実施。
fixtureのresource数は描画性能改善や実キャラクターの成功を証明しない。

## API references

- [Godot spatial shader UV2/COLOR](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html)
- [Godot per-instance uniforms](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/shading_language.html#per-instance-uniforms)
- [Blender glTF exporter](https://docs.blender.org/manual/en/5.1/addons/import_export/scene_gltf2.html)
