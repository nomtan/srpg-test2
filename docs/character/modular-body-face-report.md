# Body / Face ランタイム移行と Phase 3 表情

## 現行構造

`CharacterDefinition(body_id, face_id, expression_profile_id)` から `CharacterAssembler` がBodyとFaceを装着する。Face 001〜004は頭部と髪を一体とした既存GLBをそのまま使う。Bodyの唯一のSkeletonにある `head` ボーンへFace全体が追従し、Bodyの4クリップは維持する。`ExpressionController` が目・眉・口のatlas行を個体のFace材質へ設定する。Body側のトゥーン材質、FaceのMesh、テクスチャ、shaderは共有し、表情parameterを持つFace材質だけ複製する。

Phase 2の髪分離用 `hair_id`、`HairSocket`、Hairロード、テストfixture、build/validatorのHair経路はPhase 3で撤去した。新しい髪型は新しいFaceとして制作する。詳しい規格と出力手順は [Tripo キャラクターパイプライン](tripo-character-pipeline.md) を参照。

## Reference Rig

Phase 2のBody001をもとに `assets/characters/_shared/rigs/humanoid_v1.glb` を固定した。65ボーンとdonorメッシュを含み、animationは含まない。`build_modular_parts.py` はこのGLBからrigとウェイト転送用donorを取得し、通常のBody出力ではBody001原本を参照しない。`validate_modular_parts.py` は共有GLBの全rest変換と各Bodyを照合する。

## 検証

- `validate_modular_parts.py`: Body 001〜004、Face 001〜004が規格に合致。
- `verify_modular_parts.gd`: 16組で単一Skeleton、4クリップの追従、`normal` / `angry` / `smile`、blink、個別の眉と口、ロスター/戦闘のAPI、60体での共有Meshと個体別Face材質を確認。
- 旧統合GLBとのhead中心比較は同番号4組・4クリップで継続。

表情用SVGは仮の図柄。`artifacts/phase3_face001_*.png`、`phase3_face002_*.png` と `phase3_main_expressions.png` で、normal / angry / smile / blink + mouth openの可視差、ゲームカメラでの装着を確認した。前髪が顔面を大きく覆うため、現行単一材質では投影線が前髪に載る箇所がある。今後の正式Face素材では頭部/髪のmaterialまたはmaskを制作時に用意する必要がある。
