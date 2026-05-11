// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v1/node_02
//   pio run -d firmware/test_v1/node_02 -t upload
//   pio device monitor -d firmware/test_v1/node_02
//
// 金管 1 (node_02) の楽譜データ
// 仕様 §2.4.3.4: ScoreEvent.beatAt は startBeatNo 相対の 1 始まり拍番号。
// 最初の振り下ろしで beatNo=1 となり、effective=1 で beatAt=1 のイベントが発火する。
//
// 細分音符 (8 分音符など) は ScoreEvent 1 行内に subNote として持たせる。
// applyPattern が 4 分 BEAT 受信時に subOffsetQ8 と現在 BPM から ms を計算して予約発火する。
#pragma once
#include <Arduino.h>

struct ScoreEvent {
    uint16_t beatAt;       // この拍番号で発火 (startBeatNo 相対, 1 始まり)
    uint8_t  noteNumber;   // MIDI ノート番号 (0=休符)
    uint8_t  velocity;     // 0-127
    uint16_t durationQ8;   // 1/256 拍単位 (256 = 1 拍)
    uint8_t  flags;        // bit0=NoteOn / bit1=NoteOff(拡張) / bit2=休符
    // ── 細分音符 (拍頭からのオフセットで予約発火する 2 音目) ──
    // subNote == 0 のときは予約しない。細分音符を持たない 4 分音符はゼロ初期化で OK。
    uint8_t  subNote;        // MIDI ノート番号 (0 = subdivision なし)
    uint8_t  subVelocity;    // 0-127
    uint16_t subOffsetQ8;    // 拍頭からのオフセット (256 = 1 拍, 128 = 半拍 = 8 分音符)
    uint16_t subDurationQ8;  // sub の発音長 (256 = 1 拍)
};

extern const ScoreEvent kScore[];
extern const size_t     kScoreLength;
