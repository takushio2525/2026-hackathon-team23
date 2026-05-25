---
title: NoteSenderModule — NOTE を USB シリアルで PC に送る
description: 楽器ノードの発音指示を 20 B の NotePacket に組み立てて Processing アプリへ流すモジュール。バイナリ / デバッグの 2 モード切替
sidebar:
  label: 楽器 — NoteSenderModule
  order: 9
---

:::note[この章で分かること]
- なぜ NOTE は UDP ではなく USB シリアルで送るのか
- `SERIAL_DEBUG=0` のときバイナリ NotePacket、`=1` のとき人間可読ログ、と切り替わる仕組み
- `Serial.flush()` を毎回呼ばないと発音が「バースト化」する USB CDC の罠
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/node_02/lib/NoteSenderModule/NoteSenderModule.h` | 42 | Config / Data / クラス宣言 |
| `firmware/test_v2/node_02/lib/NoteSenderModule/NoteSenderModule.cpp` | 75 | バイナリ送信 + デバッグ切替実装 |

楽器ノード（Arduino UNO R4 WiFi）専用の **出力モジュール**。node_03 / node_04 にも同じファイル。

## 役割と責務

| 観点 | 内容 |
|---|---|
| **出力責務** | `data.noteOut.pendingOn = true` のとき NotePacket (20 B) を組み立てて Serial に書く |
| **書くフィールド** | `data.noteSender.noteSeq / lastSentMs`, `data.noteOut.pendingOn = false` (クリア) |
| **読むフィールド** | `data.noteOut.pendingOn / noteNumber / velocity / durationMs` |
| **境界** | 発音タイミングの判断は `applyPattern()` の責務。このモジュールは「pendingOn が立った瞬間に Serial に書く」だけ |

## なぜ UDP ではなく USB シリアルか

楽器ノードから PC への発音指示には **USB シリアル** を使う。UDP を使わない理由：

| 観点 | UDP | USB シリアル |
|---|---|---|
| 遅延 | 1〜5 ms（WiFi 経由） | < 1 ms（直結） |
| 信頼性 | パケットロスあり | ほぼ確実 |
| 帯域 | 数 Mbps | 数 Mbps（CDC） |
| PC 側の受信実装 | UDP ソケット listen | Serial ポートを開く |
| 配線 | WiFi のみ | USB ケーブル |

ハッカソン会場では：
- PC は楽器ノード 3 台と USB ケーブルで接続済み（電源供給も兼ねる）
- WiFi はマイコン間通信用に閉じておきたい（PC が AP に繋ぐと干渉）
- 発音指示の **絶対的な低遅延** が体感を決める

USB シリアルなら追加のネットワーク設定が要らず、低遅延で確実。

## NoteSenderConfig

```cpp
struct NoteSenderConfig {
    uint32_t baudRate;     // 115200
    uint8_t  partId;       // 0x02-0x04
    uint8_t  instrumentId; // 0..N-1
};
```

### 設定値（`ProjectConfig.h` の例: node_02）

```cpp
inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/     115200,
    /*partId=*/       0x02,
    /*instrumentId=*/ 0,
};
```

### `baudRate = 115200` の根拠

USB CDC では物理的なボーレートは無視される（USB の転送速度が支配的）。ただし
Arduino API では `Serial.begin(baud)` が必要で、値は両端（マイコン / PC）で揃える慣習。

115200 bps は組み込みデバイスのデフォルト。Processing 側も `new Serial(this, port, 115200)` で
合わせる。

### `partId` と `instrumentId` の使い分け

- `partId` (0x02-0x04): **物理ノード識別**。輪唱のどの声部か
- `instrumentId` (0..N-1): **音色識別**。PC 側 `pc_app/test_v2/orchestra_resynth/data/` 配下の JSON をファイル名昇順で配列化した、その index を指す（ファイル名先頭の `0_`, `1_` は人間用の慣例で、ファイル名自体が `<id>.json` ではない）

両者を独立して持つことで：
- `partId` だけ変えて「同じ楽器を別声部に割り当てる」運用ができる
- `instrumentId` だけ変えて「同じ声部の音色だけ差し替える」運用ができる

ハッカソン本番では `partId = instrumentId + 2` のような単純対応で運用しているが、
将来の拡張性のために分けてある。

## NoteOutData / NoteSenderData

```cpp
struct NoteOutData {
    bool     pendingOn = false;
    uint8_t  noteNumber = 0;
    uint8_t  velocity = 0;
    uint16_t durationMs = 0;
};

