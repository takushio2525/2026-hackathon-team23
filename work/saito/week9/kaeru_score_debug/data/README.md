# data

`kaeru_score_debug.pde` が読み込む、実音解析済みの音色 JSON を置くフォルダです。week9 スケッチに必要なデータをすべて同梱しています。

| ファイル | 用途 |
|---|---|
| `trumpets.tweaked.instrument.json` | 主旋律1（トランペット）の音色 |
| `horns.tweaked.instrument.json` | 主旋律2（ホルン）の音色 |
| `trombones.tweaked.instrument.json` | 主旋律3（トロンボーン）の音色 |
| `tuba.tweaked.instrument.json` | 主旋律4（チューバ）の音色 |
| `kick.tweaked.instrument.json` | キックの音色（原音1打を含む） |
| `snare.tweaked.instrument.json` | スネアの音色（原音1打を含む） |
| `Hi-hat.tweaked.instrument.json` | ハイハットの音色（原音1打を含む） |
| `crash.tweaked.instrument.json` | クラッシュの音色（原音1打を含む） |

金管4パートは `MELODY_PARTS`、ドラム4音色は `DRUM_INSTRUMENT_FILES` の順に対応します。
各ドラムJSONに `drum_sample` があれば、その解析済み原音1打を優先して再生します。
`drum_sample` がないJSONだけは、`harmonics`, `envelope`, `noise.level` による合成へ自動的に戻ります。

ドラムの `noteNumber` は `36=キック`, `38=スネア`, `42=ハイハット`, `49=クラッシュ` です。

この音色試聴機能が不要になった場合は、スケッチ側の読み込み処理を外したうえで
このフォルダを削除して構いません。
