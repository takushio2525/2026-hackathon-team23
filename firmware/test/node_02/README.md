# node_02 — 楽器 1 (金管 1) ノード (テスト版)

Arduino UNO R4 WiFi で「金管 1」パートを担当するテスト用実装。
仕様書 (`meetings/0429_3回/事前課題共有/arduino_塩澤.pdf`) §2.4.3 に準拠。

## 仕様の核

- 役割: 指揮者ノード node_01 の SoftAP に STA で接続し、CTRL/BEAT を受信、
  マスタ時刻 `playAtMasterMs` に発音タイミングを揃えて NOTE を USB Serial で
  Mac (Processing) に送出
- partId: `0x02` (金管 1)
- startBeatNo: `0` (このパートは曲頭から)
- 状態遷移: Idle → WaitStart (時計同期収束 + 入り拍到来) → Playing → (BEAT 1500 ms 未受信) → SelfRun → Playing
- 時計同期: CTRL/BEAT 受信時刻と `header.timestampMs` の差を EMA (α=0.10) で
  推定し、`masterNow = millis() + offsetMs` に揃える

## 配線

外部配線なし。USB Type-C で Mac (Processing 起動) に直結すれば給電 + Serial
通信 + WiFi STA まで揃う。

## ビルド

```bash
cd firmware/test/node_02
pio run                  # ビルド
pio run -t upload        # 書き込み
pio device monitor       # 注: Processing と同時に開けない (ポート競合)
```

シリアルポートは Processing 側が開く。pio device monitor を使うときは Processing を閉じる。

## 構成

```
node_02/
├── platformio.ini
├── include/
│   ├── ProjectConfig.h     # 設定一元化 (partId=0x02, startBeatNo=0)
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

他の楽器ノード (node_03 / 04 / 05) はこのコードをコピーし、
`ProjectConfig.h` の `partId` `startBeatNo` と `score_data.cpp` の `kScore[]`
だけを差し替えれば動く設計 (仕様 §2.4.3.6)。
