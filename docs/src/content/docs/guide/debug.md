---
title: シリアルモニタでデバッグする
description: ログの読み方、よく確認するフィールド、`SERIAL_DEBUG` 切替
sidebar:
  order: 5
---

:::note[この章で分かること]
- シリアル出力の各フィールドの意味
- どこを見れば動作が分かるか
- ログを使った典型的な不具合追跡
:::

:::tip[読了目安]
**約 8 分**。前提: [Arduino を書き換える](/guide/firmware/) を読んでいること。
:::

## シリアル出力を見る

```bash
pio device monitor -d firmware/test_v2/node_01
```

`SERIAL_DEBUG=1`（指揮者ノードのデフォルト）の場合、次のログが流れる：

### 周期ログ（200 ms ごと）

```
[N1 t=12345 st=Conducting wifi=1 imu=1 acc=(0.10,0.85,-0.05) n=0.88 dyn=0.03 peakRaw=2.15 peakDyn=1.45 gate=I armedPk=1.20 path=0.000 bpm=100.5 beatNo=42 ctrlSeq=247 beatSeq=42]
```

| フィールド | 意味 |
|---|---|
| `t` | 起動からの経過時間 (ms) |
| `st` | 状態 (`Idle` / `Calibrating` / `Conducting` / `Fallback`) |
| `wifi` | WiFi 接続状態 (1/0) |
| `imu` | IMU データ readiness (1/0) |
| `acc` | LPF 後の加速度 (x, y, z)、g 単位 |
| `n` | 加速度ノルム (重力込み) |
| `dyn` | 動加速度ノルム (重力差し引き後 = 拍判定対象) |
| `peakRaw` | 200 ms 区間内の `n` ピーク |
| `peakDyn` | 200 ms 区間内の `dyn` ピーク |
| `gate` | 拍検出ゲート (`I`=Idle, `A`=Armed) |
| `armedPk` | Armed 中の `dyn` 最大値 |
| `path` | Armed 中の経路長累積 (m) |
| `bpm` | 現在の推定 BPM |
| `beatNo` | 累積拍番号 |
| `ctrlSeq` | CTRL の送信シーケンス番号 |
| `beatSeq` | BEAT の送信シーケンス番号 |

### イベントログ（変化時のみ）

状態遷移・WiFi 接続変化・拍発火の瞬間：

```
[N1 EVT STATE] Calibrating -> Conducting (gravityMag=1.012 done=1)
[N1 EVT WIFI] connected=1
[N1 EVT BEAT] no=43 t=12500 playAt=12550 bpm=100.5
```

## 典型的な追跡パターン

### 拍が検出されない

1. `imu=1` か確認（IMU が読めているか）
2. `dyn` を見ながら振る → 1.20 を超えているか
3. 超えていれば `gate=A` に切り替わるか
4. Armed 中に `path` が増えるか（0.20 m に達するか）

`dyn` が 1.0 程度で頭打ちなら、振りの強さが足りない or 閾値が高すぎる。
`logic_params::BEAT_DYN_THRESHOLD_G` を下げて再試行。

### 拍が二重発火する

`BEAT EVT` が連続して 350 ms 以下の間隔で出ているなら不応期で漏れてない。
`logic_params::BEAT_REFRACTORY_MS` を 350 → 400 等に上げる。

### BPM が安定しない

`bpm` が拍ごとに大きく揺れるなら、振りの間隔が一定でない or EMA 係数が小さい。
`logic_params::BPM_EMA_ALPHA` を 0.30 → 0.50 に上げると安定するが追従が遅くなる。

### WiFi が繋がらない

```
[N1 EVT WIFI] connected=0
```

が続く場合：

- 指揮者の SoftAP が立ち上がってない → 指揮者を先に起動
- SSID / pass のミスマッチ → `ProjectConfig.h` で確認
- WiFi チャネル 6 が混雑 → `ORC_NET_CONFIG.channel` を変える

## `SERIAL_DEBUG` の切替

各ノードの `platformio.ini` で：

```ini
build_flags =
    ...
    -DSERIAL_DEBUG=1   ; 1 で有効、0 で無効
```

楽器ノード（node_02〜04）は **デフォルト 0**。
バイナリ NOTE パケットを Serial に流すため、テキスト混在を避ける。

楽器のデバッグ時のみ一時的に `1` に変えるが、PC アプリと同時に動かすときは
`0` に戻す（バイナリと混ざってパースエラーになる）。

## シリアル出力の読み込みコード

ログのフォーマットは `firmware/test_v2/node_01/src/main.cpp` の `dumpPeriodic()` で
定義されている：

```cpp
DBG_PRINTF(
    "[N1 t=%lu st=%s wifi=%d imu=%d acc=(%6.2f,%6.2f,%6.2f) n=%4.2f dyn=%4.2f ...",
    (unsigned long)now,
    stateName(d.conductor.state),
    d.orcNet.wifiConnected ? 1 : 0,
    ...
);
```

新しいフィールドを足したいときはここを編集。

## ログのファイル保存

`pio device monitor` の出力をファイルに残す：

```bash
pio device monitor -d firmware/test_v2/node_01 | tee log_$(date +%Y%m%d_%H%M%S).txt
```

実機テスト中の挙動を後で解析するときに便利。

## グラフで見る（簡易）

シリアル出力を Python でパースして matplotlib でグラフ化するスクリプトを
`tools/` に置く（未実装、要望次第）。

## VS Code のシリアルモニタを使う

VS Code 内蔵のシリアルモニタも使える：

1. PlatformIO アイコンを開く
2. 「Project Tasks」 → 該当ノード → 「Monitor」をクリック

ターミナル CLI と同じだが、複数タブで楽。

## 次に読むべきページ

- ハマったときの対処集 → [よく出るトラブルと対処](/code/troubleshooting/)
- LaTeX 報告書 → [LaTeX 報告書をコンパイルする](/guide/latex/)
- 変更を保存する → [チームで Git を使う](/guide/git/)
