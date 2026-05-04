# firmware/test — Arduino オーケストラ仕様書準拠のテスト実装

仕様書 `meetings/0429_3回/事前課題共有/arduino_塩澤.pdf` を実装可能な水準まで
落とし込んだ動作検証用ファームウェア。指揮者 (node_01) と楽器ノード
(node_02 / 03 / 04) の 4 ノード構成。各楽器ノードは 1 台の Mac に USB 直結し、
Mac 側 Processing が NotePacket を受けて発音する (1 楽器 = 1 Mac)。

## クイックスタート

```bash
# 1. 指揮者ノードを書き込む
cd firmware/test/node_01
pio run -t upload

# 2. 各楽器ノードを書き込む (それぞれ別の Mac から)
pio run -d firmware/test/node_02 -t upload   # 金管 1
pio run -d firmware/test/node_03 -t upload   # 金管 2
pio run -d firmware/test/node_04 -t upload   # 木管 1

# 3. 各 Mac で Processing を起動し
#    pc_app/test/orchestra_player/orchestra_player.pde を Run
#    (Mac ごとに SERIAL_PORT_NAME を書き換えること)
```

最初は node_02 だけで 1 台動作確認するのが安全。動いたら node_03 / 04 を順に
足していく。

詳細は各ノードの README を参照。

| ディレクトリ | 内容 |
|---|---|
| [`common/`](common/) | 全ノード共通ライブラリ (`OrcProtocol` / `OrcNetModule` / `StatusLedModule` / `ModuleCore`) |
| [`node_01/`](node_01/) | 指揮者ノード (XIAO ESP32-S3 Sense + GY-521) |
| [`node_02/`](node_02/) | 楽器 1 (金管 1, partId=0x02, C4 ベース) |
| [`node_03/`](node_03/) | 楽器 2 (金管 2, partId=0x03, E4 ベース) |
| [`node_04/`](node_04/) | 楽器 3 (木管 1, partId=0x04, G4 ベース) |

楽器 3 台が同期できていれば、各拍で C major 圏内の和音 (C / Dm / Em / F / Em / Dm / C)
が鳴る。ズレているとアルペジオ的に聞こえる。

## 起動順

1. 各楽器ノード (node_02 / 03 / 04) を電源 ON → `Idle` (LED 1 Hz 点滅)
2. 指揮者ノード (node_01) を電源 ON → SoftAP 起動 → `Calibrating` (2 Hz 点滅, 2 秒) → `Conducting` (点灯)
3. 各楽器ノードが SoftAP 接続 → `WaitStart` (2 Hz) → 指揮棒を振って初回 BEAT 到来で `Playing` (点灯)
   - 時計同期 EMA は CTRL/BEAT 受信のたびに更新されるが、Playing 遷移は CTRL/BEAT
     収束を待たない (待つと「鳴らない」症状の温床になるため)。最初の数拍は
     ノード間のズレが残るが、CTRL を数発受けたあとは収束する。

## マスタクロック方式

仕様 §2.3.3.6 に従い、指揮者の `millis()` をマスタ時刻として全ノードで共有する。
BEAT は「マスタ時刻 `playAtMasterMs` に発音せよ」という未来時刻指定で送り、
楽器側は CTRL/BEAT 受信時に offset を EMA で学習し、`masterNow = millis() + offset`
が `playAtMasterMs` に到達した瞬間に発音する。これにより WiFi 到達ばらつきが
時計同期誤差に押し付けられ、楽器間の相対同期はほぼゼロに収束する。
