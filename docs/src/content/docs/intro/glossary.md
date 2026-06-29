---
title: 用語集
description: 現行システムで使う用語と略語
---

| 用語 | 意味 |
|---|---|
| IMU | 加速度・角速度を測るセンサー。GY-521上のMPU6050を使用 |
| CTRL | BPM、状態、モード、得点などを20 Hzで送るUDPパケット |
| BEAT | 拍番号と発音予定時刻を送るUDPパケット |
| NOTE | 音高、強さ、長さ、音色番号をPCへ送るUSB Serialパケット |
| UI | 指揮者状態を`node_02`からPCへ中継するUSB Serialパケット |
| `partId` | ノード識別子。`node_02〜06`が`0x02〜0x06` |
| `instrumentId` | PC側で音色を選ぶ番号。0〜3が金管、4以上がドラム |
| EMA | Embedded-Module-Architecture。入力・ロジック・出力を分離する設計 |
| EMA平滑化 | Exponential Moving Average。時計ずれやBPMを滑らかに推定する処理 |
| `bpmQ8` | BPMを8倍した整数。小数1/8 BPMまで20Bパケット内で表現 |
| `playAtMasterMs` | 指揮者時計で「この時刻に発音せよ」を表す予約時刻 |
| MOE / MOP | 有効性の評価指標 / その達成度を測る性能指標 |
| ADSR | 音量包絡のAttack・Decay・Sustain・Release |
| 加算合成 | 基音と複数の倍音を足して音色を作る方式 |
| Fallback | IMUやWi-Fi異常時の一時停止状態 |
