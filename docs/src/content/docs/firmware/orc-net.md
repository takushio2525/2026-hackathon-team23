---
title: OrcNetModule — WiFi と UDP マルチキャスト
description: SoftAP / Station の切替、UDP マルチキャスト送受信、自動再接続を担当する通信モジュールの内部実装
sidebar:
  label: 共通 — OrcNetModule
  order: 3
---

:::note[この章で分かること]
- 指揮者（SoftAP）と楽器（Station）で同じモジュールがどう動作分岐するか
- `updateInput()` で受信、`updateOutput()` で送信、という入出力フェーズ両方に登場する仕組み
- マルチキャストグループ参加に失敗した場合のフォールバック挙動
- 受信バッファのサイズ検証とノイズパケット破棄の流儀
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/common/lib/OrcNetModule/OrcNetModule.h` | 76 | クラス定義 + Config / Data 構造体 |
| `firmware/test_v2/common/lib/OrcNetModule/OrcNetModule.cpp` | 138 | 接続 / 受信ループ / 送信ループ実装 |

このモジュールは **入力フェーズと出力フェーズの両方に登場する** 唯一のモジュール。
受信は `updateInput()`、送信は `updateOutput()` でフェーズが分かれている。

## 役割と責務

| 観点 | 内容 |
|---|---|
| **入力責務** | UDP ソケットを poll し、20 B のパケットを `OrcNetData::lastCtrl / lastBeat` に書き込む |
| **出力責務** | `pendingCtrl / pendingBeat` を読み、UDP マルチキャストで送信する |
| **接続維持** | Station モードのみ、切断検出で `reconnectIntervalMs` ごとに再接続を試みる |

「パケットの組み立て」はやらない。CTRL の組み立ては `OrcSenderModule` の仕事、
BEAT の組み立ても同じ。OrcNetModule は **完成品の `CtrlPacket` を受け取って送る** だけ。

## OrcNetConfig

```cpp
enum class WifiMode : uint8_t {
    SoftAp,  // 自身が AP を起動する側 (node_01)
    Sta,     // 既存 SoftAP に接続する側 (楽器ノード: test_v2 は node_02-04 / production 想定は node_02-05)
};

struct OrcNetConfig {
    WifiMode    mode;
    const char* ssid;
    const char* pass;
    IPAddress   multicastIp;
    uint16_t    udpPort;
    uint8_t     channel;              // SoftAp 時のみ参照
    uint32_t    reconnectIntervalMs;
};
```

### 指揮者ノードの設定

```cpp
inline const OrcNetConfig ORC_NET_CONFIG = {
    /*mode=*/                WifiMode::SoftAp,
    /*ssid=*/                "OrchestraAP",
    /*pass=*/                "orchestra2026",
    /*multicastIp=*/         IPAddress(239, 0, 0, 1),
    /*udpPort=*/             5001,
    /*channel=*/             6,        // 2.4 GHz CH6 を使う
    /*reconnectIntervalMs=*/ 2000,     // SoftAP 側は使わない
};
```

### 楽器ノードの設定

```cpp
inline const OrcNetConfig ORC_NET_CONFIG = {
    /*mode=*/                WifiMode::Sta,
    /*ssid=*/                "OrchestraAP",        // 指揮者と同じ
    /*pass=*/                "orchestra2026",
    /*multicastIp=*/         IPAddress(239, 0, 0, 1),
    /*udpPort=*/             5001,
    /*channel=*/             6,
    /*reconnectIntervalMs=*/ 2000,
};
```

### マルチキャストアドレスとポートの選定

- `239.0.0.1`: **管理者範囲** （Administratively Scoped）のマルチキャスト。プライベートな
  ローカルネットワーク内で自由に使ってよいレンジ（RFC 2365）。ルーティングされず、外に漏れない。
- `5001`: 1024 以上で予約のないポート。IANA 未割当だが衝突可能性は実用上ゼロ。

## OrcNetData

```cpp
struct OrcNetData {
    // 受信側 (他モジュールが読む)
    bool wifiConnected = false;
    bool hasNewCtrl = false;
    bool hasNewBeat = false;
    orc::CtrlPacket lastCtrl{};
    orc::BeatPacket lastBeat{};

