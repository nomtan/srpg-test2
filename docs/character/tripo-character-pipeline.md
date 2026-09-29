# Tripo モジュラーキャラクターパイプライン

Phase 2（2026-09-30）。新規キャラクターの正式な出力は、独立した Body / Face / Hair の `model.glb` である。統合 `character.glb` は新規制作の入力・中間出力にしない。既存の `charcter001`〜`charcter004` の統合GLBと旧スクリプトは回帰比較のためだけに保持する。

```text
Tripo Body ── Blender正規化・検証 ── modular/body/NNN/model.glb ──┐
Tripo Face ── Blender正規化・検証 ── modular/face/NNN/model.glb ──┼─ CharacterDefinition ─ CharacterAssembler ─ Godot
Tripo Hair ── Blender正規化・検証 ── modular/hair/NNN/model.glb ──┘
```

## 原本と配置

- `assets/characters/tripo/body/<3桁ID>/model.glb`、`face/<3桁ID>/model.glb`、将来の `hair/<3桁ID>/model.glb` は immutable source。加工済みGLBを原本へ書き戻さない。
- 正式出力は `assets/characters/modular/{body,face,hair}/<3桁ID>/model.glb`。
- 各パーツの `normalization.json` はそのパーツ固有のBlender正規化設定。BodyとFaceの**組み合わせ**固有の補正値を記録しない。
- `assets/characters/modular/definitions/charcterNNN.tres` は既存IDを維持する。新しいIDの内部表記には `character` を用いられるが、既存IDの一括リネームはしない。
- 旧 `assets/characters/generated/charcterNNN/character.glb` は回帰比較のみ。`export_modular_parts.py` と旧キャラクターmanifestは移行履歴であり、新規パーツの制作手順に含めない。

## 共通座標とリグ

Blenderはメートル・Z-up、GodotはY-up。出力時のroot、Armature、mesh objectは位置0、回転0、scale1にする。適合のための平行移動・一様scaleはBlenderでメッシュ頂点へ焼き込む。軸変換はglTF exporterに任せる。

Bodyは `humanoid_v1` の65ボーンを持つ唯一のSkeletonを含む。`head` とroot/hipsを必須にし、全ボーンの名前・親子関係・rest translation/rotation/scaleをBody 001と一致させる。特に `head` のrest位置、向き、scaleが全Bodyで同一であることを検証する。Bodyには `idle` / `walk` / `attack` / `hit` の4クリップとAnimationPlayerを持たせる。Body 001のTripo rigを基準として、rigがないBodyにはBlenderでウェイトを転送する。規格差があればBlenderで修正してから出力し、GodotにBody ID別の補正を追加しない。

FaceとHairはそれぞれ独立GLBの静的メッシュで、Skeleton、skin、AnimationPlayer、animationを含めない。両者の頂点座標は共通 `humanoid_v1` Skeletonの**rest空間**に正規化する。Godotでは `head` の `BoneAttachment3D` に `FaceSocket` を置き、Faceと `HairSocket` に同一の `get_bone_global_rest(head_index).affine_inverse()` を一度だけ適用する。HairSocketの子にHairを置く。Body/Face/Hair ID別、または組み合わせ別のランタイム補正は使わない。

既存Face 001〜004には髪が一体化している。これらの `hair_id` は空文字にして従来の見た目を維持する。新規のFace/Hairは別々に正規化する。実運用のHairを用意する際は原本を `tripo/hair` へ登録し、パーツ固有の `normalization.json` で共通rest空間へ焼き込む。

## 独立エクスポート

各パーツの正規化設定を出力先と同じIDディレクトリの `normalization.json` に用意する。Face/Hairには正の `scale` とBlender Z-upメートルの `position: [x,y,z]`、Bodyには `rig_profile: humanoid_v1` と必要なら `arm_alignment: match_rig_source` を記す。`body/001`〜`004`、`face/001`〜`004` には既存4体の検証済み設定がある。

Blender 5.1で、原本と同じIDを指定して**パーツごとに別プロセス**で実行する。まず `artifacts/modular_direct` のような作業領域へ出力する。

```powershell
python tools/asset_gen/character_pipeline/scan_sources.py
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind body --id 005 --output-root artifacts/modular_direct
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' -b --factory-startup --python tools/asset_gen/character_pipeline/build_modular_parts.py -- --kind face --id 005 --output-root artifacts/modular_direct
python tools/asset_gen/character_pipeline/validate_modular_parts.py --root artifacts/modular_direct
```

Hair原本があれば `--kind hair` も同様に実行する。Blenderの出力ログに `DIRECT_MODULAR_EXPORT` があることを確認する。Blenderはスクリプト例外でも終了コード0を返す場合があるので、終了コードだけでは判定しない。検証後に `model.glb` を正式ディレクトリへ配置し、Godotでimport・実行時テスト・目視確認を行う。検証失敗をGodotのtransform補正で隠さない。

`validate_modular_parts.py` はGLBのメッシュ、skin数、65ボーンの名前・親子・全rest変換、4クリップ、Face/Hairのskin・animation不在とmesh objectのidentity transformを確認する。エクスポータもBlenderシーン内のtransform、メッシュ、rig、clipを出力前に検査する。

## Godot組み立てと性能

`CharacterDefinition` は `body_id`、`face_id`、任意の `hair_id` を持つ。`hair_id == ""` は正常なBody+Face構成。`CharacterAssembler.assemble()` はspawn時の一度だけPackedSceneを読み込み、Body Skeletonへsocketを作成してFace/Hairを装着し、共有toon材質を割り当てる。`_process()` でのパーツ探索、load、instantiate、transform計算、材質生成は行わない。個体固有のFace texture差し替えだけ材質を `duplicate()` する。

将来のHeadgear、武器、offhand、capeなどは同じSkeleton上の新しいbone socketまたはFaceSocketの子として追加する。Body/Face組み合わせごとの分岐は増やさない。

## 検証

```powershell
python tools/asset_gen/character_pipeline/validate_modular_parts.py
& 'C:\Users\nomur\Desktop\godot\Godot_v4.6.1-stable_win64_console.exe' --headless --path . --script tools/asset_gen/character_pipeline/verify_modular_parts.gd
```

Godotテストは既存4 Body × 4 Face、Hairテスト部品2種と複数Body/Face、単一Skeleton、4クリップでのhead追従、ロスター/戦闘経路、60体と共有Mesh/Materialを確認する。`hair/901` と `hair/902` は装着・交換テスト専用の簡易メッシュで、製品用の髪型ではない。目視検査では実ゲームカメラで首の継ぎ目、頭部の位置・向き、4クリップ、texture、toon shader、outline、影を確認する。
