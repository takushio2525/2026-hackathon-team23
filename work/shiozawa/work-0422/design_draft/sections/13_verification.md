# 13. 検証・妥当性確認

本章は第 4.3 章で定義した MOP を実際に測るための試験計画と、要求 → 検証の対応表を示す。
単体 → 結合 → システムの 3 段階で段階的に検証する。

## 13.1 単体テスト方針

PlatformIO の `test/` ディレクトリを使い、**共通層と `applyPattern()` を中心に**
ユニットテストを書く。各ノードの `lib/` 側（H/W ドライバ）は最低限（「ビルドが通る」
「ヘッダの整合が取れている」程度）とする。

EMA に従い、判断ロジックは `IModule` 派生クラスではなく `applyPattern(SystemData&)`
関数として実装するため、テストでは **`SystemData` をテスト側で組み立てて
`applyPattern()` を呼ぶだけ**でロジック単体を検証できる。

| 対象 | テスト内容 | 手段 |
|---|---|---|
| `ModuleTimer`（共通層） | `setTime()` 後、所定 ms 経過で `getNowTime()` が閾値を超える | `millis()` をモック差し替え |
| `OrcProtocol` シリアライズ（共通層） | CTRL / BEAT / NOTE を書き込み → バッファから読み直すと一致 | バイト列ラウンドトリップ |
| `applyPattern()` の拍検出（node_01） | あらかじめ記録した `data.imu.acc` 時系列（CSV から読む）を流し、`data.beat.event` の発火位置が期待通り | ゴールデンテスト |
| `applyPattern()` のテンポ推定（node_01） | `data.beat.event` を一定間隔で発火させると、`data.tempo.bpm` が期待値に収束 | 単調列テスト |
| `applyPattern()` の楽譜進行（node_02〜05） | `data.receiver.lastBeatNo` を増やすと `data.noteOut.pendingOn` が期待順序で立つ | 状態機械テスト |
| `applyPattern()` の SelfRun 遷移（node_02〜05） | `data.receiver.lastBeatReceivedMs` を進めずに時間を経過させると `state == SelfRun` に遷移し、仮想 BEAT で進行する | 状態機械テスト |

**モジュール設計上の工夫**:

- EMA の `IModule` は `init()` / `updateInput(SystemData&)` / `updateOutput(SystemData&)`
  という形でフェーズ毎に `SystemData&` を受けるので、テストからは **偽の `SystemData`
  を渡すだけ**でモジュール単体を呼べる（Config はコンストラクタで注入済み）
- ハードウェア依存（I2C、UDP）は `ImuModule` と `OrcNetModule` に局在化しているので、
  それ以外のロジック（`applyPattern()`）は **Arduino 依存なし**でホスト側テストが可能

## 13.2 結合テスト方針

段階的に結合する。各段階で「前段階の健全性」が保てていることを確認してから次に進む。

| Tier | 構成 | 確認事項 | 必要機材 |
|---|---|---|---|
| T1 | node_01 単体 | シリアルに `beat_no` / `bpm` がログ出力される。手で振って拍が出る | PC + USB ケーブル |
| T2 | node_01 + node_02 | node_02 が BEAT を受信し、NOTE を（デバッグ受信ツールで）出力している | PC + Processing の簡易受信スクリプト |
| T3 | node_01 + node_02〜05（4 台楽器） | 4 台がほぼ同時に NOTE を出す。同期誤差 ≤ 30 ms（MOP-1） | 4 台分の USB ハブ + ログ集約 |
| T4 | 全ノード + PC Processing | 実際に音が鳴る。指揮速度を変えると BPM が追従する | PC + スピーカ + Processing 本番 |

各 Tier はサブタスク T12, T15, T17, T19（第 7.2 章の WBS）に対応する。

## 13.3 V&V（要求 → 検証対応表）

必達・ストレッチの各要求が、どの MOP・テストで検証されるかを紐づける。

| 要求 ID | 要求内容 | 検証方法 | 関連 MOP |
|---|---|---|---|
| R-1 | 5 台同期演奏 | T4 で聴感確認 + MOP-1 / MOP-2 の実測 | MOP-1, MOP-2 |
| R-2 | 輪唱曲（主旋律 3 + リズム 1 以上） | 楽譜データを 4 パートぶん用意し、T4 で演奏 | —（機能要件） |
| R-3 | 可変テンポ追従 | 指揮 BPM を階段状に変化させ、MOP-4 を実測 | MOP-4 |
| R-4（ストレッチ） | 強弱制御 | 指揮振幅を変化させ、NOTE の velocity を観測（MOP-8） | MOP-8 |
| R-5（ストレッチ） | エンタメ要素 | 実装時に別途設計（本書対象外） | — |
| R-Internal-1 | 通信の信頼性 | MOP-5（5% パケロスで演奏継続） | MOP-5 |
| R-Internal-2 | CPU リソース | MOP-6（入力フェーズ ≤ 2 ms） | MOP-6 |
| R-Internal-3 | 起動時間 | MOP-7（5 s 以内） | MOP-7 |

## 13.4 TPM（試験実施計画）

各試験を「項目・目標・手順・合否・時期」で定義する。

| Test ID | 項目 | 目標（MOP） | 計測機材・手順 | 合否基準 | 時期 |
|---|---|---|---|---|---|
| TP-1 | 拍検出精度 | MOP-3: ≥ 90% | メトロノーム 80/120/160 BPM に合わせて指揮し、検出数 vs 実拍数を 30 秒ぶん比較 | ≥ 90% | W6（M3） |
| TP-2 | 通信遅延 | MOP-2: ≤ 10 ms | node_01 送信時刻（`timestamp_ms`）と node_02 受信時刻の差を 100 サンプル平均 | 平均 ≤ 10 ms | W7（M4） |
| TP-3 | 同期誤差 | MOP-1: ≤ 30 ms | 4 ノードのシリアルログを PC で時刻同期して BEAT 受信時刻を比較 | 最大差 ≤ 30 ms | W9（M5） |
| TP-4 | テンポ追従 | MOP-4: ≤ 2 拍 | 80 BPM → 120 BPM に切り替えた際、楽器側 BPM が 120 に入るまでの拍数 | ≤ 2 拍 | W9（M5） |
| TP-5 | パケロス耐性 | MOP-5 | ルータ側で擬似 5% パケロスを設定、演奏が破綻しないことを聴感確認 | 聴感破綻なし | W11（M7） |
| TP-6 | CPU 負荷 | MOP-6: ≤ 2 ms | `micros()` で入力フェーズ所要時間を 10 分ログ取得 | 最大 ≤ 2 ms | W11（M7） |
| TP-7 | 起動時間 | MOP-7: ≤ 5 s | 電源投入 → 最初の CTRL 送出までを計測、5 回平均 | ≤ 5 s | W11（M7） |
| TP-8 | 強弱制御（ストレッチ） | MOP-8 | 小・中・大の振り幅それぞれで velocity 出力値を記録 | 3 段階分離 | W10（M6） |
