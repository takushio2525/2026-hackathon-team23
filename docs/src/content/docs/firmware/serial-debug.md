---
title: SerialDebug — コンパイル時切替えのデバッグログ
description: "-DSERIAL_DEBUG=1 で有効化されるマクロ群。NoteSenderModule との切替えロジックも含めて"
sidebar:
  label: 共通 — SerialDebug
  order: 5
---

:::note[この章で分かること]
- `SERIAL_DEBUG=0` のときマクロが完全に消える仕掛け（実行時コストゼロ）
- USB CDC でホスト側の `pio device monitor` が開くのを待つ `waitForHost()` の理由
- なぜ ESP32 と Arduino UNO R4 WiFi で `Serial.printf` をそのまま使えないのか
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/production/common/lib/SerialDebug/SerialDebug.h` | 69 | マクロ + 補助 inline 関数（ヘッダオンリー） |

`.cpp` を持たない。テンプレート的に「全部見せる」のでまず全コードを置く。

## 全コード

```cpp
#pragma once
#include <Arduino.h>
#include <stdarg.h>
#include <stdio.h>

#ifndef SERIAL_DEBUG
#define SERIAL_DEBUG 0
#endif

namespace serial_debug {

inline void waitForHost(uint32_t timeoutMs = 1500) {
#if SERIAL_DEBUG
    const uint32_t start = millis();
    while (!Serial && (millis() - start) < timeoutMs) {
        delay(10);
    }
#else
    (void)timeoutMs;
#endif
}

inline void dbgPrintf(const char* fmt, ...) {
#if SERIAL_DEBUG
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    Serial.print(buf);
#else
    (void)fmt;
#endif
}

}  // namespace serial_debug

#if SERIAL_DEBUG
  #define DBG_BEGIN(baud)        do { Serial.begin(baud); } while (0)
  #define DBG_WAIT_HOST(timeout) ::serial_debug::waitForHost(timeout)
  #define DBG_PRINT(x)           Serial.print(x)
  #define DBG_PRINTLN(x)         Serial.println(x)
  #define DBG_PRINTF(...)        ::serial_debug::dbgPrintf(__VA_ARGS__)
#else
  #define DBG_BEGIN(baud)        ((void)0)
  #define DBG_WAIT_HOST(timeout) ((void)0)
  #define DBG_PRINT(x)           ((void)0)
  #define DBG_PRINTLN(x)         ((void)0)
  #define DBG_PRINTF(...)        ((void)0)
#endif
```

## 役割と責務

| 観点 | 内容 |
|---|---|
| **コンパイル時スイッチ** | `-DSERIAL_DEBUG=1` で有効化、0 で無効化 |
| **無効時のオーバーヘッド** | ゼロ（マクロが `((void)0)` に展開され、最適化で完全消滅） |
| **責務境界** | ハードウェア出力 (Serial) のラッパーだけ。アプリケーションロジックは持たない |

このモジュールは `IModule` を継承しない。**ライブラリ関数として直接呼ばれる** タイプ。

## 切替えの仕組み

### コンパイル時定数のデフォルト値

```cpp
#ifndef SERIAL_DEBUG
#define SERIAL_DEBUG 0
#endif
```

`SERIAL_DEBUG` がどこにも定義されていなければ、自動的に 0 になる。
つまり **デフォルトは無効** で、`platformio.ini` で明示的に `-DSERIAL_DEBUG=1` を書いた
ノードだけ有効化される。

### `platformio.ini` での指定

指揮者ノード（拍検出のデバッグログを見たい）:
```ini
build_flags =
    ...
    -DSERIAL_DEBUG=1
```

楽器ノード（NotePacket バイナリ出力を流したい）:
```ini
build_flags =
    ...
    -DSERIAL_DEBUG=0
```

### マクロが「消える」原理

```cpp
#if SERIAL_DEBUG
  #define DBG_PRINTLN(x) Serial.println(x)
#else
  #define DBG_PRINTLN(x) ((void)0)