struct NoteSenderData {
    uint32_t noteSeq = 0;
    uint32_t lastSentMs = 0;
};
```

### NoteOutData — 「発音予約」コマンド

`applyPattern()` がここを更新する：

```cpp
data.noteOut.noteNumber = ev.noteNumber;
data.noteOut.velocity   = (uint8_t)v;
data.noteOut.durationMs = durMs;
data.noteOut.pendingOn  = true;   // ← トリガ
```

`pendingOn = true` で「次の出力フェーズで NOTE を吐け」というシグナル。

### NoteSenderData — 送信統計

| フィールド | 意味 |
|---|---|
| `noteSeq` | これまでに送った NOTE の累計（ヘッダの `seq` として使う） |
| `lastSentMs` | 直近送信時刻（診断ログ用） |

### NoteOff を送らない理由

`pendingOn` だけで `pendingOff` がないのは設計判断：

> 消音は Processing 側が NotePacket.durationMs から自動消音するため、ここでは noteIsSounding 等の追跡は不要。

楽器ノードは「いつ消すか」を一切気にしない。Processing が `durationMs` + ADSR Release を
タイマで管理して勝手に音を切る。これにより：
- マイコン側のメモリ状態が大幅に減る
- 「鳴ってる音のリスト」を持たなくていい
- ボイスプールの管理は Processing に集約

トレードオフ：明示的な NoteOff コマンドが送れない。「途中で強制消音」が必要なら別途
プロトコル拡張が要る。現状の輪唱用途では不要。

## init() — Serial のセットアップ

```cpp
bool NoteSenderModule::init() {
#if SERIAL_DEBUG
    // main.cpp 側で Serial.begin() / ホスト待機を済ませているので何もしない。
#else
    Serial.begin(cfg_.baudRate);
#endif
    return true;
}
```

### 2 つの初期化パス

`SERIAL_DEBUG` の値で挙動が変わる：

| `SERIAL_DEBUG` | 何が起きるか |
|---|---|
| 1 | `main.cpp::setup()` で `DBG_BEGIN(115200)` → `DBG_WAIT_HOST(1500)` を実行済み。ここは何もしない |
| 0 | `main.cpp` の `DBG_BEGIN` は `(void)0` に展開されるので、ここで `Serial.begin()` を呼ぶ |

これにより：
- デバッグビルド（`SERIAL_DEBUG=1`）では起動時にホスト接続待ち（ログ取りこぼし防止）
- リリースビルド（`SERIAL_DEBUG=0`）ではホスト待機なしですぐに動き始める

## updateOutput() — 発音予約を実行

```cpp
void NoteSenderModule::updateOutput(SystemData& data) {
    const uint32_t now = millis();
    if (data.noteOut.pendingOn) {
        const uint32_t seq = ++data.noteSender.noteSeq;
#if SERIAL_DEBUG
        (void)seq;
        DBG_PRINTF("[N2 NOTE_ON ] part=0x%02X instr=%u note=%u vel=%u dur=%u seq=%lu t=%lu\n",
                   (unsigned)cfg_.partId,
                   (unsigned)cfg_.instrumentId,
                   (unsigned)data.noteOut.noteNumber,
                   (unsigned)data.noteOut.velocity,
                   (unsigned)data.noteOut.durationMs,
                   (unsigned long)seq,
                   (unsigned long)now);
#else
        buildAndSend(cfg_.partId, cfg_.instrumentId, /*gate=*/1, seq, now, data.noteOut);
#endif
        data.noteSender.lastSentMs = now;
        data.noteOut.pendingOn = false;
    }
}
```

### 1 ループでやること

1. **トリガ判定**: `pendingOn = true` でなければ何もしない
2. **シーケンス番号進める**: `++noteSeq` で前置インクリメント
3. **モード分岐**: `SERIAL_DEBUG` で人間可読出力 or バイナリ出力
4. **統計更新**: `lastSentMs = now`
5. **`pendingOn` クリア**: 同じイベントで 2 回送らない

### デバッグ出力モード（`SERIAL_DEBUG=1`）

```cpp
DBG_PRINTF("[N2 NOTE_ON ] part=0x%02X instr=%u note=%u vel=%u dur=%u seq=%lu t=%lu\n",
           (unsigned)cfg_.partId,
           (unsigned)cfg_.instrumentId,
           ...);
