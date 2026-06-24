# node_02 — 輪唱 声部 1（production）

Arduino UNO R4 WiFi で「かえるのうた」輪唱の **声部 1** を担当する。曲頭から入る。

## この声部の設定（`include/ProjectConfig.h`）

| 項目 | 値 | 意味 |
|---|---|---|
| `partId` | `0x02` | 輪唱のどの声部か（NOTE パケットに乗る） |
| `headRestBeats` | `0` | 先頭に入れる休符の拍数。0 = 曲頭から鳴り始める |
| `instrumentId` | `0` | PC 側（orchestra_resynth）で `data/*.json` の何番目の楽器定義を使うか |

node_03 は `headRestBeats=8 / instrumentId=1`、node_04 は `16 / 2`、node_05 は `24 / 3`。
**楽譜 `src/score_data.cpp`（かえるのうた・32 拍）は 4 台とも同一**で、頭の休符ぶんずらして
入ることで輪唱（カノン）になる。

## 動きの核

- **役割**: 指揮者ノード node_01 の SoftAP に STA で接続 → CTRL/BEAT を UDP マルチキャストで受信 →
  マスタ時刻 `playAtMasterMs` に揃えて楽譜を 1 拍進め、NOTE を USB Serial で Mac（Processing）へ送出
- **NOTE の中身**: `instrumentId`（楽器番号）/ `noteNumber`（高さ）/ `durationMs`（長さ）/ `partId`（声部）/ `velocity`。
  消音は送らない（PC 側が `durationMs` から自動でリリース）
- **楽譜の進み方**: 「指揮者の拍番号 `firedBeatNo`」から自分の楽譜インデックスを計算する
  （`cyclePos = (firedBeatNo - 1) % 56`、`cyclePos - headRestBeats` が 0〜31 の窓内のときだけ
  `kScore[]` を発火。56 = 曲長 32 + 最終声部 node_05 の遅延 24 の輪唱サイクル）。拍番号で引くので、PC 側 Processing を
  曲の途中で起動しても「いまの拍」から鳴り始める。拍が 1 つ飛んでも `firedBeatNo` に追随する
  だけでズレが残らない（自己補正）
- **状態遷移**: Idle → WaitStart（Wi-Fi 接続）→ Playing（初回 BEAT 受信）。Playing からは戻らず、
  BEAT が来ない間は次の BEAT を待つだけ。`sync.converged` 待ちはしない（未収束で「鳴らない」を回避）
- **発音タイミング**: 受信した BEAT の `playAtMasterMs` をローカル時刻に変換
  （`targetLocalMs = playAtMasterMs - sync.offsetMs`）し、その時刻に達したら発火。過去になっている
  BEAT は捨てずに即発火。複数ノードが同じ `playAtMasterMs` を共有するので受信ジッタによらず
  発音タイミングが揃う
- **時計同期**: CTRL/BEAT 受信時刻と `header.timestampMs` の差を EMA（α=0.10）で推定
- **テンポ**: 指揮者が CTRL で配る BPM をそのまま使って `durationMs` を計算する（最初の 1 音は 100 BPM、
  2 拍目以降は指揮者の推定値。詳細は `node_01/README.md`）

## 配線

外部配線なし。USB Type-C で Mac（Processing 起動）に直結すれば給電＋Serial＋WiFi STA まで揃う。

## ビルド

```bash
pio run -d firmware/production/node_02                  # ビルド
pio run -d firmware/production/node_02 -t upload        # 書き込み
pio device monitor -d firmware/production/node_02       # 注: Processing と同時に開けない (ポート競合)
```

シリアルポートは Processing 側が開く。`pio device monitor` を使うときは Processing を閉じる。

## シリアルデバッグ出力（SERIAL_DEBUG）

`platformio.ini` の `-DSERIAL_DEBUG=0`（既定 / Processing 連携優先）では **20 B のバイナリ
NOTE パケットだけ**が流れる。実機で挙動を切り分けたいときは `-DSERIAL_DEBUG=1` にしてビルド
すると、Serial は人間可読テキスト専用になり（= バイナリ NOTE は流れない＝ Processing には音が来ない）、
起動時の `init()` OK/NG・200 ms 周期の状態ダンプ・`[N2 EVT STATE/WIFI/SYNC_CONVERGED/CTRL/BEAT]`・
`[N2 NOTE_ON]`（part/instr/note/vel/dur）が `pio device monitor` で読める。

## 構成

```
node_02/
├── platformio.ini
├── include/
│   ├── ProjectConfig.h     # この声部の設定 (partId / headRestBeats / instrumentId)
│   ├── SystemData.h        # モジュール間共有データ
│   └── score_data.h        # 楽譜配列の宣言
├── src/
│   ├── main.cpp            # 3 フェーズループ
│   ├── applyPattern.cpp    # 状態遷移 / マスタ時刻判定 / 拍番号→楽譜インデックス
│   └── score_data.cpp      # 楽譜本体 — かえるのうた (kScore[], 32 拍)。4 台とも同一
└── lib/
    ├── OrcReceiverModule/  # CTRL/BEAT を整形して Sync / Receiver / Ctrl に書く
    └── NoteSenderModule/   # NOTE (楽器番号/長さ/高さ…) を USB Serial へ送出
```

node_03〜05 はこのコードのコピー。差し替えるのは `include/ProjectConfig.h` だけ
（`partId` / `headRestBeats` / `instrumentId`）。`score_data.*` は同一。
