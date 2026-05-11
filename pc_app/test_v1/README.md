# pc_app/test_v1 — テスト用 PC 側プログラム（最初の版）

> これは最初の版（旧 `pc_app/test`）。きらきら星の輪唱 + sound_lab の音色で鳴らす続編は
> [`../test_v2/`](../test_v2/)。新しく動かすならそちらを使う。

`firmware/test_v1/` の楽器ノード (Arduino UNO R4 WiFi) から USB Serial で送られて
くる NOTE パケットを受けて音を鳴らす Processing スケッチ。

## 構成

| ディレクトリ | 内容 |
|---|---|
| `orchestra_player/` | 1 楽器ノード ↔ 1 Mac の音色合成 (Minim サイン波) |

複数の楽器ノード (node_02 / 03 / 04) を鳴らすときは、**Mac と Processing インスタンスを
楽器ノードごとに用意する** (1 楽器 = 1 Mac)。Processing 側は受信した
`partId` をそのまま `Voice` のキーに使うため、partId が 0x02 / 0x03 / 0x04 の
いずれでもコード変更なしで動く (画面の `Last partId` 表示で確認可能)。

## 必要なもの

- [Processing IDE](https://processing.org/download) (最新版)
- Minim ライブラリ (Processing IDE の `スケッチ → ライブラリをインポート → ライブラリを追加` から `Minim` を入れる)

## 実行手順

1. 指揮者ノード (`firmware/test_v1/node_01`) と楽器ノード
   (`firmware/test_v1/node_02` / `node_03` / `node_04` のいずれか) を電源 ON にする
2. 楽器ノードを Mac に USB Type-C で接続する (Mac が自動でシリアルポートを生成)
3. Processing IDE で `orchestra_player/orchestra_player.pde` を開く
4. ポート選択を 2 通りから選ぶ:
   - **推奨: ポート名で指定**。Mac で `ls /dev/cu.*` でポート名を調べ、スケッチ先頭の
     `SERIAL_PORT_NAME` をそのポート名に書き換える。Mac ごとにポート名は異なる
     ので、各 Mac で 1 度だけ書き換えればよい
   - フォールバック: `SERIAL_PORT_NAME = ""` のときだけ `SERIAL_PORT_INDEX` の番号
     (`Serial.list()` の 0 始まりインデックス) で選ぶ
5. Run。Processing コンソールに開いたポート名と「`Last partId: 0xXX`」が出れば成功

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
