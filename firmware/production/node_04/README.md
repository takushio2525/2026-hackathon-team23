# node_04 — 輪唱 声部 3（production）

Arduino UNO R4 WiFi で「かえるのうた」輪唱の **声部 3** を担当する。**16 拍遅れて**入る。

## この声部の設定（`include/ProjectConfig.h`）

| 項目 | 値 | 意味 |
|---|---|---|
| `partId` | `0x04` | 輪唱のどの声部か（NOTE パケットに乗る） |
| `headRestBeats` | `16` | 先頭に 16 拍ぶん休符を入れてから鳴り始める |
| `instrumentId` | `2` | PC 側（orchestra_resynth）で `data/*.json` の何番目の楽器定義を使うか |

node_02 は `headRestBeats=0 / instrumentId=0`、node_03 は `8 / 1`、node_05 は `24 / 3`。
**楽譜 `src/score_data.cpp`（かえるのうた・32 拍）は 4 台とも同一**で、頭の休符ぶんずらして
入ることで輪唱（カノン）になる。

設定値以外の動き・ビルド方法・SERIAL_DEBUG・構成は `node_02/README.md` と同じ
（node_02 のコードをコピーし `ProjectConfig.h` だけ差し替えたもの）。デバッグ出力タグは `[N4 …]`。

```bash
pio run -d firmware/production/node_04                  # ビルド
pio run -d firmware/production/node_04 -t upload        # 書き込み
pio device monitor -d firmware/production/node_04       # 注: Processing と同時に開けない (ポート競合)
```
