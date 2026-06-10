# data

`kaeru_score_debug.pde` が読み込む、実音解析済みの音色 JSON を置くフォルダです。

| ファイル | 用途 |
|---|---|
| `trumpets.tweaked.instrument.json` | 主旋律1（トランペット）の音色 |
| `horns.tweaked.instrument.json` | 主旋律2（ホルン）の音色 |
| `trombones.tweaked.instrument.json` | 主旋律3（トロンボーン）の音色 |
| `tuba.tweaked.instrument.json` | 低音（チューバ）の音色 |
| `kick.tweaked.instrument.json` | キックの音色 |
| `snare.tweaked.instrument.json` | スネアの音色 |
| `Hi-hat.tweaked.instrument.json` | ハイハットの音色 |
| `crash.tweaked.instrument.json` | クラッシュの音色 |

各ファイルの `harmonics` と `envelope` は Processing の音色合成で使用します。
音色を差し替える場合は、同じ項目を持つ JSON を用意し、スケッチの
`INSTRUMENT_FILES` との対応を保ってください。
ドラムパートも JSON を読み込み、`harmonics`, `envelope`, `noise.level` を使用します。

この音色試聴機能が不要になった場合は、スケッチ側の読み込み処理を外したうえで
このフォルダを削除して構いません。
