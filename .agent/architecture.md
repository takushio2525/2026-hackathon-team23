# アーキテクチャ — Arduino オーケストラ

Embedded-Module-Architecture（以下 **EMA**）を全面採用し、4〜6 台のマイコン
（指揮者 1 ＋ 楽器 3〜5）と PC アプリ（Processing）を UDP マルチキャストで結合する。

- **test_v2（現行・推奨）**: 指揮者 1 + 楽器 3（`node_02〜04`）の 4 台構成。きらきら星 3 声輪唱で稼働中。
- **production（本番想定）**: 指揮者 1 + 楽器 5（`node_02〜06`、金管 4 ＋ ドラム 1）の
  6 台構成（ADR-0004 改訂版）。現状は雛形のみで、`firmware/production/` 配下には
  `node_01〜05` の 5 フォルダが存在し、**最終形に必要な `node_06` フォルダはこれから作成**。

## システム全体像

```
[指揮者ノード node_01]                    [楽器ノード node_02〜04]              [PC]
  XIAO ESP32-S3 Sense                       Arduino UNO R4 WiFi                  Processing 4
  + GY-521 (MPU6050)                                                             orchestra_resynth.pde
   │                                          │                                   │
   │  CTRL (20 Hz, BPM/velocity)              │                                   │
   │  BEAT (拍ごと、playAtMasterMs)            │                                   │
   ├──────────────────────────────────────────┤                                   │
   │  UDP マルチキャスト 239.0.0.1:5001         │                                   │
   │  WiFi SoftAP: OrchestraAP/orchestra2026   │                                   │
   │                                          │  NOTE (発音、instrumentId 付き)    │
   │                                          ├──── USB シリアル (115200) ───────►│
   │                                          │                                   │
```

- **指揮者**: IMU で振りを検出 → 拍とテンポを推定 → CTRL/BEAT を UDP で全ノードへ配信
- **楽器**: BEAT を受け取り、自分の楽譜位置の音符を `instrumentId` 付き NOTE として PC に送る
- **PC**: 各楽器からの NOTE を `pc_app/test_v2/orchestra_resynth/data/*.json` の音色定義で加算合成 → スピーカ
  （`sound_lab/` は音色を分析・試作する実験場。完成した JSON を `pc_app/.../data/` にコピーして使う）

詳しい役割分担は `docs/` の「アーキテクチャ > 全体図」を参照。
このファイルは AI が実装で迷ったときに開く、要点と前提条件の集約。

## Embedded-Module-Architecture（EMA）

リファレンス: <https://github.com/takushio2525/Embedded-Module-Architecture>

### 3 フェーズループ

```cpp
void loop() {
    // ① 入力フェーズ: 外界からデータを取り込む
    for (auto* m : gInputs)  if (m->enabled) m->updateInput(gData);
    // ② ロジックフェーズ: SystemData だけを見て状態を更新
    applyPattern(gData);
    // ③ 出力フェーズ: SystemData を外界に反映
    for (auto* m : gOutputs) if (m->enabled) m->updateOutput(gData);
}
```

- 入力モジュールは `updateInput(SystemData&)` のみ
- 出力モジュールは `updateOutput(SystemData&)` のみ
- ロジック（`applyPattern.cpp`）は `SystemData` のフィールドだけを読み書き
- **モジュール同士の直接呼び出しは禁止**。通信は必ず `SystemData` 経由

### 主要パターン

| パターン | 役割 | 実体 |
|---|---|---|
| `IModule` | 抽象基底（`init` / `updateInput` / `updateOutput` / `deinit`） | `firmware/test_v2/common/lib/ModuleCore/IModule.h` |
| `SystemData` | ノード内モジュール間で共有する状態を 1 構造体に集約 | 各 node の `include/SystemData.h` |
| `ProjectConfig` | ピン配置・定数・閾値などノード固有設定の一元化 | 各 node の `include/ProjectConfig.h` |
| `ModuleTimer` | 周期実行・非ブロッキング | `ModuleCore` ライブラリ内 |

### 共通層（`firmware/test_v2/common/lib/`）

各ノードの `platformio.ini` から `lib_extra_dirs = ../common/lib` で参照する。

| ライブラリ | 内容 |
|---|---|
| `ModuleCore/` | `IModule` 抽象基底 + `ModuleTimer` |
| `OrcProtocol/` | CTRL/BEAT/NOTE の 20 B パケット定義（`magic=0x4F52`） |
| `OrcNetModule/` | WiFi UDP マルチキャスト送受信 |
| `StatusLedModule/` | 状態に応じた LED 点滅出力 |
| `SerialDebug/` | `SERIAL_DEBUG` マクロで切替えるシリアルデバッグ |

test_v1 にも同じ構成の `firmware/test_v1/common/lib/` がある（バージョンごとに独立）。

## 3 段階開発（test_v1 → test_v2 → production）

| 段階 | 目的 | 状態 | 推奨度 |
|---|---|---|---|
| `firmware/test_v1/` | 最初の同期検証。C major 圏の和音を拍で鳴らして遅延を聞き分ける | 完了（参照用に残置） | × |
| `firmware/test_v2/` | きらきら星の輪唱（3 声部）。NOTE に `instrumentId` を載せ PC で音色切替 | **現行・積極開発中** | ◎ |
| `firmware/production/` | 本番想定の素テンプレ。EMA 未適用 | 雛形のみ | △ |

**新しい変更は基本 test_v2 に入れる**。production への取り込みは結合検証後。

## 各ノードの責務

