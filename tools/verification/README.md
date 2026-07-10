# MOE/MOP 検証プログラム

計画書 表 1.4「MOE と MOP の対応関係および目標値」全 9 項目を 1 台の PC で検証するツール。

## 構成

```
tools/verification/
├── README.md              ← このファイル
├── requirements.txt       ← Python 依存 (pyserial, matplotlib, numpy)
├── .gitignore             ← .venv/ 等を除外
├── logs/                  ← ログ保存先
├── results/               ← 計測 CSV + グラフ
│   ├── mop1〜9/           ← 各 MOP の計測結果 CSV
│   └── graphs/            ← mop_graphs.py が生成する PNG
├── scripts/
│   ├── serial_logger.py   ← 複数ポート同時ログ収集
│   ├── analyze.py         ← 全 9 項目 PASS/FAIL 判定
│   ├── mop1〜9_*.py       ← 各 MOP の個別計測スクリプト
│   ├── common.py          ← 計測スクリプト共通処理
│   └── mop_graphs.py      ← 計測結果のグラフ生成（発表用）
└── firmware/
    ├── README.md           ← 検証ファームの説明
    ├── main_conductor_perf.cpp   ← MOP8 用 指揮者
    └── main_instrument_perf.cpp  ← MOP8 用 楽器
```

## 前提条件

- Python 3.8+
- USB 接続: 指揮者 (XIAO ESP32-S3 or DevKitC) + 楽器 (Arduino UNO R4 WiFi) × 1〜5 台
- ファームウェア: `firmware/production/` の node_01〜06
- 全ノードの `platformio.ini` で `build_flags` に `-DSERIAL_DEBUG=1` を追加

## セットアップ

```bash
cd tools/verification
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## テスト手順

### 準備: 全ノードを SERIAL_DEBUG=1 にする

各ノードの `platformio.ini` の `build_flags` に `-DSERIAL_DEBUG=1` を追加してビルド・書き込み:

```bash
# 例: node_02 の場合
# firmware/production/node_02/platformio.ini の build_flags に -DSERIAL_DEBUG=1 を追加
pio run -d firmware/production/node_02 -t upload
```

**注意**: `SERIAL_DEBUG=1` では楽器のバイナリ NOTE 送出が止まるため Processing 連携不可。
MOP2 テストのみ `SERIAL_DEBUG=0` に戻す必要がある（後述）。

### Step 1: ログ収集

全ノードを PC に USB 接続してから:

```bash
cd tools/verification
python3 scripts/serial_logger.py
```

自動で USB シリアルポートを検出してログ収集を開始する。手動指定も可:

```bash
python3 scripts/serial_logger.py --ports /dev/cu.usbmodem1234 /dev/cu.usbmodem5678
```

### Step 2: テストシナリオを実行

ログ収集中に以下のシナリオを手動で実行する:

1. **起動テスト (MOP7)**: 全ノードの電源を同時に入れる（ログ収集を先に開始しておく）
2. **指揮開始**: 指揮者を振ってキャリブレーション → 演奏を開始
3. **定常演奏 (MOP1/3/4/5/9)**: 一定テンポで 60 秒以上演奏（例: メトロノーム 120 BPM に合わせて振る）
4. **テンポ変更 (MOP6)**: 演奏中にテンポを大きく変える（例: 100→140 BPM）

Ctrl+C でログ収集を停止。ログは `logs/test_YYYYMMDD_HHMMSS.log` に保存される。

### Step 3: 解析

```bash
python3 scripts/analyze.py logs/test_XXXXXXXX_XXXXXX.log
```

MOP1 の検出率を計算するには期待 BPM とテスト時間を指定:

```bash
python3 scripts/analyze.py logs/test_XXXXXXXX_XXXXXX.log \
  --expected-bpm 120 --test-duration 60
