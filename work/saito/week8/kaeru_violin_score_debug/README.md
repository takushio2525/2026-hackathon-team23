# かえるのうた ヴァイオリン単体版

ヴァイオリン単体で「かえるのうた」の主旋律を演奏するための Processing 確認用スケッチです。
week7 の金管・低音・ドラム版とは分け、解析アプリで書き出した JSON から音を合成する構成にしています。

## 前提

| 項目 | 内容 |
|---|---|
| 曲 | かえるのうた（ハ長調） |
| テンポ | 96 BPM |
| パート | ヴァイオリン単体 |
| 音域 | C4〜A4 |
| 音色 | `data/violin.tweaked.instrument.json` |

最後の「ドドレレミミファファ」は、1拍の中に2つの半拍音符を入れるため、
`subNote`, `subVelocity`, `subOffsetQ8`, `subDurationQ8` を使っています。
`durationQ8` は `256 = 1拍`、`128 = 半拍` です。

## 実行方法

1. Processing 4 で `kaeru_violin_score_debug.pde` を開く。
2. Minim ライブラリが未導入の場合は、Contribution Manager から `Minim` を追加する。
3. Run すると自動で1回再生される。
4. もう一度聞く場合は `P` キーを押す。

## 音色の差し替え

課題条件に合わせ、WAV の直接再生ではなく、JSON の `harmonics`, `envelope`, `modulation`,
`noise`, `fx.chorus` をもとに Processing 側で合成します。
音色を作り直した場合は、`violin.tweaked.instrument.json` というファイル名で `data/` に置き換えてください。

`data/` にある `violinC4.wav`〜`violinB4.wav` は、GarageBand で書き出した参考音源です。
このスケッチの再生には使っていません。

この音色確認が不要になった場合は、このフォルダごと削除して構いません。
