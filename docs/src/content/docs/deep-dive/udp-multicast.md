---
title: UDP マルチキャスト
description: なぜ TCP でなく UDP か、なぜ SoftAP か、マルチキャストアドレスの意味、IGMP の振る舞い、OrcNetModule の実装
sidebar:
  order: 3
---

:::note[この章で分かること]
- マルチキャストは「ユニキャスト」「ブロードキャスト」と何が違うか
- なぜ TCP ではなく UDP マルチキャストか
- 指揮者が SoftAP（親機）、楽器が Sta（子機）になる構成の意義
- 239.0.0.1 という IP アドレスがどういう意味か（IGMP / TTL）
- `OrcNetModule` の送受信実装
:::

:::tip[読了目安]
**約 12 分**。前提: TCP/IP の超基本（IP・ポート・パケットを知っていれば OK）。
:::

実装本体: `firmware/test_v2/common/lib/OrcNetModule/`

## ユニキャスト / ブロードキャスト / マルチキャスト

ネットワーク通信の届け方は 3 種類ある。

| 方式 | 宛先 | 例 | 本プロジェクトでの可否 |
|---|---|---|---|
| **ユニキャスト** | 1 対 1 | TCP / UDP の通常通信 | △ 楽器 N 台分の宛先管理が必要 |
| **ブロードキャスト** | 1 対 全員 | `255.255.255.255` | △ 同じセグメントの無関係な機器も受信 |
| **マルチキャスト** | 1 対 グループ | `224.0.0.0/4` | ◎ 「興味ある機器だけ受信」が自然に書ける |

ハッカソンの構成（指揮者 1 + 楽器 N）では「マルチキャストで CTRL/BEAT を投げ、
聞きたい楽器が join する」のが自然。N が増えても指揮者側のコードが変わらない。

## なぜ TCP ではなく UDP

TCP は **再送と順序保証** をするが、その代償として「届くまで待つ」ことがある。
音楽用途ではこれが致命的：

- 1 拍ぶんのパケットが再送で 50 ms 遅れたら、その拍だけ遅れて鳴る
- 100 ms ジッタは「リズム崩壊」として体感できる

UDP は **届かないものは届かない** を受け入れる代わりに、低レイテンシ。
本プロジェクトは：

- BEAT は **2 連送** することで単発ロスに耐える
- CTRL は **20 Hz で常時更新** されるので 1 つ落ちても 50 ms 後に復帰する
- 落ちて困るのは BEAT だけで、それは 2 連送が確率的に救う

という設計でカバーしている（詳しくは [バイナリパケット](/deep-dive/binary-packet/) 参照）。

## なぜ独自プロトコル

既存プロトコルの候補と却下理由：

| 候補 | 却下理由 |
|---|---|
| OSC (Open Sound Control) | UDP で動く音楽用プロトコルだが、文字列パース・型タグでオーバーヘッドが大きい |
| RTP / RTP-MIDI | 規格が大きすぎ、マイコン実装が重い |
| MIDI over USB | 1 対 1 ユニキャスト前提。複数楽器に同時送信できない |

「20 B 固定の自前プロトコル」なら：

- パース不要（`memcpy` でそのまま構造体に書き戻せる）
- 仕様変更も自分で決められる（`instrumentId` を後付けできたのはこのおかげ）
- マイコンのフラッシュ / RAM 消費が小さい

詳細決定は [ADR-0002](/decisions/0002-udp-original-protocol/) 参照。

## なぜ SoftAP / Sta 構成

WiFi の役割は 2 種類：

- **SoftAP (Software Access Point)**: 親機。自分が WiFi セルを作る側
- **Sta (Station)**: 子機。既存のセルに接続する側

本プロジェクトは:

- **指揮者ノード (node_01) = SoftAP**: SSID `OrchestraAP` を立ち上げる
- **楽器ノード (node_02〜04) = Sta**: `OrchestraAP` に接続する

### なぜ会場の WiFi を使わないか

会場（教室・ホール）の WiFi に乗ると：

- IT 部門のフィルタでマルチキャストが弾かれることがある
- 隣の研究室が大量にトラフィックを流して詰まる
- 認証画面（キャプティブポータル）で詰まると詰む

指揮者ノードが **自前の WiFi セルを立てる** ことで、これらすべてから独立できる。
電源さえあれば、どこでも動く。

### チャネル 6 固定の理由

WiFi 2.4 GHz は 1〜13 のチャネルに分かれている。`ORC_NET_CONFIG.channel = 6` の意味：

