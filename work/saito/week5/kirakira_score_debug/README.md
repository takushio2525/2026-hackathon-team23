# きらきら星 楽譜デバッグ版

Arduino に組み込む前に、金管4パートの音階と輪唱タイミングを Processing 上で
確認するための仮スケッチです。ドラムパートはこの段階では含めません。

## 前提

| 項目 | 内容 |
|---|---|
| 曲 | きらきら星（C major） |
| テンポ | 固定 96 BPM |
| パート | 金管1〜4（同じ主旋律を輪唱） |
| 入り拍 | 0 / 4 / 8 / 12 拍 |
| 楽譜形式 | Arduino の `ScoreEvent` に合わせた形式 |

`ScoreEvent` は `beatAt`, `noteNumber`, `velocity`, `durationQ8`, `flags` を持ちます。
`durationQ8` は `256 = 1拍`、`noteNumber = 0` と `flags = REST` は休符です。
二分音符の2拍目には休符スロットを置き、Arduino で `beatNo` から位置を求める
場合にも拍位置がずれないようにしています。

## 実行方法

1. Processing 4 で `kirakira_score_debug.pde` を開く。
2. Minim ライブラリが未導入の場合は、Contribution Manager から `Minim` を追加する。
3. Run 後、`P` キーで4パートの再生、`1`〜`4` キーで各パート単独再生を行う。
   再生中にもう一度キーを押すと音が重なるため、1回の再生が終わってから再試聴する。

画面上には各パートの入り拍と、Arduino 用に転記できる `ScoreEvent` 配列の
前提を表示します。

## Arduino へ移す際の扱い

このスケッチの `TWINKLE_SCORE` は `score_data.cpp` の `kScore[]` に転記できる
粒度で作っています。各金管ノードでは同じ配列を利用し、`startBeatNo` だけを
`0`, `4`, `8`, `12` に差し替える想定です。
