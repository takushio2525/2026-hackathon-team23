---
title: OrcSenderModule — CTRL と BEAT を組み立てる
description: applyPattern() の判断結果を 20 B のパケットに梱包して送信予約する出力モジュール。BEAT 冗長送信と CTRL 周期送信の両立
sidebar:
  label: 指揮者 — OrcSenderModule
  order: 7
---

:::note[この章で分かること]
- イベント駆動の BEAT と周期駆動の CTRL を 1 つの `updateOutput()` で扱う設計
- `playAtMasterMs = masterNow + lookahead` で先読み時刻を載せる仕掛け
- `bpmQ8` への変換ロジックと、シーケンス番号の進め方
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/node_01/lib/OrcSenderModule/OrcSenderModule.h` | 36 | Config / Data / クラス宣言 |
| `firmware/test_v2/node_01/lib/OrcSenderModule/OrcSenderModule.cpp` | 58 | CTRL/BEAT 組み立てロジック |

指揮者ノード専用の **出力モジュール**。`updateInput()` は持たない。

## 役割と責務

| 観点 | 内容 |
|---|---|
| **出力責務** | BEAT パケット（イベント駆動）と CTRL パケット（周期駆動）の組み立て + 送信予約 |
| **書くフィールド** | `data.orcNet.pendingCtrl / pendingBeat / pendingBeatRedundancy`, `data.sender.ctrlSeq / beatSeq`, `data.beat.playAtMasterMs`, `data.beat.event = false`（クリア） |
| **読むフィールド** | `data.beat.event / beatNo`, `data.tempo.bpm / velocity`, `data.conductor.state` |
| **境界** | 「拍を検出した」「テンポを推定した」という判断は `applyPattern()` の仕事。このモジュールは結果を **パケットに変換するだけ** |

## OrcSenderConfig

```cpp
struct OrcSenderConfig {
    uint32_t ctrlIntervalMs;   // 50 ms = 20 Hz
    uint8_t  beatRedundancy;   // 同一 BEAT を何発まで連送するか (1-8 を実用域として想定)
    uint16_t beatLookaheadMs;  // playAtMasterMs = masterNow + lookahead
};
```

### 設定値（`ProjectConfig.h`）

```cpp
inline const OrcSenderConfig ORC_SENDER_CONFIG = {
    /*ctrlIntervalMs=*/  50,   // 20 Hz
    /*beatRedundancy=*/  4,    // BEAT を 4 連送 (旧 2 だが ESP32-S3 SoftAP の radio ロス対策で増やした暫定値・2026-05-25)
    /*beatLookaheadMs=*/ 50,   // playAtMasterMs = masterNow + 50 ms
};
```

> ⚠️ **2026-05-25 時点の暫定設定**: ESP32-S3 SoftAP で BEAT パケットロスが多発した件の
> 切り分け中。`beatRedundancy = 2 → 4` に増やし、連送間隔は `OrcNetConfig.beatGapMs`
> （別フィールド）で挿入する設計。実機計測で確定値が出たら 2 連送に戻すか 4 を据え置く。

### `ctrlIntervalMs = 50` の根拠（20 Hz CTRL）

CTRL は「現在のテンポと状態」を常時配信する **ハートビート** 兼テンポ更新。

20 Hz の根拠：
- 楽器側の **時計同期 EMA** が CTRL の `timestampMs` を使う。20 Hz サンプルで EMA が
  数秒以内に十分収束する
- BPM 60〜200 の範囲なら CTRL 1 周期で「次の拍までに 1〜数回 CTRL が届く」確率が高い
- WiFi UDP は数 kHz でも余裕で送れるが、楽器側の処理コストとのバランスで 20 Hz が妥当

50 ms より遅くすると：時計同期が遅延、楽器側の `data.ctrl.bpm` が古くなる。
50 ms より速くすると：帯域の無駄、楽器側の処理オーバーヘッドが増える。

### `beatRedundancy` の根拠（BEAT 連送）

BEAT はイベント駆動でロスすると **次の拍まで楽器が無音** になる。

連送なら（独立ロス確率 p のとき）：
- 2 連送: 両方ロスする確率は p²。p = 5% で p² = 0.25%
- 4 連送: p⁴。p = 5% で 0.00063%
- 帯域影響は微小（拍ごとに 40 B × 連送数）

当初は 2 連送で十分という見立てだったが、**2026-05-25 に ESP32-S3 SoftAP で
連続ロスが観測された** ため、`beatRedundancy = 4` に増量。radio が「同一状態で
連発するとロスする」癖が疑われたため、追加で `OrcNetConfig.beatGapMs` を 0 → 1〜5 ms
に設定して連送間隔を空ける運用を検討中（現状は `beatGapMs = 0` で切り分け継続）。

確定値は実機計測（受信ロス率 vs 平均遅延の trade-off）で決定する。確定後に本節を
書き直す予定。

### `beatLookaheadMs = 50` の根拠（先読み 50 ms）

`playAtMasterMs = masterNow + 50` として、**50 ms 先の時刻** を発音目標として配信する。

50 ms の選定：
- UDP 往復が通常 1〜5 ms 程度（同一 SoftAP 内）
- 楽器側の最悪受信遅延が ~20 ms 程度
- 余裕を見て 50 ms あれば、ほぼ全パケットが「目標時刻より前に」着く
- 大きくしすぎると体感的に「振りから音まで遅れる」と感じられる（人間が許容する遅延は ~100 ms）

50 ms は **正確さと体感即時性のバランス点**。

## OrcSenderData

```cpp
struct OrcSenderData {
    uint32_t ctrlSeq = 0;
    uint32_t beatSeq = 0;
    uint32_t lastCtrlSentMs = 0;
};
```

シーケンス番号と最終送信時刻のミニマムな状態。CTRL/BEAT それぞれ独立に番号付ける。

### シーケンス番号の意味

- `ctrlSeq`: CTRL 送信のたびに `++ctrlSeq`。楽器側が「同じ CTRL を 2 回受け取った」のを
  検出するために使う（ただし CTRL は冪等なので重複処理しても問題ない）
- `beatSeq`: BEAT 送信のたびに `++beatSeq`。2 連送する場合は **同じ `beatSeq`** で 2 回送る

`beatNo`（楽譜上の拍番号、`uint16_t`）と `beatSeq`（送信回数、`uint32_t`）は別物。

## init() — タイマ初期化のみ

```cpp
bool init() override {
    ctrlTimer_.setTime();
    return true;
}
```

`ModuleTimer ctrlTimer_` を「今を基準にゼロ」に設定するだけ。失敗しないので常に true。

`ctrlTimer_` は `OrcSenderModule` がメンバとして持つ `ModuleTimer` 1 個。
これで CTRL の周期送信を実現する。

## updateOutput() — 1 ループでやること

```cpp
void OrcSenderModule::updateOutput(SystemData& data) {
    const uint32_t masterNow = millis();

    // ── BEAT 送信予約 (イベント駆動) ──
    if (data.beat.event) {
        orc::BeatPacket pkt{};
        pkt.header.magic       = orc::MAGIC;
        pkt.header.version     = orc::PROTOCOL_VERSION;
        pkt.header.type        = orc::PKT_BEAT;
        pkt.header.seq         = ++data.sender.beatSeq;
        pkt.header.timestampMs = masterNow;
        pkt.payload.beatNo         = data.beat.beatNo;
        pkt.payload.reserved[0]    = 0;
        pkt.payload.reserved[1]    = 0;
        pkt.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;

        data.beat.playAtMasterMs = pkt.payload.playAtMasterMs;
        data.orcNet.pendingBeat  = pkt;
        data.orcNet.pendingBeatRedundancy = cfg_.beatRedundancy;
        data.orcNet.hasPendingBeat = true;

        data.beat.event = false;   // event を読み取り後にクリア
    }

    // ── CTRL 送信予約 (周期駆動) ──
    if (ctrlTimer_.getNowTime() >= cfg_.ctrlIntervalMs) {
        ctrlTimer_.setTime();
        orc::CtrlPacket pkt{};
        pkt.header.magic       = orc::MAGIC;
        pkt.header.version     = orc::PROTOCOL_VERSION;
        pkt.header.type        = orc::PKT_CTRL;
        pkt.header.seq         = ++data.sender.ctrlSeq;
        pkt.header.timestampMs = masterNow;

        float bpm = data.tempo.bpm;
        if (bpm < 0)    bpm = 0;
        if (bpm > 8000) bpm = 8000;
        pkt.payload.bpmQ8    = (uint16_t)(bpm * 8.0f + 0.5f);
        pkt.payload.velocity = data.tempo.velocity;
        pkt.payload.state    = (uint8_t)data.conductor.state;
        for (uint8_t i = 0; i < 4; ++i) pkt.payload.reserved[i] = 0;

        data.orcNet.pendingCtrl    = pkt;
        data.orcNet.hasPendingCtrl = true;
        data.sender.lastCtrlSentMs = masterNow;
    }
}
```

このモジュールの **核心がこの 1 関数** に詰まっている。順に分解する。

### BEAT 送信予約

#### トリガ条件

```cpp
if (data.beat.event) {
```

`applyPattern()` が拍を検出した周期で `data.beat.event = true` をセットしている。
**1 周期だけ true になるエッジフラグ**。読み取り後にクリアする：

```cpp
data.beat.event = false;   // event を読み取り後にクリア
```

これにより同じ拍を 2 回送信することはない（ただし `beatRedundancy` で同一パケットを
2 回送ることはある）。

#### ヘッダ組み立て

```cpp
orc::BeatPacket pkt{};
pkt.header.magic       = orc::MAGIC;
pkt.header.version     = orc::PROTOCOL_VERSION;
pkt.header.type        = orc::PKT_BEAT;
pkt.header.seq         = ++data.sender.beatSeq;
pkt.header.timestampMs = masterNow;
```

- `orc::BeatPacket pkt{}`: **値初期化** ですべてのフィールドを 0 で埋める（`reserved` を
  明示的に 0 にする保険）
- `magic = 0x4F52` / `version = 0x01` / `type = PKT_BEAT (= 2)`: プロトコル定数
- `seq = ++beatSeq`: 前置インクリメントで番号を進めてからコピー（最初の BEAT は 1）
- `timestampMs = masterNow`: **送信時の指揮者時計**（楽器側の時計同期 EMA で使う）

#### ペイロード組み立て

```cpp
pkt.payload.beatNo         = data.beat.beatNo;
pkt.payload.reserved[0]    = 0;
pkt.payload.reserved[1]    = 0;
pkt.payload.playAtMasterMs = masterNow + cfg_.beatLookaheadMs;
```

- `beatNo`: `applyPattern()` が `data.beat.beatNo += 1` で更新した楽譜上の拍番号
- `reserved`: 値初期化で 0 だが明示的に 0 を書く（メンテナンス時の意図表示）
- `playAtMasterMs = masterNow + 50`: **50 ms 先の時刻** を載せる

#### `data.beat.playAtMasterMs` の同期更新

```cpp
data.beat.playAtMasterMs = pkt.payload.playAtMasterMs;
```

`SystemData` 側にも同じ値をミラーしておく。ログ出力や別モジュールから参照可能にするため。

#### OrcNetModule への送信予約

```cpp
data.orcNet.pendingBeat  = pkt;
data.orcNet.pendingBeatRedundancy = cfg_.beatRedundancy;
data.orcNet.hasPendingBeat = true;
```

完成したパケットを `pendingBeat` に積み、`pendingBeatRedundancy = 2`（連送回数）を指定し、
`hasPendingBeat = true` でフラグ立て。

これにより次に呼ばれる `OrcNetModule::updateOutput()` でパケットが UDP に流される。
モジュール間の通信は **すべて SystemData 経由** という EMA 規約を厳守。

### CTRL 送信予約

#### 周期判定

```cpp
if (ctrlTimer_.getNowTime() >= cfg_.ctrlIntervalMs) {
    ctrlTimer_.setTime();
```

`ctrlTimer_` の経過時間が 50 ms を超えたら：
1. `getNowTime()` がしきい値超え判定
2. `setTime()` でタイマをリセット（次の 50 ms カウント開始）

これにより **50 ms ごとに 1 回だけ** CTRL が送信される。

#### ヘッダ

BEAT と同じパターン。`type = PKT_CTRL (= 1)`, `seq = ++ctrlSeq`, `timestampMs = masterNow`。

#### BPM の Q8 エンコード

```cpp
float bpm = data.tempo.bpm;
if (bpm < 0)    bpm = 0;
if (bpm > 8000) bpm = 8000;
pkt.payload.bpmQ8 = (uint16_t)(bpm * 8.0f + 0.5f);
```

3 ステップ：

1. **負の値クランプ**: `bpm < 0` は物理的にありえないが防御的に 0 に
2. **オーバーフロー防止クランプ**: `bpm > 8000` → `bpm * 8 > 64000` で `uint16_t` の上限
   65535 を超える可能性。実際は BPM 40〜240 範囲だが、`applyPattern()` のバグや CTRL の
   不正な値を遮断するための保険
3. **Q8 変換 + 四捨五入**: `(bpm * 8.0f + 0.5f)` で半分加算してから `uint16_t` キャスト
   （切り捨てが四捨五入になる）

例：
- bpm = 120.5 → `bpm * 8 = 964.0` → `bpmQ8 = 964`
- bpm = 100.4375 → `bpm * 8 + 0.5 = 803.75` → `bpmQ8 = 803`
- bpm = 100.4376 → `bpm * 8 + 0.5 = 803.8008` → `bpmQ8 = 803`

楽器側のデコードは `bpmQ8 / 8.0f` で復元できる。

#### velocity と state

```cpp
pkt.payload.velocity = data.tempo.velocity;
pkt.payload.state    = (uint8_t)data.conductor.state;
```

- `velocity`: 現在の強弱（0–127、ストレッチ未実装で固定 64）
- `state`: `ConductorState` enum を `uint8_t` にキャスト

`state` を送ることで、楽器側は「指揮者が今キャリブ中か演奏中か Fallback か」を知れる
（現状演奏判断には使っていないが、将来「Fallback で楽器も停止」などの拡張点）。

#### reserved の明示的ゼロクリア

```cpp
for (uint8_t i = 0; i < 4; ++i) pkt.payload.reserved[i] = 0;
```

`pkt{}` の値初期化で既に 0 になっているが、明示的に 0 を書く。将来 `reserved` を
拡張フィールドに使うとき、「ここに 0 が入る」という意図がコードに残る。

#### 送信予約

```cpp
data.orcNet.pendingCtrl    = pkt;
data.orcNet.hasPendingCtrl = true;
data.sender.lastCtrlSentMs = masterNow;
```

`hasPendingCtrl` で `OrcNetModule` にフラグを立て、`lastCtrlSentMs` を更新（診断ログ用）。

CTRL は冗長送信しない（20 Hz で常時更新されるので 1 パケットロスは即補填される）。

## なぜ BEAT と CTRL を 1 つのモジュールにまとめたか

別案として「OrcCtrlSenderModule」「OrcBeatSenderModule」と分ける設計もありえる。
1 モジュールにまとめた理由：

- どちらも **指揮者の判断結果をパケットに変換するだけ**で本質的に同じ責務
- 共有する内部状態が少ない（ヘッダ組み立てパターンが同じ）
- 分けると `OrcSenderData` を共有する仕掛けが必要で複雑化

ただし将来「BEAT だけ別ノードに移したい」という拡張が来たら分割する余地はある。

## イベント駆動 vs 周期駆動の使い分け

| パケット | 駆動方式 | 理由 |
|---|---|---|
| BEAT | イベント駆動 (`data.beat.event`) | 拍検出は不規則なイベントなので、検出時に即送信する |
| CTRL | 周期駆動 (`ctrlTimer_`) | テンポは連続的に変化するので、20 Hz で更新を流し続ける |

両方を 1 ループで処理することで、**イベントと周期が干渉せず** 動く。BEAT 直後に CTRL も
周期が来ていれば、同じ `updateOutput()` 内で両方送信予約される（`OrcNetModule` 側で
順に送出される）。

## 落とし穴

- **`data.beat.event` をクリアし忘れると 1 拍で永遠に BEAT を送り続ける**。読み取り後に
  `false` に戻すこと。
- **`++beatSeq` を後置インクリメントにすると最初の BEAT が `seq=0` で送られる**。前置
  インクリメントで最初が `seq=1` になるよう揃える。
- **`bpmQ8` の四捨五入を忘れると累積誤差が出る**。`(uint16_t)(bpm * 8.0f)` だけだと
  切り捨てで bias がかかる。`+ 0.5f` を必ず付ける。
- **`playAtMasterMs` の計算で `masterNow + 50` がオーバーフローする心配は？** → `uint32_t` の
  範囲なら 49.7 日まで安全。`masterNow = 4294967295` 付近で `+ 50` してもラップアラウンドで
  自然に小さい値になり、楽器側の `(int32_t)diff` 計算で正しく扱える。

## 関連ページ

- パケットを実際に UDP に流す側 → [OrcNetModule](/firmware/orc-net/)
- パケット構造の詳細 → [OrcProtocol](/firmware/orc-protocol/)
- 拍検出の中身 → [拍検出アルゴリズム](/deep-dive/beat-detection/)
- main フロー全体 → [main フロー（指揮者）](/firmware/main-conductor/)