- 1 / 6 / 11 が **互いに干渉しない 3 チャネル**（米国仕様。日本は 14 ch まで使えるが慣習で同じ）
- 6 は会場の WiFi と完全に重なってもセルを立てられる
- もし不調なら 1 や 11 へ変える余地がある

## マルチキャストアドレス `239.0.0.1` の意味

IPv4 マルチキャストは `224.0.0.0` 〜 `239.255.255.255`（クラス D）の範囲。
このうち：

| 範囲 | 用途 | 適否 |
|---|---|---|
| `224.0.0.0/24` | リンクローカル予約（ルーティング不可） | × IGMP/OSPF 等の制御で使われる |
| `224.0.1.0` 〜 `238.255.255.255` | グローバル割当 | × IANA が管理する公式アドレス |
| `239.0.0.0/8` | **管理スコープ（プライベート用）** | ◎ 自分のネットワーク内で自由に使える |

つまり `239.0.0.0/8` は「ローカルで好きに使っていいプライベートマルチキャスト」。
本プロジェクトは `239.0.0.1` を採用している。

> 192.168.x.y / 10.x.y.z がユニキャストのプライベートアドレスなのと同じく、
> `239.x.y.z` はマルチキャストのプライベートアドレス。

### TTL（Time To Live）

マルチキャストパケットは TTL でホップ数（通過できるルータの数）を制限される：

- TTL=1: 同じセグメントだけ。ルータを越えない（本プロジェクトはこれ）
- TTL=32 / 64: 組織内ルーティング可
- TTL=255: グローバル（ただし大半のルータが弾く）

`WiFiUDP` のデフォルト TTL は 1 で、本プロジェクトはそのままにしている。
SoftAP の中で完結するので、ルータを越える必要がない。

## IGMP の振る舞い

楽器が `udp_.beginMulticast(239.0.0.1, 5001)` を呼ぶと、内部で **IGMP Join Group** が
送信される。これにより：

- AP（指揮者）が「このグループに加入している子機リスト」を持つ
- マルチキャストパケットは AP から該当グループの子機にだけ転送される
- グループ外の子機には届かない（節電にもなる）

SoftAP 構成ではすべて指揮者ノード（ESP32-S3）の中で完結する。

### IGMP Snooping

商用 AP には「IGMP Snooping」という機能があり、これが有効だとマルチキャストが
特定の子機にだけ届く（理想的）。無効だとマルチキャストはブロードキャストに
なるが、本プロジェクトでは関係ない（楽器 3〜5 台ぶんのトラフィックは無視できる）。

## ポート 5001 を選んだ理由

UDP ポート番号の選定：

- 0〜1023: well-known ports（HTTPS=443、DNS=53 など）
- 1024〜49151: registered ports
- 49152〜65535: dynamic / private ports

`5001` は registered ports の範囲だが「比較的空いている」「覚えやすい」「他の
代表的なアプリと被らない」で採用。本プロジェクトでは固定なので、変更する場合は
`ORC_NET_CONFIG.udpPort` だけ書き換える。

## `OrcNetModule` の実装

### 初期化フロー

```cpp
bool OrcNetModule::init() {
    bool ok = (cfg_.mode == WifiMode::SoftAp) ? startSoftAp() : connectSta();
    if (ok) started_ = true;
    return ok;
}
```

#### SoftAP 側（指揮者）

```cpp
bool OrcNetModule::startSoftAp() {
    WiFi.mode(WIFI_AP);
    if (!WiFi.softAP(cfg_.ssid, cfg_.pass, cfg_.channel)) return false;
    delay(100);   // 内部で AP 起動が落ち着くまで
    if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
        udp_.begin(cfg_.udpPort);   // フォールバック
    }
    return true;
}
```

`WiFi.softAP()` で SSID `OrchestraAP` パスワード `orchestra2026` のセルを立てる。
`udp_.beginMulticast()` は自分自身もループバック確認できるよう、送信専用ではなく
受信もできる状態で開く（デバッグ用）。

#### Sta 側（楽器）

```cpp
bool OrcNetModule::connectSta() {
    WiFi.mode(WIFI_STA);
    WiFi.begin(cfg_.ssid, cfg_.pass);
    uint32_t startMs = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startMs < 8000) {
        delay(100);
    }
    if (WiFi.status() != WL_CONNECTED) return false;
    if (!udp_.beginMulticast(cfg_.multicastIp, cfg_.udpPort)) {
        udp_.begin(cfg_.udpPort);
    }
    return true;
}
```

`WiFi.begin()` で接続を試行。最大 8 秒待つ。これに失敗したら `init()` は
`false` を返し、その後 `enabled = false` で無効化される。

