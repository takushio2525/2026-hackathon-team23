---
title: システム全体
description: production版のノード構成とデータフロー
---

## 構成図

```mermaid
flowchart LR
    subgraph C[指揮者 node_01]
      IMU[GY-521] --> LOGIC[拍検出 / BPM / ゲーム]
      LOGIC --> TX[CTRL / BEAT]
    end
    subgraph N[Wi-Fi OrchestraAP]
      UDP[239.0.0.1:5001]
    end
    subgraph I[楽器 Arduino UNO R4 WiFi]
      N2[node_02 トランペット + UI中継]
      N3[node_03 ホルン]
      N4[node_04 トロンボーン]
      N5[node_05 チューバ]
      N6[node_06 ドラム]
    end
    PC[Processing 4]
    SP[スピーカー]
    TX --> UDP
    UDP --> N2 & N3 & N4 & N5 & N6
    N2 & N3 & N4 & N5 & N6 -- NOTE / UI<br/>USB Serial --> PC
    PC --> SP
```

## 責務

| 要素 | 主な責務 |
|---|---|
| 指揮者 | IMU取得、拍検出、BPM推定、モード選択、ゲーム採点、UDP送信 |
| 金管4台 | 時刻同期、拍番号から楽譜位置を計算、NOTE送信 |
| ドラム | 56拍の専用譜を進行し、GMドラム番号をNOTE送信 |
| Processing | 複数USB受信、画面制御、金管加算合成、ドラム合成 |

## データ経路

- UDP：指揮者から楽器へ`CTRL`と`BEAT`
- USB Serial：各楽器からPCへ`NOTE`
- USB Serial：`node_02`からPCへ`UI`
- 音声：ProcessingのMinimからスピーカーへ

test_v1/test_v2は比較・参考用です。新しい作業はproductionを基準にしてください。