#endif
```

`SERIAL_DEBUG=0` のとき、ソース中の `DBG_PRINTLN("hello")` は **プリプロセッサで** 
`((void)0)` に置換される。コンパイラは `(void)0` を見て「式の値を捨てる」と判断し、
最適化（`-O2`）で完全に削除する。

結果として：
- **コードサイズが増えない**: 文字列リテラルも残らない
- **実行時間が増えない**: そもそもコード自体が存在しない
- **printf フォーマット文字列がリリースビルドに残らない**: リバースエンジニアリング対策にもなる

### inline 関数版（`dbgPrintf`）の実装

マクロ版だと可変長引数の解釈で扱いが面倒なので、`dbgPrintf` は `inline` 関数：

```cpp
inline void dbgPrintf(const char* fmt, ...) {
#if SERIAL_DEBUG
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    Serial.print(buf);
#else
    (void)fmt;
#endif
}
```

`SERIAL_DEBUG=0` のとき、関数本体は `(void)fmt;` だけになる。`inline` なので呼び出し側に
インライン展開され、引数の評価も省略される（副作用のない引数ならコンパイラが消す）。

**バッファ 256 B の根拠**:

```cpp
char buf[256];
```

最初は 160 B にしていたが、指揮者ノードの dump 行が **175 文字** あり、末尾の改行 `\n` が切れて
次の行と連結して見える事故があった。256 まで広げてもスタック消費は微増のみ。

```
// 切れる例 (buf[160])
"[N1 t=12345 st=Conducting wifi=1 imu=1 acc=(...) ... peakRaw=...peakDyn=..."[N1 t=12350 st=...
//                                                                          ↑ \n が切れて連結
```

`vsnprintf` は `n-1` 文字で切って `\0` を入れるので、改行を含む長い行はバッファを十分に
取らないと連結バグになる。

## USB CDC とホスト待機

### USB CDC とは

XIAO ESP32-S3 と Arduino UNO R4 WiFi は両方とも **USB CDC**（Communications Device Class）で
シリアル通信する。これは「ボードが USB デバイスとして PC にシリアルポートを見せる」方式で、
従来の UART チップ（FTDI / CH340 等）を介さない。

特徴：
- ボード側のリセット直後、ホスト（macOS / Windows）がポートをエニュメレートするまで時間がかかる
- ホスト側のシリアルアプリ（`pio device monitor` 等）がポートを **開いていない間に書いた出力は
  捨てられる**

つまり、`setup()` 内で `Serial.println("=== boot ===")` を書いても、ホストが間に合わなければ
**起動ログが永久に見えない**。

### `waitForHost()` の役割

```cpp
inline void waitForHost(uint32_t timeoutMs = 1500) {
#if SERIAL_DEBUG
    const uint32_t start = millis();
    while (!Serial && (millis() - start) < timeoutMs) {
        delay(10);
    }
#endif
}
```

`while (!Serial)` で **ホスト側がシリアルポートを開くのを待つ**。`Serial` の bool 演算子は
「ホストが接続済みか」を返す（USB CDC 限定の挙動）。

タイムアウト 1500 ms を設けているのは：
- ホストが起動していない場合、無限待機すると組み込み機器が起動しない
- 1.5 秒待っても繋がらなければ「ホストなしで起動した」と判断して続行

これにより：
- `pio device monitor` を先に開いてから USB を挿す → 起動ログを取りこぼさない
- 単体で電源だけ繋いだ場合 → 1.5 秒待って動き始める

### `SERIAL_DEBUG=0` 時の挙動

```cpp
inline void waitForHost(uint32_t timeoutMs = 1500) {
#if SERIAL_DEBUG
    ...
#else
    (void)timeoutMs;
#endif
}
```

無効時は **完全に何もしない**。`(void)timeoutMs` は警告抑制（未使用引数警告を消す）。
楽器ノードのリリースビルドでは `DBG_WAIT_HOST(1500)` が空展開されるので、
起動直後すぐにループに入れる。

## `Serial.printf` 不在問題

ESP32 の Arduino Core には `Serial.printf` がある：
```cpp
Serial.printf("bpm=%5.1f\n", bpm);   // ESP32 では動く
```

しかし Arduino UNO R4 WiFi（Renesas）の `Serial` クラスには **`printf` メソッドがない**。
これがあるとビルドが片方で通って片方で通らない。

このモジュールでは `vsnprintf` + `Serial.print` の組み合わせで自前 printf を実装し、
**両方のアーキで同じコード** が動くようにしてある：

```cpp
char buf[256];
va_list ap;
va_start(ap, fmt);
vsnprintf(buf, sizeof(buf), fmt, ap);
va_end(ap);
Serial.print(buf);
```

`vsnprintf` は C 標準ライブラリの関数なので、Arduino のどちらのコアでも使える。

## マクロの使い方

### 起動シーケンス（`main.cpp`）

```cpp
void setup() {
    DBG_BEGIN(115200);       // Serial.begin(115200) (有効時のみ)
    DBG_WAIT_HOST(1500);     // ホスト接続を 1.5 秒待つ (有効時のみ)
    DBG_PRINTLN("");
    DBG_PRINTLN("=== node_01 (conductor) boot ===");
    // ...
}
```

`SERIAL_DEBUG=0` ならこれらは全部 `(void)0` に消える。

### 周期出力（`main.cpp` の `dumpPeriodic`）

```cpp
DBG_PRINTF(
    "[N1 t=%lu st=%s wifi=%d imu=%d acc=(%6.2f,%6.2f,%6.2f) n=%4.2f dyn=%4.2f ...]\n",
    (unsigned long)now,
    stateName(d.conductor.state),
    d.orcNet.wifiConnected ? 1 : 0,
    d.imu.ready ? 1 : 0,
    d.imu.accLpf[0], d.imu.accLpf[1], d.imu.accLpf[2],
    d.imu.accNorm,
    d.imu.dynNorm,
    ...);
```

ここが 175 文字超えるので 256 B バッファが必要だった。

### イベント出力（`dumpEdges`）

```cpp
if (d.conductor.state != gPrevState) {
    DBG_PRINTF("[N1 EVT STATE] %s -> %s\n",
               stateName(gPrevState), stateName(d.conductor.state));
    gPrevState = d.conductor.state;
}
```

状態が変わった瞬間だけ出力する「エッジ通知」パターン。`gPrevState` を保持して差分検出する。

## NoteSenderModule との切替えロジック

楽器ノードの `NoteSenderModule` は **同じ Serial を NotePacket バイナリ出力に使う**。
`SERIAL_DEBUG=1` のときバイナリ出力と人間可読出力が混ざると、Processing 側が
ヘッダ MAGIC を見失って崩壊する。

そのため `NoteSenderModule.cpp` は：

```cpp
#if SERIAL_DEBUG
    DBG_PRINTF("[N2 NOTE_ON ] part=0x%02X instr=%u note=%u ...\n", ...);
#else
    buildAndSend(cfg_.partId, cfg_.instrumentId, /*gate=*/1, seq, now, data.noteOut);
    // ↑ NotePacket 20 B を Serial に書く
#endif
```

と **コンパイル時に分岐** する。`SERIAL_DEBUG=1` のときは「人間可読のデバッグログ専用」になり、
Processing 連携は一時停止する。`SERIAL_DEBUG=0` のときは「NotePacket バイナリ出力専用」になる。

両者を実行時に切り替える設計にすると、`Serial` の状態管理が面倒になる（ホスト側はバイナリと
テキストを混在して受け取れない）。コンパイル時切替えにすれば設計が単純で済む。

## 落とし穴

- **`SERIAL_DEBUG=1` のとき NotePacket は流れない**: 楽器ノードを Processing と連携させて
  音を出したければ、`SERIAL_DEBUG=0` でビルドし直す必要がある。
- **`DBG_PRINTF` のフォーマット文字列をユーザー入力から作らない**: フォーマット文字列攻撃の
  原因になる。組み込みなので実害は限定的だが、習慣として避ける。
- **`Serial.flush()` を呼ばない**: USB CDC は内部バッファを持っているので、毎回 flush すると
  パフォーマンスが落ちる（実際 NoteSenderModule では発音の遅れを避けるため必要に応じて flush
  しているが、デバッグログは flush 不要）。
- **256 B を超える出力は切れる**: 1 行 256 B 以内に収める。長い構造体ダンプは複数行に分ける。

## 関連ページ

- 楽器ノードのバイナリ送信側 → [NoteSenderModule](/firmware/note-sender/)
- どのノードでどう有効化されているか → [main フロー（指揮者）](/firmware/main-conductor/) / [main フロー（楽器）](/firmware/main-instrument/)
- シリアルモニタの使い方 → [シリアルモニタでデバッグする](/guide/debug/)
