# node_04 — 輪唱 声部 3（test_v2）

Arduino UNO R4 WiFi で「きらきら星」輪唱の **声部 3** を担当する。**16 拍遅れて**入る。

## この声部の設定（`include/ProjectConfig.h`）

| 項目 | 値 | 意味 |
|---|---|---|
| `partId` | `0x04` | 輪唱のどの声部か（NOTE パケットに乗る） |
| `headRestBeats` | `16` | 先頭に 16 拍ぶん休符を入れてから鳴り始める |
| `instrumentId` | `2` | PC 側（orchestra_resynth）で `data/*.json` の何番目の楽器定義を使うか |

node_02 は `headRestBeats=0 / instrumentId=0`、node_03 は `headRestBeats=8 / instrumentId=1`。
**楽譜 `src/score_data.cpp`（きらきら星 全曲・48 拍）は 3 台とも同一**で、頭の休符ぶんずらして
入ることで輪唱（カノン）になる。

設定値以外の動き・ビルド方法・SERIAL_DEBUG・構成は `node_02/README.md` と同じ
（node_02 のコードをコピーし `ProjectConfig.h` だけ差し替えたもの）。デバッグ出力タグは `[N4 …]`。

```bash
pio run -d firmware/test_v2/node_04                  # ビルド
pio run -d firmware/test_v2/node_04 -t upload        # 書き込み
pio device monitor -d firmware/test_v2/node_04       # 注: Processing と同時に開けない (ポート競合)
```
