# MOE/MOP 検証プログラム

計画書 表 1.4「MOE と MOP の対応関係および目標値」全 9 項目を 1 台の PC で検証するツール。

## 構成

```
tools/verification/
├── README.md              ← このファイル
├── requirements.txt       ← Python 依存 (pyserial)
├── logs/                  ← ログ保存先
├── scripts/
│   ├── serial_logger.py   ← 複数ポート同時ログ収集
│   └── analyze.py         ← 全 9 項目 PASS/FAIL 判定
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

### MOP4: 楽器間同期誤差 (<= 20 ms)

| 項目 | 内容 |
|---|---|
| 方法 | 複数楽器の NOTE_ON の PC 側タイムスタンプ差を比較 |
| 必要機材 | 楽器ノード 2 台以上 (SERIAL_DEBUG=1) + 指揮者 |
| ログ | `[N? NOTE_ON ] ... t=...` |
| 判定 | 同時発音クラスタの最大時間差 <= 20ms |
| 注意 | USB シリアル遅延 (~1-3ms) を含む近似値 |

### MOP5: 指揮→楽器 通信遅延 (<= 30 ms)

| 項目 | 内容 |
|---|---|
| 方法 | 同一 beatNo の EVT BEAT の PC 受信時刻差 (指揮者 vs 楽器) |
| 必要機材 | 指揮者 + 楽器 1 台以上 |
| ログ | `[N1 EVT BEAT] no=...` / `[N2 EVT BEAT] no=...` |
| 判定 | 最大遅延 <= 30ms |
| 注意 | USB シリアル遅延の差分 (~1-3ms) を含む近似値 |

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

## 制約・注意事項

- `SERIAL_DEBUG=1` と `SERIAL_DEBUG=0` は排他。NOTE バイナリ送出と
  テキストログは同時に出せない
- MOP4/MOP5 の計測値には USB シリアル遅延 (~1-3ms) が含まれる。
  WiFi 遅延のみを厳密に測るにはオシロスコープ等の外部計測が必要
- 楽譜突合 (MOP3) は production の「かえるのうた」(32 拍) をハードコード。
  楽譜を変えた場合は `analyze.py` の `EXPECTED_SCORE` を更新する
- ドラムノード (node_06) は MOP3 の楽譜突合対象外
