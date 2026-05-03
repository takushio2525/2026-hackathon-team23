// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/test/node_01     # 指揮者ノード
//   pio run -d firmware/test/node_02     # 楽器 1
//
// シリアルデバッグの共通フック
// build_flags の -DSERIAL_DEBUG=1 で有効化される。
//   - SERIAL_DEBUG=0: マクロは空展開され、コードサイズも実行時コストも 0
//   - SERIAL_DEBUG=1: 内部で Serial.print / printf 互換出力を行う
//
// node_02 の NoteSenderModule はこのフラグを見て
// バイナリ NotePacket 出力 / 人間可読テキスト出力を切替えるので、
// このヘッダを必ず通してフラグの一貫性を確保する。
#pragma once
#include <Arduino.h>
#include <stdarg.h>
#include <stdio.h>

#ifndef SERIAL_DEBUG
#define SERIAL_DEBUG 0
#endif

namespace serial_debug {

// Serial が USB CDC の場合、ホスト側がポートを開くまで出力が落ちる。
// SERIAL_DEBUG=1 のときだけ最大 timeoutMs まで待つ (タイムアウト後は諦めて続行)。
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

// printf 互換。Renesas (UNO R4 WiFi) と ESP32 で Serial.printf の有無が
// 揺れるので、自前で vsnprintf してから write する。
inline void dbgPrintf(const char* fmt, ...) {
#if SERIAL_DEBUG
    // node_01 の dump 行は ~175 文字あり、160 では末尾が切れて改行が落ち、
    // 次の行と連結して見えてしまうので 256 まで広げる。スタック消費は微増のみ。
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
