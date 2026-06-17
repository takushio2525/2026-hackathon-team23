# data

`kaeru_violin_score_debug.pde` が読み込む音色 JSON を置くフォルダです。

| ファイル | 用途 |
|---|---|
| `violin.representative.instrument.json` | ヴァイオリン単体版の音色 |

スケッチは JSON の `harmonics` と `envelope` を使って倍音加算合成を行い、
`noise.level` がある場合だけ、ごく薄く弓のこすれ成分としてノイズを足します。

解析アプリで作った代表音色JSONに差し替える場合も、ファイル名を
`violin.representative.instrument.json` にそろえてください。
