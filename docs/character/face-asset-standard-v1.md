# Face Asset Standard v1

Face は `Head + Hair` を1部品として扱う。`hair_id`、`HairSocket`、`modular/hair` は導入しない。

## Required Contract

- Standard: `ashen_character_v1`, version 1
- coordinate space: `humanoid_v1_rest`
- Skeleton / Skin / Animation: 0
- render mesh transform: identity
- UV set: 1以上
- Body 固有 offset: 禁止
- runtime attachment: `Body Skeleton → head → FaceSocket → Face`
- texture: 原則 base color のみ、最大 side 512 推奨
- new Face: Head と Hair を material boundary で識別可能にする。

## Head / Hair Method

新規 Face007 以降の正式方式は material separation とする。

- material 名 `Head*`: Expression UV v2 対象（第2 UV + 頂点カラーRマスク必須）
- material 名 `Hair*`: expression projection 対象外
- 同一 GLB / 同一 Face ID の中に両方を持つ。
- geometry を推測して自動分割しない。分類不能なら normalizer は FAIL し、Blender authoring へ戻す。

この方式は mesh を不必要に分割せず、Godot shader 側で surface を安全に選べる。001〜006 は単一 mesh / material の legacy combined であり、破壊的再生成を避けるため WARNING 互換とする。

UV／maskの出力規格・検証状況は [Face Expression Rendering v2](face-expression-rendering-v2.md) を参照。Face007 authoringは未完了。

## Reference Measurements

以下はサイズ統一前のPhase4測定。現行Faceは顎幅0.2035m基準で等方スケール済み（Face004は例外）。
形状・UV0は保持し、縦横比・髪型差は維持する。現行の実寸・接続確認は
[顎幅基準](face-size-jaw.md)を参照。

| ID | vertices | triangles | textures | bounds W×H×D (m) | center X,Y,Z (m) |
|---|---:|---:|---:|---|---|
| 001 | 7,587 | 6,671 | 1 | 0.5170 × 0.5056 × 0.5144 | 0.0010, 1.1428, 0.0600 |
| 002 | 7,122 | 6,460 | 1 | 0.5171 × 0.5204 × 0.4971 | 0.0004, 1.1502, 0.0562 |
| 003 | 7,026 | 5,698 | 2 | 0.5170 × 0.6129 × 0.5290 | 0.0008, 1.0965, 0.0557 |
| 004 | 5,451 | 6,216 | 1 | 0.5248 × 0.5168 × 0.5246 | 0.0011, 1.1484, 0.0550 |
| 005 | 11,534 | 11,065 | 1 | 0.5273 × 0.5220 × 0.5240 | 0.0007, 1.1510, 0.0552 |
| 006 | 10,721 | 10,557 | 1 | 0.5242 × 0.4824 × 0.5252 | -0.0010, 1.1312, 0.0560 |

## Head-space Range

| value | recommended | hard bounds |
|---|---|---|
| width | 0.41–0.43 | 0.39–0.45 |
| height | 0.38–0.54 | 0.35–0.65 |
| depth | 0.39–0.54 | 0.35–0.60 |
| center X | -0.03–0.03 | -0.08–0.08 |
| center Y | 1.03–1.12 | 0.98–1.20 |
| center Z | 0.04–0.08 | 0.00–0.12 |

Face003 は height / center Y が recommended 外だが hard bounds 内の legacy variation である。詳細は [Face003 analysis](face003-normalization-analysis.md) を参照する。

## Performance Budget

| metric | recommended | warning ceiling | hard limit |
|---|---:|---:|---:|
| vertices | 12,000 | 18,000 | 24,000 |
| triangles | 12,000 | 18,000 | 24,000 |
| materials | 2 | 3 | 4 |
| textures | 2 | 3 | 4 |

