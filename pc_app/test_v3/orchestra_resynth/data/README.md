# data/ — 楽器定義（楽器番号 = ファイル名昇順のインデックス）

`orchestra_resynth.pde` が起動時にこのフォルダの `*.json` を**ファイル名昇順**で全部読み込み、
`0, 1, 2, 3, …` と番号を振る。Arduino の NOTE パケットに乗る `instrumentId`（楽器番号）が
このインデックスに対応する。

| 番号 | ファイル | 中身 | 使うノード |
|---|---|---|---|
| 0 | `0_organ.json` | オルガン風（持続音, 手書きサンプル）| node_02（声部 1） |
| 1 | `1_flute.json` | フルート（sound_lab で実音を解析, 持続音）| node_03（声部 2） |
| 2 | `2_bell.json` | 鐘風（減衰音, 非整数倍音, 手書きサンプル）| node_04（声部 3） |
| 3 | `3_flute_tweaked.json` | フルート（編集スタジオで調整した版）| 予備（どのノードにも割り当てていない） |

- ファイル名は何でもよいが、番号順を固定したいので `0_` `1_` … と数字で始めている。
- 楽器を差し替えたい / 増やしたいときは、`sound_lab/analyzer` で解析してダウンロードした
  `*.instrument.json` をここに置く（実行中なら `i` キーで再スキャン）。Arduino 側
  `ProjectConfig.h` の `instrumentId` を、使いたいファイルの番号（昇順のインデックス）に合わせること。
- フォーマット仕様: [`../../../../sound_lab/library_format.md`](../../../../sound_lab/library_format.md)

> `0_organ.json` / `2_bell.json` は手書きサンプル（解析結果ではない）。`1_flute.json` /
> `3_flute_tweaked.json` は `sound_lab/processing/instrument_player/data/` にあった解析結果を
> 持ってきたもの。
