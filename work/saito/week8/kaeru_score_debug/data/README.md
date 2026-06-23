# data

`kaeru_score_debug.pde` が読み込む、実音解析済みの音色 JSON を置くフォルダです。week9 スケッチに必要なデータをすべて同梱しています。

| ファイル | 用途 |
|---|---|
| `trumpets.tweaked.instrument.json` | 主旋律1（トランペット）の音色 |
| `horns.tweaked.instrument.json` | 主旋律2（ホルン）の音色 |
| `trombones.tweaked.instrument.json` | 主旋律3（トロンボーン）の音色 |
| `tuba.tweaked.instrument.json` | 主旋律4（チューバ）の音色 |
| `kick.tweaked.instrument.json` | キックの音色 |
| `snare.tweaked.instrument.json` | スネアの音色 |
| `Hi-hat.tweaked.instrument.json` | ハイハットの音色 |
| `crash.tweaked.instrument.json` | クラッシュの音色（`drum_sample` を含む場合は原音1打を再生） |

金管4パートは `MELODY_PARTS`、ドラム4音色は `DRUM_INSTRUMENT_FILES` の順に対応します。
通常は各 JSON の `harmonics`, `envelope`, `noise.level` で合成します。クラッシュだけは
`drum_sample` があれば、その解析済み原音1打を優先して再生します。

ドラムの `noteNumber` は `36=キック`, `38=スネア`, `42=ハイハット`, `49=クラッシュ` です。

この音色試聴機能が不要になった場合は、スケッチ側の読み込み処理を外したうえで
このフォルダを削除して構いません。
