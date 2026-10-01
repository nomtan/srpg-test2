# Face003 Normalization Analysis

## 結論

Face003 は誤設定ではなく、元 source の横幅が他 Face より小さい一方で縦寸法が同程度という造形差を保つための legacy variation である。分類は「B. キャラクターデザイン上必要な variation」。`scale=0.63` と Z-up position の `z=0.79` は新規 Face の既定値にはせず、Face003 metadata の legacy exception として維持する。

## Evidence

| ID | source W×H×D | scale | position | modular W×H×D | modular center Y |
|---|---|---:|---|---|---:|
| 001 | 0.9583×0.9372×0.9535 | 0.5395 | 0,-0.055,0.89 | 0.5170×0.5056×0.5144 | 1.1428 |
| 002 | 0.9647×0.9710×0.9275 | 0.5360 | 0,-0.055,0.89 | 0.5171×0.5204×0.4971 | 1.1502 |
| 003 | 0.8206×0.9729×0.8396 | 0.6300 | 0,-0.055,0.79 | 0.5170×0.6129×0.5290 | 1.0965 |
| 004 | 0.9719×0.9571×0.9715 | 0.5400 | 0,-0.055,0.89 | 0.5248×0.5168×0.5246 | 1.1484 |

Face003 の source width は約0.8206 m で、他の約0.96〜0.98 m より明確に小さい。0.63倍することで modular width は0.5170 mとなり、001 / 002 と一致する。したがって 0.63 は旧 pipeline の偶発値ではなく横幅を共通 head-space へ合わせる補正である。

同時に source height は0.9729 mと通常範囲なので、同じ scale により modular height は0.6129 mになる。低い position はその高い silhouette の neck connection を戻すために必要で、結果は hard bounds 0.44〜0.65 m 内に収まる。

## Runtime Result

- Face003 は全6 Bodies との組み合わせで assemble 成功
- 4 clips で `FaceSocket` follow / rest cancellation 成功
- body003 + face003 は legacy combined `charcter003` の head center と一致
- expression preset / individual channel / instance isolation 成功

## Standard Treatment

- Face003: height と center Y を WARNING、hard bounds 内なので legacy PASS
- Face007 以降: recommended range を目標にし、この数値をテンプレートへコピーしない。
- 同様の縦長 design が必要な新規 Face は、Inspector、neck fit、game camera review を根拠に metadata へ明示する。

