# pc_app/test — テスト用 PC 側プログラム

`firmware/test/` の楽器ノード (Arduino UNO R4 WiFi) から USB Serial で送られて
くる NOTE パケットを受けて音を鳴らす Processing スケッチ。

## 構成

| ディレクトリ | 内容 |
|---|---|
| `orchestra_player/` | 1 楽器ノード ↔ 1 Mac の音色合成 (Minim サイン波) |

## 必要なもの

- [Processing IDE](https://processing.org/download) (最新版)
- Minim ライブラリ (Processing IDE の `スケッチ → ライブラリをインポート → ライブラリを追加` から `Minim` を入れる)

## 実行手順

1. 指揮者ノード (`firmware/test/node_01`) と楽器ノード (`firmware/test/node_02`) を
   電源 ON にする
2. 楽器ノードを Mac に USB Type-C で接続する (Mac が自動でシリアルポートを生成)
3. Processing IDE で `orchestra_player/orchestra_player.pde` を開く
4. Run。コンソールに出るシリアルポート一覧から UNO R4 のポート番号を確認し、
   スケッチ先頭の `SERIAL_PORT_INDEX` を該当インデックスに書き換えて再 Run

## パケット仕様 (受信)

20 バイト固定。リトルエンディアン。

| Offset | Field         | Type      | 説明 |
|---|---|---|---|
| 0 | magic         | uint16_t  | 0x4F52 (`OR`)。フレーム同期マーク |
| 2 | version       | uint8_t   | 0x01 |
| 3 | type          | uint8_t   | 1=CTRL / 2=BEAT / 3=NOTE |
| 4 | seq           | uint32_t  | 単調増加 |
| 8 | timestampMs   | uint32_t  | 送信時のマスタ時刻 |
| 12| partId        | uint8_t   | 0x02–0x05 |
| 13| noteNumber    | uint8_t   | MIDI ノート番号 (60=C4) |
| 14| velocity      | uint8_t   | 0–127 |
| 15| gate          | uint8_t   | 1=NoteOn, 0=NoteOff |
| 16| durationMs    | uint16_t  | 発音予定長 (参考値) |
| 18| reserved[2]   | uint8_t[2]| 0 埋め |

詳細は `meetings/0429_3回/事前課題共有/arduino_塩澤.pdf` §2.3.3.3 を参照。

## トラブルシュート

- 音が鳴らない → Processing コンソールに「Failed to open serial port」が出ていないか確認。
  `pio device monitor` を立ち上げているとポートが二重に開けないので閉じる
- ノイズが乗る → サンプルレートと Mac の出力サンプルレートを一致させる (44100 Hz)
- 楽器ノードが動いているのにパケットが来ない → 指揮者ノードの SoftAP に
  STA 接続できているか LED 点滅パターンで確認 (1 Hz=Idle / 0.5 Hz=WaitStart / 点灯=Playing)