### 切断検知と再接続

楽器側（Sta）のみ、`updateInput()` で接続状態を監視し、切断時は
`reconnectIntervalMs = 2000` 間隔で再接続を試みる：

```cpp
if (cfg_.mode == WifiMode::Sta && !linkUp && started_) {
    uint32_t now = millis();
    if (now - lastReconnectMs_ >= cfg_.reconnectIntervalMs) {
        lastReconnectMs_ = now;
        WiFi.disconnect();
        WiFi.begin(cfg_.ssid, cfg_.pass);
    }
}
```

SoftAP 側は「立ち上がっていれば up 扱い」とみなす（実際のクライアント有無は
気にしない設計）。

### 受信ループ

```cpp
void OrcNetModule::pollReceive(OrcNetData& net) {
    int packetSize;
    while ((packetSize = udp_.parsePacket()) > 0) {
        if (packetSize != (int)orc::PACKET_SIZE) {
            // 不正サイズは破棄
            // ...
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

ポイント：

- `parsePacket()` でキューに溜まったパケットを 1 つずつ取り出す
- サイズが 20 B 固定でないものは捨てる（ノイズや別アプリのパケット混入対策）
- `magic` / `version` の検証は `parseHeader()` で行う
- `memcpy` でそのまま構造体に書き戻す（リトルエンディアン依存。詳細は次章）

毎ループで while ループするのは、CTRL と BEAT が同じループで届く可能性があるため。
ループしないと片方が古いまま残る。

### 送信ループ

```cpp
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
            udp_.write(/* ... */);
            udp_.endPacket();
        }
        net.hasPendingBeat = false;
    }
}
```

CTRL は 1 回送信、BEAT は `pendingBeatRedundancy`（= 2）回送信。
EMA の出力フェーズで毎ループ呼ばれるが、`hasPendingCtrl` / `hasPendingBeat` が
立っているときだけ実際に送る。これらのフラグを立てるのは `OrcSenderModule`
（次節で触れる）。

## なぜモジュールが 2 つに分かれているか

通信は `OrcNetModule`（ハードウェアに近い WiFi/UDP 操作）と
`OrcSenderModule`（CTRL/BEAT パケットを組み立てるロジック）に分かれている。

```
OrcSenderModule (Output)
    │
    │ data.orcNet.pendingCtrl / pendingBeat に書き込む
    ▼
OrcNetModule (Output)
    │
    │ data.orcNet.pendingCtrl を見て udp_.beginPacket → endPacket
    ▼
WiFi UDP
```

これにより:

- パケット形式やタイミングのロジックは `OrcSenderModule` に集約
- WiFi / UDP 操作の差異（ESP32 と UNO R4 で違う）は `OrcNetModule` が吸収
- 楽器側で受信したい場合は `OrcReceiverModule` を追加するだけで済む

EMA の「モジュール同士の直接呼び出し禁止」を守るため、両者は
`SystemData.orcNet.pendingCtrl` 等のフィールドだけで通信する。

## 確認方法（パケットが本当に流れているか）

### 1. WireShark で見る

Mac を SoftAP に接続して WireShark で `udp.port == 5001` をフィルタすると、
20 B のバイナリパケットが流れているのが見える。

### 2. 楽器側のシリアル

楽器を `SERIAL_DEBUG=1` でビルドすると、受信した CTRL/BEAT をシリアルに吐く。

```
[N2 CTRL recv bpm=100.5 vel=64 state=2 seq=247]
[N2 BEAT recv beatNo=42 playAtMaster=12395 seq=42]
```

### 3. 指揮者の送信統計

`OrcSenderData` の `ctrlSeq` / `beatSeq` を `dumpPeriodic()` で確認すると、
送信が継続しているか見える。

## 拡張するなら

- **楽器を 5 台以上に増やす**: `partId` を `0x05` 以降に拡張。プロトコルは変えない
- **指揮者を冗長化したい**: 第 2 の SoftAP を別チャネルで立て、楽器が両方に join。
  ただし時刻同期の融合戦略が必要になるので、現状は採用していない
- **クラウド経由で配信したい**: マルチキャストはルータを越えにくいので、
  別の仕組み（WebSocket リレー等）が必要

## 次に読むべきページ

- パケットのバイトレベル: [バイナリパケット](/deep-dive/binary-packet/)
- 送信される CTRL の中身: `firmware/test_v2/node_01/lib/OrcSenderModule/`
- 楽器側の受信処理: `firmware/test_v2/node_02/lib/OrcReceiverModule/`