    // 送信側 (送信したいモジュールが書く)
    bool hasPendingCtrl = false;
    orc::CtrlPacket pendingCtrl{};
    bool hasPendingBeat = false;
    orc::BeatPacket pendingBeat{};
    uint8_t pendingBeatRedundancy = 1;
};
```

このデータ構造が **受信用フィールドと送信用フィールドを 1 つに統合** している。
名前付けで方向が分かるように設計してある：

| フィールド | 書く側 | 読む側 |
|---|---|---|
| `wifiConnected` | OrcNetModule | applyPattern (状態判定) |
| `hasNewCtrl / lastCtrl` | OrcNetModule | OrcReceiverModule |
| `hasNewBeat / lastBeat` | OrcNetModule | OrcReceiverModule |
| `hasPendingCtrl / pendingCtrl` | OrcSenderModule | OrcNetModule |
| `hasPendingBeat / pendingBeat` | OrcSenderModule | OrcNetModule |
| `pendingBeatRedundancy` | OrcSenderModule | OrcNetModule |

「has〇〇」フラグは **1 周期だけ true** になるエッジ通知。読み取った側がクリアする責任を持つ。
たとえば `OrcSenderModule` が `hasPendingBeat = true` にした次の `updateOutput()` 呼び出しで
`OrcNetModule::flushSend()` が送信した直後に `hasPendingBeat = false` に戻す。

## init() — 接続セットアップ

```cpp
bool OrcNetModule::init() {
    bool ok = (cfg_.mode == WifiMode::SoftAp) ? startSoftAp() : connectSta();
    if (ok) started_ = true;
    return ok;
}
```

モードで分岐して、成功時のみ `started_ = true`。失敗時は `enabled = false` で
無効化されたままループに入る。

### SoftAP モード（指揮者）

```cpp
bool OrcNetModule::startSoftAp() {
#if defined(ARDUINO_ARCH_ESP32)
    WiFi.mode(WIFI_AP);
    if (!WiFi.softAP(cfg_.ssid, cfg_.pass, cfg_.channel)) {
        return false;
    }
    delay(100);
    if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
        udp_.begin(cfg_.udpPort);
    }
    return true;
#else
    return false;   // ESP32 以外では SoftAp 不可
#endif
}
```

ポイント：

- `WiFi.mode(WIFI_AP)` で AP モードに遷移
- `softAP()` で SSID / Pass / Channel を指定して起動
- `delay(100)` は AP 起動を確実にするための小休止（経験的に必要）
- **`beginMulticast` 失敗時はユニキャスト `udp_.begin()` にフォールバック**
  - SoftAP 側は送信が主目的だが、自身からのパケット受信ループバック確認のため受信も開ける
- ESP32 以外のアーキ（UNO R4 など）では即 false（指揮者ノードは ESP32-S3 限定）

### Station モード（楽器）

```cpp
bool OrcNetModule::connectSta() {
#if defined(ARDUINO_ARCH_ESP32)
    WiFi.mode(WIFI_STA);
    WiFi.begin(cfg_.ssid, cfg_.pass);
#else
    WiFi.begin(cfg_.ssid, cfg_.pass);   // UNO R4 は mode() なし
#endif
    uint32_t startMs = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startMs < 8000) {
        delay(100);
    }
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }
    if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
        udp_.begin(cfg_.udpPort);
    }
    return true;
}
```

ポイント：

- 接続待機は **最大 8 秒** まで `WL_CONNECTED` をポーリング
- ESP32 と Arduino UNO R4 WiFi（Renesas）で `WiFi.mode()` の挙動が違うので `#ifdef` で分岐
- マルチキャスト join 失敗時は同じくフォールバック

## updateInput() — 受信処理

```cpp
void OrcNetModule::updateInput(SystemData& data) {
    data.orcNet.hasNewCtrl = false;
    data.orcNet.hasNewBeat = false;

    bool linkUp = isLinkUp();
    data.orcNet.wifiConnected = linkUp;

    // Sta 側のみ自動再接続
    if (cfg_.mode == WifiMode::Sta && !linkUp && started_) {
        uint32_t now = millis();
        if (now - lastReconnectMs_ >= cfg_.reconnectIntervalMs) {
            lastReconnectMs_ = now;
            WiFi.disconnect();
            WiFi.begin(cfg_.ssid, cfg_.pass);
        }
    }

    if (!started_) return;
    pollReceive(data.orcNet);
}
```