```

## 各 MOP 項目のテスト方法

### MOP1: 拍検出の正確性 (正解率 >= 90%)

| 項目 | 内容 |
|---|---|
| 方法 | メトロノームに合わせて指揮を振り、検出拍数と期待拍数を比較 |
| 必要機材 | 指揮者ノード 1 台 |
| ログ | `[N1 EVT BEAT] no=... bpm=...` |
| 判定 | `検出拍数 / (BPM × 秒数 / 60) >= 0.90` |

テスト手順:
1. スマホ等でメトロノームを BPM 120 に設定
2. メトロノームに合わせて 60 秒間指揮を振る
3. `--expected-bpm 120 --test-duration 60` で解析

### MOP2: 音階の誤差 (平均 < 3.6 cent)

**シリアルログでは自動計測不可。以下の手動テスト手順で実施する。**

| 項目 | 内容 |
|---|---|
| 方法 | Processing の音声出力を録音し周波数分析 |
| 必要機材 | 楽器ノード 1 台 + PC (Processing) |
| 判定 | 録音した音の基本周波数と理論音高の cent 差の平均 < 3.6 |

テスト手順:
1. 楽器ノードを `SERIAL_DEBUG=0` に戻してビルド・書き込み
2. Processing (`pc_app/production/orchestra_resynth/`) を起動
3. 指揮者を振って演奏を開始
4. PC の音声出力を WAV で録音（macOS: QuickTime Player → 新規オーディオ収録 等）
5. 録音した WAV を音高分析ソフト（Sonic Visualiser 等）で開き、各音の基本周波数を測定
6. 楽譜の MIDI ノート番号から理論周波数を算出: `f = 440 × 2^((note - 69) / 12)`
7. cent 差を計算: `cent = 1200 × log2(f_actual / f_theory)`
8. 全音の平均 cent 差が 3.6 未満なら PASS

### MOP3: 楽譜との相違 (誤ノート発音数 0)

| 項目 | 内容 |
|---|---|
| 方法 | NOTE_ON の noteNumber を楽譜 (score_data.cpp) と突合 |
| 必要機材 | 楽器ノード 1 台以上 (SERIAL_DEBUG=1) |
| ログ | `[N2 NOTE_ON ] part=... note=... vel=... dur=...` |
| 判定 | 送出された noteNumber が期待値と一致すれば PASS |

### MOP4: 楽器間同期誤差 (<= 20 ms) — MOP_TEST ビルド + 専用スクリプト

| 項目 | 内容 |
|---|---|
| 方法 | 楽器の**発火箇所**が出すデバイス側計測ログ `M45F` の localMasterMs (発火時点の推定マスタ時刻) を beatNo で突合し、ノード間レンジ (max−min) を同期誤差とする |
| 必要機材 | 楽器ノード 2 台以上 (**MOP_TEST=4 ビルド**) + 指揮者 (通常ビルドのまま) |
| ログ | `M45F,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>` |
| 集計 | `python3 scripts/mop4_sync_error.py logs/test_XXXX.log` → 平均/p50/p95/最大と 20ms 超過率 |
| 判定 | 最大レンジ <= 20ms |
| 注意 | USB 受信時刻は判定に**使わない** (旧 NOTE_ON PC タイムスタンプ方式は到着ジッタ ~20ms で廃止。経緯: `results/MOP45_latency_investigation_20260710.md`) |

具体的な再計測手順は後述「MOP4/MOP5 の再計測手順」を参照。

### MOP5: 発音予約の遅刻 lateMs (発火 p95 <= 30 ms) — MOP_TEST ビルド + 専用スクリプト

計画書の MOP5「指揮→楽器 通信遅延 ≤30ms」(絶対片道遅延) は片方向の時計同期
(EMA が平均遅延を吸収) では原理的に計測できないため、検証可能な指標
「BEAT が beatLookahead (45ms) の発音予約に間に合っているか」に再定義した。
絶対片道遅延の実測 (GPIO トグル + ロジックアナライザ / 往復 ping-ACK 同期) は将来課題。

| 項目 | 内容 |
|---|---|
| 方法 | BEAT 受信時 (`M45R`) と発火時 (`M45F`) の `lateMs = max(0, localMasterMs − playAtMasterMs)` を集計 |
| 必要機材 | 楽器ノード 1 台以上 (**MOP_TEST=5 ビルド**。=4 と同一ログなのでどちらでも可) + 指揮者 |
| ログ | `M45R,...` (受信時) / `M45F,...` (発火時)。1 拍 1 行ずつ (旧 M5I の二重記録は解消済み) |
| 集計 | `python3 scripts/mop5_comm_delay.py logs/test_XXXX.log` → 受信/発火の遅刻率・lateMs 分布・lookahead 45ms に対する系統シフト |
| 判定 | 発火 lateMs の p95 <= 30ms (`--threshold` で変更可) |

### MOP4/MOP5 の再計測手順（MOP_TEST ビルド）

MOP4/MOP5 は SERIAL_DEBUG ログではなく **MOP_TEST ビルドの専用ログ (M45R/M45F)** で計測する。
MOP_TEST=4 と =5 は同一のログを出すため、**1 回の計測で MOP4/MOP5 の両方を集計できる**。

```bash
# 1. ビルドフラグを付けて楽器ノード (node_02〜06) を書き込み
#    platformio.ini は編集不要 (環境変数が build_flags に追記される)。
#    SERIAL_DEBUG の値はどちらでもよい (集計は行中の M45 行だけを正規表現で拾う)。
#    指揮者 node_01 は通常ビルドのまま書き換え不要。
for n in 02 03 04 05 06; do
  PLATFORMIO_BUILD_FLAGS="-DMOP_TEST=4" pio run -d firmware/production/node_$n -t upload
