---
title: 通信プロトコル（UDP）
description: CTRL / BEAT / NOTE 各 20 B パケットの仕様
sidebar:
  order: 3
---

:::note[この章で分かること]
- 何が UDP、何が USB Serial で流れているか
- パケットのバイトレイアウト（20 B 固定）
- なぜ独自プロトコルにしたか
:::

:::tip[読了目安]
**約 7 分**。前提: UDP / マルチキャストの基本概念。
:::

## 全体像

| 区間 | 経路 | 種別 | 周期 |
|---|---|---|---|
| 指揮者 → 楽器 | UDP マルチキャスト | CTRL | 50 ms（20 Hz） |
| 指揮者 → 楽器 | UDP マルチキャスト | BEAT | 拍ごと（2 連送） |
| 楽器 → PC | USB Serial（115200 bps） | NOTE | 発音時 |

ネットワーク設定:

| 項目 | 値 |
|---|---|
| トランスポート | UDP マルチキャスト |
| グループアドレス | `239.0.0.1` |
| ポート | `5001` |
| WiFi モード | SoftAP（指揮者ノードが親機） |
| SSID / pass | `OrchestraAP` / `orchestra2026` |
| WiFi チャネル | 6 |

## なぜ UDP / 独自プロトコル

[ADR-0002](/decisions/0002-udp-original-protocol/) より:

- TCP の再送遅延は許容できない（拍が遅れたら全部崩れる）
- 順序保証より低遅延が重要
- 1 対多配信が必要（マルチキャストが自然）
- パケット内容を自分たちで設計したい（同期や表現を自由に乗せる）

## パケット共通ヘッダ（12 B）

すべてのパケットは固定長 20 B で、先頭 12 B が共通ヘッダ：

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 0 | 2 B | `magic` | `0x4F52`（'OR' = "ORchestra"） |
| 2 | 1 B | `version` | プロトコルバージョン（現行 `0x01`） |
| 3 | 1 B | `type` | `0x01=CTRL`, `0x02=BEAT`, `0x03=NOTE` |
| 4 | 4 B | `seq` | 送信側で単調増加するシーケンス番号（型ごとに独立） |
| 8 | 4 B | `timestampMs` | 送信側の `millis()`（指揮者時計） |

### `magic` の使い方

受信側はまず `magic == 0x4F52` をチェックして、本プロトコルのパケットかを判定する。
シリアルでバイナリを受け取る PC 側もこれでフレーミングする。

### `seq` の使い方

- パケロス検知: 前回受信した `seq` との差分でロス数が分かる
- 重複検知: 同じ `seq` が来たら無視（BEAT 2 連送の片方が遅れて届いたケース）

### `timestampMs` の使い方

- 楽器側で「指揮者の時刻」が分かる
- 受信時刻と `timestampMs` の差を EMA で平滑化して、自時計のオフセットを推定
- 詳しくは [同期戦略](/architecture/sync/) 参照

## CTRL パケット（type=0x01）

指揮者 → 楽器、**20 Hz で常時配信**。

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 2 B | `bpmQ8` | BPM × 8 整数（分解能 0.125 BPM。例: 100.0 BPM → 800、120.5 BPM → 964）。フィールド名に `Q8` を含むが、一般的な Q8 固定小数（×256）ではない |
| 14 | 1 B | `velocity` | 0–127（強弱。ストレッチ未実装時は固定 64） |
| 15 | 1 B | `state` | `0=Idle`, `1=Calibrating`, `2=Conducting`, `3=Fallback` |
| 16 | 4 B | `reserved` | 0 埋め（将来拡張） |

### なぜ常時配信するのか

- BEAT が落ちても、次の CTRL ですぐ BPM・状態が補填される
- 楽器側は CTRL の `timestampMs` で時刻オフセット推定を継続できる
- 楽器側で「指揮者が生きているか」を 50 ms 単位で監視できる

### BPM の整数表現（×8）

`uint16_t` で BPM を扱うため、**8 倍した整数** で送る。フィールド名 `bpmQ8` の
`Q8` は「一般的な Q8 固定小数（×256）」ではない点に注意（命名の歴史的経緯）。

- 例: 100.0 BPM → `800`、120.5 BPM → `964`
- 送信側: `bpmQ8 = (uint16_t)(bpm * 8.0f + 0.5f)`（`OrcSenderModule.cpp`）
- 受信側: `bpm = bpmQ8 / 8.0f`（`OrcReceiverModule.cpp`）
- 0.125 BPM 単位で表現できる。40 BPM 〜 240 BPM の範囲は `320`〜`1920` に収まる

## BEAT パケット（type=0x02）

指揮者 → 楽器、**拍ごとに 2 連送**。

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 2 B | `beatNo` | 拍番号（0 オリジン、巻き戻しなしの単調増加） |
| 14 | 2 B | `reserved` | 0 埋め |
| 16 | 4 B | `playAtMasterMs` | 楽器が発音する目標時刻（指揮者時計） |

### `playAtMasterMs` の効果