### 毎周期の流れ

1. **`hasNewCtrl / hasNewBeat` を false にクリア**
   - これらは 1 周期だけ true になるエッジフラグなので、毎周期頭でリセット
2. **リンク状態を反映**
   - Station モードなら `WiFi.status() == WL_CONNECTED` をチェック
   - SoftAP モードは起動時に `started_ = true` した時点で常時 up 扱い
3. **Station の自動再接続**
   - 切断検出から `reconnectIntervalMs` (2 s) 経過したら `disconnect` → `begin` を再試行
4. **`pollReceive()` を呼んで受信バッファを掃く**

### pollReceive() — UDP 受信ループ

```cpp
void OrcNetModule::pollReceive(OrcNetData& net) {
    int packetSize;
    while ((packetSize = udp_.parsePacket()) > 0) {
        // 不正サイズは破棄 (バッファを読み捨てる)
        if (packetSize != (int)orc::PACKET_SIZE) {
            uint8_t scratch[64];
            int rem = packetSize;
            while (rem > 0) {
                int n = udp_.read(scratch, sizeof(scratch));
                if (n <= 0) break;
                rem -= n;
            }
            continue;
        }
        uint8_t buf[orc::PACKET_SIZE];
        int n = udp_.read(buf, orc::PACKET_SIZE);
        if (n != (int)orc::PACKET_SIZE) continue;

        orc::PacketHeader hdr;
        if (!orc::parseHeader(buf, orc::PACKET_SIZE, hdr)) continue;

        if (hdr.type == orc::PKT_CTRL) {
            memcpy(&net.lastCtrl, buf, sizeof(net.lastCtrl));
            net.hasNewCtrl = true;
        } else if (hdr.type == orc::PKT_BEAT) {
            memcpy(&net.lastBeat, buf, sizeof(net.lastBeat));
            net.hasNewBeat = true;
        }
    }
}
```

### 防御ロジック 4 段階

1. **サイズ ≠ 20 B → 破棄**: 別アプリのパケットや断片化されたものを除外
2. **不正サイズパケットの読み捨て**: バッファに残ったゴミデータをスクラッチバッファで吸い出す
3. **`parseHeader()` 失敗 → 破棄**: MAGIC / version が合わないパケットを除外
4. **type 不一致 → 破棄**: `PKT_NOTE` を楽器側が受信してもどこにも書かれない

`while (parsePacket() > 0)` で **1 周期内に届いた全パケットを処理する**。蓄積を許さない設計。
これにより BEAT の冗長送信（2 連送）が連続到達した場合でも、`lastBeat` には最後のものが残る。
楽器側の `OrcReceiverModule` 側で `beatNo` による重複排除を行う。

## updateOutput() — 送信処理

```cpp
void OrcNetModule::updateOutput(SystemData& data) {
    if (!started_) return;
    flushSend(data.orcNet);
}

void OrcNetModule::flushSend(OrcNetData& net) {
    if (net.hasPendingCtrl) {
        udp_.beginPacket(cfg_.multicastIp, cfg_.udpPort);
        udp_.write(reinterpret_cast<const uint8_t*>(&net.pendingCtrl),
                   sizeof(net.pendingCtrl));
        udp_.endPacket();
        net.hasPendingCtrl = false;
    }
    if (net.hasPendingBeat) {
        uint8_t reps = net.pendingBeatRedundancy ? net.pendingBeatRedundancy : 1;
        for (uint8_t i = 0; i < reps; ++i) {
            udp_.beginPacket(cfg_.multicastIp, cfg_.udpPort);
            udp_.write(reinterpret_cast<const uint8_t*>(&net.pendingBeat),
                       sizeof(net.pendingBeat));
            udp_.endPacket();
        }
        net.hasPendingBeat = false;
    }
}
```

### CTRL の送信

シンプルに 1 発撃つだけ。CTRL は 20 Hz で常時更新されるので、1 パケットロスは即座に
次の CTRL で補填される。再送はしない。

### BEAT の冗長送信