### 指揮者ノード（`firmware/test_v2/node_01/`）

- ハードウェア: **XIAO ESP32-S3 Sense + GY-521（MPU6050）**
- 役割: IMU から振りを検出 → 拍検出 → テンポ推定 → CTRL/BEAT を 5001/UDP に配信
- 状態機械: `Idle → Calibrating（2 s）→ Conducting → (IMU タイムアウト) → Fallback`
- 主要モジュール: `ImuModule` / `OrcNetModule` / `OrcSenderModule` / `StatusLedModule`
- ロジック: `src/applyPattern.cpp`（拍検出ゲート、BPM EMA、CTRL/BEAT 生成）

### 楽器ノード（`firmware/test_v2/node_02〜04/`）

- ハードウェア: **Arduino UNO R4 WiFi**
- 役割: 指揮者の BEAT を受信 → `score_data.cpp` から自パートの音符を取得 → NOTE を PC に送信（USB Serial）
- 輪唱の頭ずらし: `ProjectConfig.h` の `headRestBeats` で 0 / 8 / 16 拍ずれて入る
- `instrumentId`: PC 側 `pc_app/test_v2/orchestra_resynth/data/*.json` を**ファイル名昇順**で配列化したときの index（2026-05 時点は 0=オルガン / 1=フルート / 2=ベル / 3=フルート調整版）。JSON を増やせば対応関係も増える
- ロジック: `src/applyPattern.cpp`（拍 → 楽譜位置 → NOTE 生成）

### PC アプリ（`pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde`）

- フレームワーク: **Processing 4**
- 役割: 各楽器ノードからの NOTE を USB シリアルで受信 → `pc_app/test_v2/orchestra_resynth/data/` 配下の倍音定義 JSON を **ファイル名昇順ソート** で読み、`instrumentId` を index として参照して加算合成 → スピーカ
- ADSR エンベロープで自然な発音
- 複数音同時発音をサポート（声部 3 並列）

## 同期戦略

### マスタクロック

- **指揮者の `millis()` が基準**。CTRL/BEAT のヘッダ `timestampMs` で配信
- 楽器側は受信時刻と `timestampMs` から指揮者時刻のオフセットを EMA で推定
  → 「指揮者時計で時刻 T に発音」という指示を自時計に変換

### `playAtMasterMs` 先読み

- 指揮者が BEAT を発射する際、`playAtMasterMs = masterNow + beatLookaheadMs` を載せる
- 楽器側はこの時刻まで待ってから NOTE を吐くので、ネットワーク遅延が吸収される
- `beatLookaheadMs` のデフォルトは 50 ms（`ProjectConfig.h` の `OrcSenderConfig`）

### 同期目標（MOP）

| 指標 | 目標 | 出典 |
|---|---|---|
| MOP-1: 楽器間同期誤差 | ≤ 20 ms | ADR-0006（`docs/decisions/0006-sync-error-moe-20ms.md`） |
| MOP-2: 通信遅延 | ≤ 10 ms | 同上 |

### パケロス対策

- BEAT は同一内容を連送（`beatRedundancy = 4`、2026-05-25 暫定値・旧 2 から ESP32-S3 SoftAP のロス対策で増量）
- CTRL は 20 Hz で常時更新されているため 1 パケットロスは即座に補填
- BEAT 番号（`beatNo`）の不連続で取りこぼしを検知

## 拍検出ロジック（指揮者）

`firmware/test_v2/node_01/src/applyPattern.cpp` 抜粋。要点だけ：

1. IMU 加速度に LPF（α=0.10）
2. 動加速度ノルム `dynNorm = |a_lpf| − gravityMag`（重力差し引き）
3. `dynNorm > 1.20 g` で Armed 突入
4. Armed 中の積分経路長 `pathLenM` が `0.20 m` 到達で **拍発火**
5. 不応期 350 ms（≒ 170 BPM 上限）
6. リリース判定（停止 or ピークの 40% 以下、40 ms 連続）→ Idle に戻る
7. 拍間隔から BPM を EMA（α=0.30）で更新

実装変更時は `ProjectConfig.h` の `logic_params` 名前空間内の定数を調整する。
モジュール本体（`src/*.cpp`）にハードコードしない。

## 楽譜データ

- 配置: `firmware/test_v2/node_0{2,3,4}/src/score_data.cpp`（**3 台同一内容**＝輪唱だから）
- 構造: `score_data.h` に `ScoreEvent { beatAt, noteNumber, velocity, durationQ8, flags, subNote, subVelocity, subOffsetQ8, subDurationQ8 }` 配列。1 ScoreEvent = 1 拍、`durationQ8` は 1/256 拍単位（256=1 拍）、`flags` は bit0=NoteOn / bit2=休符（タイの続きを含む）。`sub*` は細分音符用で、きらきら星では全行 0
- 各ノードは自分の `headRestBeats` 拍ずれた位置から再生開始
- 曲全体の長さで mod 演算 → 途中起動でも「今の拍」から鳴る

## 「実装中に迷ったらここを開く」チェックリスト

- 新しい入力デバイスを足したい → `IModule` を継承して `updateInput()` のみ実装、`SystemData` に出力フィールドを足す
- 新しい出力（LED / アクチュエータ）を足したい → `updateOutput()` のみ実装
- 通信パケット形式を変えたい → @.agent/api.md と `OrcProtocol/` を同期更新
- 拍検出を調整したい → `node_01/include/ProjectConfig.h` の `logic_params` のみ
- ノード固有の閾値・ピンを変えたい → 該当 node の `ProjectConfig.h` だけ