```

人間可読の 1 行ログを `pio device monitor` に流す。例：

```
[N2 NOTE_ON ] part=0x02 instr=0 note=60 vel=64 dur=500 seq=1 t=12345
[N2 NOTE_ON ] part=0x02 instr=0 note=62 vel=64 dur=500 seq=2 t=12845
```

このとき **NotePacket バイナリは流れない**。Processing 連携は停止する（テキストとバイナリが
混ざらないため）。

### バイナリ送信モード（`SERIAL_DEBUG=0`）

```cpp
buildAndSend(cfg_.partId, cfg_.instrumentId, /*gate=*/1, seq, now, data.noteOut);
```

`buildAndSend()` の中身：

```cpp
void buildAndSend(uint8_t partId, uint8_t instrumentId, uint8_t gate,
                  uint32_t seq, uint32_t now, const NoteOutData& out) {
    orc::NotePacket pkt{};
    pkt.header.magic        = orc::MAGIC;
    pkt.header.version      = orc::PROTOCOL_VERSION;
    pkt.header.type         = orc::PKT_NOTE;
    pkt.header.seq          = seq;
    pkt.header.timestampMs  = now;
    pkt.payload.partId      = partId;
    pkt.payload.noteNumber  = out.noteNumber;
    pkt.payload.velocity    = out.velocity;
    pkt.payload.gate        = gate;
    pkt.payload.durationMs  = out.durationMs;
    pkt.payload.instrumentId = instrumentId;
    pkt.payload.reserved    = 0;
    Serial.write(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt));
    Serial.flush();
}
```

- 20 B の NotePacket を組み立て
- `Serial.write()` で **生バイト列をそのまま** 書く（テキスト変換なし）
- **`Serial.flush()` を必ず呼ぶ**（後述）

`#if !SERIAL_DEBUG` で囲まれているので、`SERIAL_DEBUG=1` のときはこの関数自体が
コンパイルされず存在しない（リンク時に無駄なコードが残らない）。

## `Serial.flush()` の重要性

```cpp
Serial.write(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt));
Serial.flush();
```

`Serial.flush()` は **内部送信バッファを今すぐ吐き出す** API。これを呼ばないと：

### USB CDC のバッファリング挙動

UNO R4 WiFi の USB CDC は、効率のため **小さい書き込みを内部バッファで束ねる**。

```
write(20 B) → 内部バッファに溜まる (まだ送らない)
write(20 B) → 内部バッファに溜まる (まだ送らない)
write(20 B) → 内部バッファに溜まる (まだ送らない)
...
60 B 溜まったら一気に送る (USB バルク転送効率最大化)
```

これは大量データ転送には良いが、**リアルタイム発音には致命的**：
- NoteOn 3 個が同時に到達して Processing が「バースト発音」する
- 拍と発音が同期しなくなる

### `flush()` で即座に送る

```cpp
Serial.flush();
```

`flush()` を呼ぶと、内部バッファをすぐに USB バス上に押し出す：

```
write(20 B) → 内部バッファ
flush()     → USB バルク転送開始 → PC へ
                                  ↓ (~1 ms 後)
                                  Processing が NoteOn 受信 → 発音
```

これにより 1 拍 1 ノートが個別に届き、発音タイミングが揃う。

`flush()` のコストは USB CDC で ~50 μs 程度。20 ノート/秒で 1 ms/秒 程度のオーバーヘッドなので
実用上問題ない。

## 「明示的に gate=1 を渡す」設計

```cpp
buildAndSend(cfg_.partId, cfg_.instrumentId, /*gate=*/1, seq, now, data.noteOut);
```

`gate=1` を **ハードコード** で渡している。これは：
- 現状 NoteOff を送らないので常に 1
- 将来 NoteOff を送るなら `buildAndSend(..., /*gate=*/0, ...)` で呼べる
- 「gate の意味をここに残しておく」意図表示

`gate` 引数を取らなくても動くが、引数として明示することで「将来拡張ポイント」を
コード自体で示している。

## 落とし穴

- **`SERIAL_DEBUG=1` でビルドすると音が出ない**: Processing は NotePacket を期待しているが
  人間可読テキストが流れてくる。本番ビルドは必ず `SERIAL_DEBUG=0`。
- **`Serial.flush()` を呼ばないと発音がバーストする**: USB CDC の罠。小さい書き込みは
  まとめられる。
- **`Serial.write(uint8_t*, len)` を使う**: `Serial.print(uint8_t)` は ASCII 数字に変換するので
  バイナリ送信には使えない。
- **`reinterpret_cast<const uint8_t*>(&pkt)` のアライメント**: `NotePacket` は `#pragma pack(1)` で
  パックされているので、ポインタキャストで 1 B アライメントアクセスが許される（一部のアーキで
  alignment fault が出る恐れがあるが、Renesas RA4M1 / Xtensa では問題なし）。
- **`partId` と `instrumentId` を取り違えると別の音色が鳴る**: 設定ファイル整備時に注意。
- **Processing 側のシリアルバッファサイズ**: 受信側もバッファを十分大きく取らないと
  20 B 単位で切れずに崩れる。Processing の `Serial.buffer()` を使うか、bytesAvailable で
  毎フレーム掃く。

## 関連ページ

- NotePacket の定義 → [OrcProtocol](/firmware/orc-protocol/)
- 発音指示を生成する側 → [main フロー（楽器）](/firmware/main-instrument/)
- 楽譜から音符を引く仕組み → [楽譜進行ロジック](/deep-dive/score-progression/)
- PC 側の受信処理 → [pc_app の歩き方](/code/pc-app/) / [加算合成エンジン](/deep-dive/additive-synthesis/)