done

# 2. 楽器ノードを全部 PC に USB 接続してログ収集を開始
cd tools/verification
python3 scripts/serial_logger.py     # Ctrl+C で停止

# 3. 指揮者を振って 60 秒以上演奏する (定常テンポ。例: メトロノーム 120 BPM)

# 4. 集計 (同じログから両方出せる)
python3 scripts/mop4_sync_error.py logs/test_YYYYMMDD_HHMMSS.log
python3 scripts/mop5_comm_delay.py logs/test_YYYYMMDD_HHMMSS.log

# 5. グラフ生成 (results/mopN/ の最新 CSV を読む)
python3 scripts/mop_graphs.py --mop 4 5

# 6. 計測が終わったらフラグなしで再ビルド・書き込みして通常動作に戻す
for n in 02 03 04 05 06; do
  pio run -d firmware/production/node_$n -t upload
done
```

補足:
- ログ形式: 受信時 `M45R,<partId>,<beatNo>,<playAtMasterMs>,<deviceMs>,<offsetMs>,<localMasterMs>`、
  発火時 `M45F,...` (同一フィールド)。localMasterMs = deviceMs + offsetMs。
- 出力レート: 1 拍あたり 2 行 × 約 55 バイト (120 BPM で ~220 B/s/ノード)。
  115200 bps に対し十分小さく、シリアル帯域は圧迫しない。
- MOP_TEST > 0 では NOTE バイナリ送出が止まるため Processing 連携 (発音) は不可。
- 集計スクリプトはライブ計測を持たない (旧ライブ計測は逐次ポーリングで
  タイムスタンプが破綻していたため廃止)。必ず serial_logger.py のログを渡す。

### MOP6: テンポ追従の遅延 (<= 2 拍)

| 項目 | 内容 |
|---|---|
| 方法 | 指揮者の BPM 変化後、楽器の CTRL 受信 BPM が追従するまでの拍数 |
| 必要機材 | 指揮者 + 楽器 1 台以上 |
| ログ | `[N1 EVT BEAT] ... bpm=...` / `[N2 EVT CTRL] bpm=...` |
| 判定 | 追従拍数 <= 2 |

テスト手順: 演奏中にテンポを急に変える（例: 100→140 BPM）。

### MOP7: 起動時間 (<= 5 s)

| 項目 | 内容 |
|---|---|
| 方法 | boot メッセージから演奏可能状態までの時間 |
| 必要機材 | 全ノード |
| ログ | `=== node_XX ... boot ===` → `EVT WIFI connected=1` → `EVT BEAT` |
| 判定 | 最大起動時間 <= 5 秒 |

テスト手順: ログ収集を開始してからノードの電源を入れる。

### MOP8: CPU 負荷 入力フェーズ (<= 2 ms)

| 項目 | 内容 |
|---|---|
| 方法 | 3 フェーズの micros() 計測 |
| 必要機材 | 検証用ファーム (`firmware/` 参照) |
| ログ | `[N? PERF] in=<us> logic=<us> out=<us> total=<us>` |
| 判定 | 入力フェーズ最大値 <= 2000 μs |

テスト手順: `firmware/README.md` の手順に従って検証用 main.cpp を一時的に差し替える。

### MOP9: パケットロス耐性 (ロス <= 5%)

| 項目 | 内容 |
|---|---|
| 方法 | 楽器の EVT BEAT の beatNo 連続性を検査 |
| 必要機材 | 指揮者 + 楽器 1 台以上 |
| ログ | `[N2 EVT BEAT] no=... seq=...` |
| 判定 | beatNo の欠番率 <= 5% |
| 注意 | beatRedundancy=4 のため 4 連送すべて落ちた場合のみ欠番 |

## 出力例

```
ログエントリ数: 12345