`pendingBeatRedundancy` (デフォルト 2) の回数だけ同じパケットを連送する：

```cpp
for (uint8_t i = 0; i < reps; ++i) {
    udp_.beginPacket(...);
    udp_.write(...);
    udp_.endPacket();
}
```

理由：
- BEAT は **イベント駆動** で、ロスすると次のチャンスまで楽器が無音になる
- 2 連送なら片方ロスしても通る（独立ロス確率を仮定すれば p² まで下がる）
- 楽器側は `beatNo` で重複排除するので、2 回受け取っても発音は 1 回

### 送信フラグの責任

`flushSend()` の最後で `hasPendingCtrl/Beat = false` に戻す。これにより：

- 送信予約 → 送信 → クリア、というサイクルが 1 ループで閉じる
- 次のループで未予約なら何も送らない（消費電力 / 帯域に優しい）
- 「送信予約したのに送られなかった」というバグが構造的に起きない

## isLinkUp() — リンク状態判定

```cpp
bool OrcNetModule::isLinkUp() const {
    if (cfg_.mode == WifiMode::SoftAp) {
        return started_;
    }
    return WiFi.status() == WL_CONNECTED;
}
```

SoftAP 側は「起動できれば常時 up」と見なす。**接続しているクライアントの数は問わない**。
0 台でも 4 台でも `wifiConnected = true`。これにより指揮者は楽器の起動を待たずに
拍検出を始められる（楽器が後から繋がれば、それ以降の BEAT を受信できる）。

Station 側は実際に AP に接続できているかを `WL_CONNECTED` で判定。

## deinit()

```cpp
void OrcNetModule::deinit() {
    udp_.stop();
}
```

UDP ソケットを閉じるだけ。WiFi の切断は行わない（他モジュールが使っているかもしれないため）。

現状 `deinit()` は呼ばれていない（再起動運用）。将来的に「演奏終了時に省電力モードに入る」
拡張のための準備。

## マルチキャストフォールバックの意義

```cpp
if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
    udp_.begin(cfg_.udpPort);   // ユニキャスト/ブロードキャスト受信に降格
}
```

`beginMulticast()` は **IGMP join に失敗** する場合がある：

- Arduino UNO R4 WiFi の `WiFiS3` ライブラリは IGMP 実装が不完全
- ESP32 でも稀に AP 起動直後だと失敗する
- 一部の WiFi スタックでマルチキャストフィルタが厳しい

このとき `udp_.begin()` で **ユニキャストポート** だけ開く。指揮者の送信が
ブロードキャスト的にネットワーク内に流れるので、（実装によっては）受信できる。
完全な保証はないが「マルチキャスト join 失敗 = 完全に死ぬ」を回避する。

## 落とし穴

- **Arduino UNO R4 WiFi では `WiFi.mode(WIFI_STA)` を呼ばない**。Renesas の `WiFiS3` は
  ESP32 と API が違い、`WiFi.mode()` 自体が存在しないので `#ifdef` 分岐が必須。
- **マルチキャスト送信は AP 起動完了直後に行うと飛ばないことがある**。`delay(100)` で
  AP 起動を確実にしてから `beginMulticast` を呼ぶ。
- **同じポート / 同じグループに複数アプリが居ると、互いに自分のパケットも受信する**。
  ループバック（自送→自受）は `MAGIC` チェックでは止まらないので、楽器側で `parseHeader` 後の
  type で破棄する必要がある（PKT_NOTE は楽器→PC 用なので楽器が受信したら無視）。
- **`parsePacket()` を 1 ループに 1 回しか呼ばないと、複数到達したパケットが溜まる**。
  本実装では `while (parsePacket() > 0)` で全部掃く。
- **UDP の MTU は 1500 B**。20 B パケットなので余裕で乗るが、将来ペイロードを増やすときは
  IP 断片化に注意。

## 関連ページ

- パケット定義 → [OrcProtocol](/firmware/orc-protocol/)
- パケットを生成する側 → [OrcSenderModule](/firmware/orc-sender/)
- パケットを処理する側 → [OrcReceiverModule](/firmware/orc-receiver/)
- ネットワークの仕組み深掘り → [UDP マルチキャスト](/deep-dive/udp-multicast/)
