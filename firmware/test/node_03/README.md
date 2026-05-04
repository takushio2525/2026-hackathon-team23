# node_03 — 楽器 2 (金管 2) ノード (テスト版)

Arduino UNO R4 WiFi で「金管 2」パートを担当するテスト用実装。
仕様書 (`meetings/0429_3回/事前課題共有/arduino_塩澤.pdf`) §2.4.3 に準拠。

## 仕様の核

- 役割: 指揮者ノード node_01 の SoftAP に STA で接続し、CTRL/BEAT を受信、
  マスタ時刻 `playAtMasterMs` に発音タイミングを揃えて NOTE を USB Serial で
  Mac (Processing) に送出
- partId: `0x03` (金管 2)
- startBeatNo: `0` (このパートは曲頭から)
- 楽譜: ミファソラソファミ (E4 F4 G4 A4 G4 F4 E4) — node_02 (C4 ベース) の 3 度上、
  同時演奏で C major 圏内のハモリになる
- 状態遷移: Idle → WaitStart (Wi-Fi 接続) → Playing (初回 BEAT 受信)
  (Playing からは戻らず、BEAT が来ない間は単に次の BEAT を待つ。
  `sync.converged` 待ちは行わない — 未収束で「鳴らない」症状を回避するため)
- 進行則: **「BEAT を 1 個受信したら 1 拍ぶん `currentEventIndex` を進める」**
  純粋 index 駆動。`beatAt` は読みやすさ用の参考値。末尾まで来ると先頭に戻ってループ。
  BPM 起点の自走 (旧 SelfRun) は持たない。
- 発音タイミング: 受信した BEAT の `playAtMasterMs` をローカル時刻に変換
  (`targetLocalMs = playAtMasterMs - sync.offsetMs`) し、その時刻に達したら発火。
  既に過去になっている BEAT は捨てずに即発火 (フォールバック)。複数スレーブが
  同じ `playAtMasterMs` を共有することで、受信ジッタに関わらずスレーブ間で
  発音タイミングが揃う。
- 8 分音符の細分発火: `ScoreEvent.subNote / subOffsetQ8 / subDurationQ8` を立てると
  4 分 BEAT 受信時に拍頭で第 1 音、`subOffsetQ8/256` 拍後 (現在 BPM から ms 換算) に
  第 2 音を予約発火する。標準 `subOffsetQ8=128` で半拍後 = 8 分音符。
- 時計同期: CTRL/BEAT 受信時刻と `header.timestampMs` の差を EMA (α=0.10) で
  推定し、`masterNow = millis() + offsetMs` に揃える

## 配線

外部配線なし。USB Type-C で Mac (Processing 起動) に直結すれば給電 + Serial
通信 + WiFi STA まで揃う。

## ビルド

```bash
cd firmware/test/node_03
pio run                  # ビルド
pio run -t upload        # 書き込み
pio device monitor       # 注: Processing と同時に開けない (ポート競合)
```

シリアルポートは Processing 側が開く。pio device monitor を使うときは Processing を閉じる。

## シリアルデバッグ出力 (SERIAL_DEBUG)

`platformio.ini` の `-DSERIAL_DEBUG=0` (既定 / Processing 連携優先) ではバイナリ
NotePacket だけが流れる。実機で挙動を切り分けたいときは `-DSERIAL_DEBUG=1` に
変更してビルド。**この間 Serial は人間可読テキスト専用となり、Processing 連携用の
20 B バイナリ NotePacket は流れない** ので、診断中は Processing は閉じておく。

`SERIAL_DEBUG=1` で `pio device monitor` を開くと以下が流れる:

- 起動時: 各モジュール `init()` の OK/NG
- 周期 (200 ms): `[N3 t=… st=Playing wifi=1 sync=ok(off=… n=…) ctrl=(bpm=… v=… s=…)
  recv=(no=… ago=…) pend=… score=(idx=… snd=…)]`
- イベント:
  - `[N3 EVT STATE]` Idle/WaitStart/Playing の遷移
  - `[N3 EVT WIFI]` STA リンクの up/down
  - `[N3 EVT SYNC_CONVERGED]` 時計同期収束時の offset と sample 数
  - `[N3 EVT CTRL]` / `[N3 EVT BEAT]` パケット受信ごとに seq・bpm・playAt 等
  - `[N3 NOTE_ON ]` / `[N3 NOTE_OFF]` 発音タイミングと note/vel/dur

`SERIAL_DEBUG=0` のときは従来どおり 20 B バイナリ NotePacket を Serial に書き、
`pc_app/test/orchestra_player/` (Processing) が読み取って音を鳴らす。

## 構成

```
node_03/
├── platformio.ini
├── include/
│   ├── ProjectConfig.h     # 設定一元化 (partId=0x03, startBeatNo=0)
│   ├── SystemData.h        # モジュール間共有データ
│   └── score_data.h        # 楽譜配列の宣言
├── src/
│   ├── main.cpp            # 3 フェーズループ
│   ├── applyPattern.cpp    # 状態遷移 / マスタ時刻判定 / 楽譜進行
│   └── score_data.cpp      # 楽譜本体 (kScore[])
└── lib/
    ├── OrcReceiverModule/  # CTRL/BEAT を整形して SyncLogic / Receiver に書く
    └── NoteSenderModule/   # NOTE を USB Serial へ送出
```

他の楽器ノード (node_02 / 04 / 05) はこのコードをコピーし、
`ProjectConfig.h` の `partId` `startBeatNo` と `score_data.cpp` の `kScore[]`
だけを差し替えれば動く設計 (仕様 §2.4.3.6)。
