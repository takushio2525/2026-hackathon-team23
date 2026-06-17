# data

`kaeru_violin_score_debug.pde` が読み込むヴァイオリン音色データを置くフォルダです。

| ファイル | 用途 |
|---|---|
| `violin.tweaked.instrument.json` | Processing 側で合成に使うヴァイオリン音色 JSON |
| `violinC4.wav`〜`violinB4.wav` | GarageBand 書き出しの参考音源（このスケッチでは未使用） |

スケッチは JSON の `harmonics`, `envelope`, `modulation.vibrato`, `noise.level`,
`fx.chorus` を読み、倍音加算、ビブラート、弓ノイズ、薄いデチューン重ねを使って合成します。

解析アプリで音色JSONを作り直した場合は、ファイル名を
`violin.tweaked.instrument.json` にそろえて置き換えてください。
