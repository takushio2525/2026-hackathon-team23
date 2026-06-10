# data/ — 楽器定義（楽器番号 = ファイル名昇順のインデックス）

`orchestra_resynth.pde` が起動時にこのフォルダの `*.json` を**ファイル名昇順**で全部読み込み、
`0, 1, 2, 3, ...` と番号を振る。Arduino の NOTE パケットに乗る `instrumentId`（楽器番号）が
このインデックスに対応する。

| 番号 | ファイル | 中身 | 想定用途 |
|---|---|---|---|
| 0 | `0_trumpets.tweaked.instrument.json` | トランペット | node_02（主旋律1） |
| 1 | `1_horns.tweaked.instrument.json` | ホルン | node_03（主旋律2） |
| 2 | `2_trombones.tweaked.instrument.json` | トロンボーン | node_04（主旋律3） |
| 3 | `3_tuba.tweaked.instrument.json` | チューバ | 低音伴奏用 |
| 4 | `4_kick.tweaked.instrument.json` | キック | ドラム用 |
| 5 | `5_snare.tweaked.instrument.json` | スネア | ドラム用 |
| 6 | `6_hi_hat.tweaked.instrument.json` | ハイハット | ドラム用 |
| 7 | `7_crash.tweaked.instrument.json` | クラッシュ | ドラム用 |

- ファイル名昇順で楽器番号が決まるため、番号付きファイル名を変える場合は
  `firmware/test_v3/node_0X/include/ProjectConfig.h` の `instrumentId` も合わせる。
- ここには `sound_lab/analyzer` と編集スタジオで作成した音色 JSON だけを置く。
- フォーマット仕様: [`../../../../sound_lab/library_format.md`](../../../../sound_lab/library_format.md)

不要になった音色は、このフォルダから削除して構いません。