指揮者が拍を発火した瞬間に BEAT を投げると、ネットワーク遅延（数 ms）の分だけ
楽器の発音が遅れる。これを防ぐため、指揮者は次の式で先読みする：

```
playAtMasterMs = (指揮者時計の現在時刻) + 50 ms
```

楽器側は受信後、自時計に変換した上で「`playAtMasterMs` に該当する自時計時刻」まで
ビジー待ちして発音する。50 ms の余裕がネットワーク遅延を吸収するバッファとして働く。

### なぜ 2 連送なのか

- BEAT 1 つでも落ちると 1 拍ぶん演奏が抜ける（致命的）
- マルチキャスト UDP は再送がないので、冗長化で対処
- 受信側は `beatNo` の重複を見て 2 通目を捨てる
- 2 連送のオーバーヘッドは 20 B × 2 = 40 B / 拍 ＝ 軽微

## NOTE パケット（type=0x03）

楽器 → PC、**USB Serial で発音時に送る**。

| オフセット | サイズ | フィールド | 内容 |
|---|---|---|---|
| 12 | 1 B | `partId` | ノード ID。test_v2 は `0x02`〜`0x04`（楽器 3 台）、production 想定は `0x02`〜`0x05`（楽器 4 台）。輪唱のどの声部か |
| 13 | 1 B | `noteNumber` | MIDI ノート番号（0–127、60=C4） |
| 14 | 1 B | `velocity` | 0–127 |
| 15 | 1 B | `gate` | `1=NoteOn`、`0=NoteOff`（test_v2 は常に `1`、消音は PC 側が `durationMs` から自動） |
| 16 | 2 B | `durationMs` | 発音時間（ミリ秒） |
| 18 | 1 B | `instrumentId` | 音色 ID（`data/*.json` の何番目か）。test_v2 で追加（旧 `reserved` 領域に充当） |
| 19 | 1 B | `reserved` | 0 埋め |

> ⚠️ test_v1 のドキュメントでは「先頭が `midiNote`」と書かれていたが、test_v2 実装で
> ヘッダ直後に `partId` を置く順序へ変更されている（`OrcProtocol.h::NotePayload`）。
> パース時のオフセットを誤らないよう注意する。

### なぜ UDP ではなく USB Serial?

- PC を WiFi につながなくていい（運用が楽）
- 楽器ノードは UDP 受信に集中、PC 送信は安定した USB Serial
- ノイズや遅延が WiFi より小さい

### `instrumentId` の役割

test_v2 で追加された 1 バイト（旧 `reserved[0]` に置換）。
PC 側 `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` は
`pc_app/test_v2/orchestra_resynth/data/` 配下の JSON を **ファイル名昇順** で配列化し、
`instrumentId` を **その配列の index** として参照して加算合成する。

- 実体（2026-05 時点）: `0_organ.json` / `1_flute.json` / `2_bell.json` / `3_flute_tweaked.json`
  → `instrumentId = 0,1,2,3` の順に対応
- 新しい音色を増やすには、`pc_app/test_v2/orchestra_resynth/data/` に JSON を追加する
  （`sound_lab/` で試作した JSON を完成後にコピーする運用）
- ファイル名先頭の数字（`0_`, `1_`）は人間が並び順を把握するための慣例で、
  ファイル名そのものが `<id>.json` の形式というわけではない

## パケット定義の場所

実装は `firmware/test_v2/common/lib/OrcProtocol/` 配下：

- `OrcProtocol.h` — 構造体定義（`CtrlPacket`、`BeatPacket`、`NotePacket`）
- `OrcProtocol.cpp` — シリアライズ／デシリアライズ

変更時は本ページと `.agent/api.md` を同時に更新する。

## バージョン管理

`version` バイトを 1 ずつ上げる。互換性のない変更があった場合、
受信側は `version != 0x01` を見たらパケットを捨てる。

| バージョン | 主な変更 |
|---|---|
| `0x01` | 初版。test_v2 で NOTE に `instrumentId` を追加 |

## パケロス・ジッタへの対処

| 想定問題 | 対処 |
|---|---|
| BEAT 単発ロス | 2 連送で 1 つは届く |
| CTRL 単発ロス | 50 ms 後の次の CTRL で復帰 |
| 連続ロス（>10 パケット） | 楽器が `Fallback` 状態に入り、LED で警告 |
| ジッタ（受信タイミングのばらつき） | `playAtMasterMs` 先読み 50 ms で吸収 |
| 楽器の WiFi 切断 | `reconnectIntervalMs = 2000` で自動再接続 |

## 次に読むべきページ

- 拍検出と時刻同期の中身 → [同期戦略](/architecture/sync/)
- 楽譜データの形式 → [楽譜フォーマット](/architecture/score/)
- PC 側の合成 → [pc_app の歩き方](/code/pc-app/)

### さらに深掘りしたい

- なぜ UDP マルチキャスト / SoftAP / `239.0.0.1` か → [UDP マルチキャスト](/deep-dive/udp-multicast/)
- 20 B 固定パケットのバイトレイアウト・エンディアン → [バイナリパケット](/deep-dive/binary-packet/)
