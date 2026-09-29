# Body / Face 分離ランタイム移行

2026-09-29。既存の `charcter001`〜`charcter004` を、GodotでBodyとFaceを組み立てる方式へ移行した。既存IDの `charcter` 表記はセーブ・シーン参照との互換性のため維持した。

## アセットと座標規格

- `assets/characters/modular/body/<3桁ID>/model.glb` はBodyメッシュ、65ボーンの共通リグ、`idle` / `walk` / `attack` / `hit` を含む。対応する検証済み統合GLBからHeadノードと不要なメッシュ・テクスチャ領域を除き、Bodyのバイナリデータと4クリップは保持した。
- `assets/characters/modular/face/<3桁ID>/model.glb` は単独のFaceメッシュと元テクスチャを含む。SkeletonとAnimationPlayerは含まない。頂点は統合GLBのHeadと同じBody Skeletonのrest座標で保持する。Godot側で読み込んだ `head` ボーンのglobal rest行列の逆変換をFaceSocket直下に1回適用し、全Faceを共通処理で装着する。
- Faceには髪が一体化している。`HairSocket` は将来の独立Hair用の空ノードである。
- Tripoの `body/**/model.glb` と `face/**/model.glb` は変更していない。

変換の再生成はBlender 5.1で次を実行する。

```text
blender -b --factory-startup --python tools/asset_gen/character_pipeline/export_modular_parts.py
```

## Godot構造

`CharacterDefinition` Resourceが `id`、`body_id`、`face_id` を持つ。既存4体の `.tres` は同じ番号のBodyとFaceを指定する。`CharacterAssembler.assemble()` はIDからGLBを読み込み、BodyのSkeleton3Dに `BoneAttachment3D` の `FaceSocket` を追加し、その子にFaceを置く。装着位置のID別補正はない。アニメーションとSkeletonはBody側のみが所有する。Meshは結合しない。

組み立ては生成時の1回だけ。Godotの `load()` キャッシュと共有トゥーン材質を再利用し、毎フレームの装着処理はない。追加部品は同じSkeletonのbone socketまたは `HairSocket` を利用できる。新しいBodyは `head` boneと共通の装着座標を、FaceはBody Skeletonのrest座標を満たすGLBを追加し、DefinitionにIDを指定する。

初回のFace書き出しではBlender側の `head` rest行列の逆変換を頂点に焼き込んだため、Godotでのボーン軸との違いからサンプルシーンで頭部が90度回転した。現在は元の頂点座標を維持し、Godot自身が読み込んだrest行列で変換する。これはBody/Face IDに依存しない共通処理である。

既存の4つのロスターシーン、探索の切り替え、戦闘の `BattleUnit.setup_visual()` とジョブの既定パスは新方式を参照する。`BattleUnit` はシーンをツリーに入れる前にもモデルを調べるため、ロスターの `prepare_visual()` をそこで1回呼ぶ。探索側の初期ロスター照合は、旧GLBの `scene_file_path` ではなく `character_id` を使う。

## 検証

- `scan_sources.py`: TripoのFace/Body各10原本を確認。
- `verify_modular_geometry.py`: 4つの同番号ペアで元のHeadとFaceの双方向頂点距離は `0 m`。各Headのポリゴン数は同一。Face GLBのJPEGは対応する統合GLB内のJPEGとバイト単位で一致した。
- `verify_modular_parts.gd`: 4×4の全16組み合わせで単一Skeleton、単一AnimationPlayer、共通FaceSocket、4クリップ中のhead追従とFaceの向きを確認。同番号4組では、旧GLBのスキン変換後の頭部中心と新方式の頭部中心が全4クリップで `0.0001 m` 未満の差。Body側head poseも一致。ロスター4シーンとBattleUnit4体でAnimationPlayerを取得。60体同時生成では60 Skeletonを確認。
- `verify_tripo_switching.gd`: 探索・会話・戦闘中の4体切り替え、武器、アニメーション位相、HUDを確認し `TRIPO_SWITCHING: PASSED`。
- 旧 `verify_characters.gd`: 統合GLBの既存検証も `CHARACTER_BATCH_VALIDATION: PASSED`。
- Blender Workbenchで同番号4組と交換した5組の静止画を描画し、頭部の浮き・埋まり・回転ずれと首元を目視確認した。画像は [`artifacts/modular_preview`](../../artifacts/modular_preview/) に保存した。

## 旧方式の整理候補

旧ロスターシーンから統合GLBへの直接参照と、未使用の `set_face_variant()` / Face outline差し替え処理は削除した。`assets/characters/generated/charcter001`〜`charcter004` の統合GLBは実行時には参照しないが、現在の分離エクスポータの入力であり、旧方式との回帰比較にも用いる。Tripo原本から独立Body/Faceを直接生成する工程へ置き換えるまでは保持する。`build_characters.py` と旧manifestもその再生成記録として保持する。

## 変更ファイル

- `assets/characters/modular/`: Body/Face GLB各4、Definition Resource各4、Godotのimport設定と抽出テクスチャ。
- `scripts/character/character_definition.gd`、`character_assembler.gd`、`tripo_roster_character.gd`: 定義、組み立て、ロスター表示。
- `scenes/characters/tripo_roster/charcter001.tscn`〜`charcter004.tscn`: 統合GLB参照をDefinitionへ変更。
- `scripts/unit/battle_unit.gd`、`scripts/world_jrpg/world.gd`、`scripts/job/job_database.gd`、`scripts/dev/flat_validation.gd`、`flat_grass_test.gd`: 戦闘・探索・検証経路を新シーンへ接続。
- `tools/asset_gen/character_pipeline/export_modular_parts.py`、`verify_modular_geometry.py`、`verify_modular_parts.gd`、`render_modular_preview.py`: 再生成と検証。
- `docs/character/tripo-character-pipeline.md`、本書、`artifacts/modular_preview/`: 移行記録と静止画。

Godot実画面での透過・影・輪郭を含む比較は、このヘッドレス検証とBlender静止画には含まれない。元のUV・JPEGとトゥーンシェーダーを再使用しているが、最終的な戦闘カメラでの目視確認は別途必要である。
