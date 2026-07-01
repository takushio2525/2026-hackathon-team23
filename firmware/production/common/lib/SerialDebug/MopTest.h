// MOP 検証モード共通ヘッダ
// platformio.ini の build_flags に -DMOP_TEST=N で切り替える (0=通常、1〜9=各MOP専用)。
// MOP_TEST が有効なときは SERIAL_DEBUG の大量ログを抑制し、
// 各 MOP に必要な最小限のデータだけを出力する。
#pragma once
#include <Arduino.h>

#ifndef MOP_TEST
#define MOP_TEST 0
#endif

// MOP_TEST 有効時は Serial を確実に初期化する (SERIAL_DEBUG=0 でも出力が必要なため)
namespace mop_test {

inline void ensureSerial(uint32_t baud = 115200, uint32_t timeoutMs = 1500) {
#if MOP_TEST > 0
    static bool initialized = false;
    if (!initialized) {
        Serial.begin(baud);
        const uint32_t start = millis();
        while (!Serial && (millis() - start) < timeoutMs) {
            delay(10);
        }
        initialized = true;
    }
#else
    (void)baud;
    (void)timeoutMs;
#endif
}

// コンパクトなテキスト出力 (帯域を節約するため printf 書式を使わず直書きする)
inline void print(const char* s) {
#if MOP_TEST > 0
    Serial.print(s);
#else
    (void)s;
#endif
}

inline void println(const char* s) {
#if MOP_TEST > 0
    Serial.println(s);
#else
    (void)s;
#endif
}

// printf 互換 (MOP 出力専用、SERIAL_DEBUG とは独立)
inline void mprintf(const char* fmt, ...) {
#if MOP_TEST > 0
    char buf[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    Serial.print(buf);
#else
    (void)fmt;
#endif
}

}  // namespace mop_test
