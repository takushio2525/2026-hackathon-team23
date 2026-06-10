# node_05 — 輪唱 声部 4（test_v3）

Arduino UNO R4 WiFi で「かえるのうた」輪唱の **声部 4（最終声部）** を担当する。
**24 拍遅れて**入り、この声部が 1 周を終えるまで先頭声部（node_02）は次の周回を始めない
（輪唱サイクル `CANON_CYCLE_BEATS=56` 拍を全声部で共有）。

## この声部の設定（`include/ProjectConfig.h`）

| 項目 | 値 | 意味 |
|---|---|---|
| `partId` | `0x05` | 輪唱のどの声部か（NOTE パケットに乗る） |
| `headRestBeats` | `24` | 先頭に 24 拍ぶん休符を入れてから鳴り始める |
| `instrumentId` | `3` | PC 側（orchestra_resynth）で `data/*.json` の何番目の楽器定義を使うか（3=チューバ） |

node_02 は `headRestBeats=0 / instrumentId=0`（トランペット）、node_03 は `8 / 1`（ホルン）、
node_04 は `16 / 2`（トロンボーン）。**楽譜 `src/score_data.cpp`（かえるのうた・32 拍）は
4 台とも同一**で、頭の休符ぶんずらして入ることで輪唱（カノン）になる。

設定値以外の動き・ビルド方法・SERIAL_DEBUG・構成は `node_02/README.md` と同じ
（node_02 のコードをコピーし `ProjectConfig.h` だけ差し替えたもの。UI 中継
`UiRelayModule` は node_02 のみで本ノードには無い）。

```bash
pio run -d firmware/test_v3/node_05                  # ビルド
pio run -d firmware/test_v3/node_05 -t upload        # 書き込み
pio device monitor -d firmware/test_v3/node_05       # 注: Processing と同時に開けない (ポート競合)
```
