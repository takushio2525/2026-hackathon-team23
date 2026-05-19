# pc_app/test_v2 — 輪唱（きらきら星）を sound_lab の音色で鳴らす Processing

`firmware/test_v2/` の楽器ノード（Arduino UNO R4 WiFi）から USB Serial で送られてくる
NOTE パケット（**楽器番号 / 高さ / 長さ / 声部 / velocity**）を受け、`sound_lab` で解析した
楽器定義（`data/*.json`）を使ってポリフォニックに加算合成する。

```
pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde
```

## 構成

| ディレクトリ | 内容 |
|---|---|
| `orchestra_resynth/` | 受信した NOTE を `data/*.json` の音色で再合成して鳴らす。複数シリアルポートを同時に開ける |
| `orchestra_resynth/data/` | 楽器定義 JSON（番号 = Arduino が送る `instrumentId`）。4 種類同梱 |

合成方式は `sound_lab/processing/instrument_player` と同じ（倍音ごとの振幅・周波数比・時間
エンベロープを持つ加算合成 + 非調和性 + スペクトル整形ノイズ + 全体振幅エンベロープ +
ビブラート/トレモロ）。`InstrModel` / `ResynthVoice` をそちらから移植している。

## 必要なもの

- [Processing IDE](https://processing.org/download)
- Minim ライブラリ（Processing IDE の `スケッチ → ライブラリをインポート → ライブラリを追加` から `Minim`）

## 実行手順

1. 指揮者ノード（`firmware/test_v2/node_01`）と楽器ノード（`node_02` / `node_03` / `node_04`）を電源 ON
2. 楽器ノードを Mac に USB Type-C で接続する
   - 本番想定は **1 Mac : 1 ノード（1 声部）**
   - テスト用に **1 Mac に複数ノードを挿してもよい**（このアプリで複数ポートを同時に開ける）
3. Processing IDE で `orchestra_resynth/orchestra_resynth.pde` を開いて Run
4. 画面下の「シリアルポート」一覧で、繋いだ Arduino のポートを **クリックして開く**
   （複数挿しているなら、それぞれのポートをクリックして全部開く）。もう一度クリックで閉じる
5. node_02 がすぐ「きらきら星」を弾き始める。node_03 は 8 拍後、node_04 は 16 拍後に入って輪唱になる
   - Processing をいつ起動しても「曲の現在位置」から鳴り始める（途中参加 OK）。
     `pio device monitor` を立ち上げているとポートが二重に開けないので閉じる

### Arduino なしで音だけ確認したいとき

- `t` キー: テスト和音（C・E・G を楽器 0/1/2 で同時に鳴らす）
- `0`〜`3` キー: その番号の楽器で C4 を 1 発（楽器の聴き比べ）
- `Space`: 全音停止 / `+` `-`: マスター音量 / `a`: 振幅包絡の方式切替（実エンベロープ ↔ ADSR4値）
- `r`: シリアルポート再列挙 / `i`: `data/` の楽器定義を再スキャン

## パケット仕様（受信, 20 バイト固定, リトルエンディアン）

| Offset | Field | Type | 説明 |
|---|---|---|---|
| 0 | magic | uint16 | 0x4F52（`OR`） |
| 2 | version | uint8 | 0x01 |
| 3 | type | uint8 | 3=NOTE（1=CTRL / 2=BEAT は USB には流れない） |
| 4 | seq | uint32 | 単調増加 |
| 8 | timestampMs | uint32 | 送信時のマスタ時刻 |
| 12 | partId | uint8 | test_v2 は 0x02–0x04 / production 想定は 0x02–0x05（輪唱のどの声部か） |
| 13 | noteNumber | uint8 | MIDI ノート番号（60=C4, 高さ） |
| 14 | velocity | uint8 | 0–127 |
| 15 | gate | uint8 | 1=NoteOn（0=NoteOff は来ないが来たら一致音を release） |
| 16 | durationMs | uint16 | 発音予定長（長さ）。これを過ぎたら自動で release |
| 18 | instrumentId | uint8 | 0..N-1（楽器番号 — `data/` の何番目の楽器定義か） |
| 19 | reserved | uint8 | 0 |

楽器定義 JSON のフォーマット: [`../../sound_lab/library_format.md`](../../sound_lab/library_format.md)

## トラブルシュート

- 音が鳴らない → コンソールに `Failed to open` が出ていないか確認。`pio device monitor` を閉じる。
  楽器ノードの `platformio.ini` が `SERIAL_DEBUG=0`（既定）になっているか確認（`=1` だとバイナリ
  NOTE が流れず、人間可読テキストになる）
- ノイズ / 割れる → `-` キーでマスター音量を下げる（3 声部合算で大きくなりがち）
- ポートを開いても受信 0 のまま → 指揮者ノードが SoftAP を立てていて、楽器ノードが STA 接続できているか
  LED 点滅で確認（1 Hz=Idle / 0.5 Hz=WaitStart / 点灯=Playing）。指揮棒を振らないと BEAT が出ない