============================================================
MOP1: 拍検出の正確性 (正解率 >= 90%)
============================================================
  検出拍数:     118
  計測区間:     60.2 秒
  平均拍間隔:   510.2 ms
  検出 BPM:     117.6
  拍間隔 SD:    28.3 ms  (CV 5.5%)
  期待拍数:     120 (BPM=120, 60s)
  検出率:       98.3%
  判定: PASS

...

============================================================
判定サマリ
============================================================
  MOP1: PASS
  MOP2: N/A
  MOP3: PASS
  MOP4: PASS
  MOP5: PASS
  MOP6: PASS
  MOP7: PASS
  MOP8: N/A
  MOP9: PASS

  PASS=7  FAIL=0  N/A=2
```

## グラフ生成（発表用）

計測済み CSV からグラフを生成する:

```bash
cd tools/verification
source .venv/bin/activate
# または .venv/bin/python scripts/mop_graphs.py で直接実行

# 全 MOP のグラフを生成
python scripts/mop_graphs.py

# 個別指定
python scripts/mop_graphs.py --mop 1 4 8
```

`results/graphs/` に各 MOP の PNG が出力される。
各グラフには目標値ライン（赤破線）と PASS/FAIL 判定がタイトルに表示される。

## 制約・注意事項

- `SERIAL_DEBUG=1` と `SERIAL_DEBUG=0` は排他。NOTE バイナリ送出と
  テキストログは同時に出せない (`MOP_TEST>0` でも NOTE バイナリは止まる)
- MOP4/MOP5 はデバイス側計測 (M45R/M45F) なので USB シリアル遅延は乗らない。
  ただし推定マスタ時刻は EMA オフセット依存であり、絶対片道遅延
  (計画書 MOP5 の本来の定義) は片方向同期では測れない。GPIO トグル +
  ロジックアナライザ等の外部計測が将来課題。
  analyze.py の MOP4/MOP5 は USB 受信時刻ベースの参考値で、正式判定には使わない
- 楽譜突合 (MOP3) は production の「かえるのうた」(32 拍) をハードコード。
  楽譜を変えた場合は `analyze.py` の `EXPECTED_SCORE` を更新する
- ドラムノード (node_06) は MOP3 の楽譜突合対象外
