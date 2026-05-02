// 金管 1 (node_02) の楽譜データ
// 仕様 §2.4.3.4: ScoreEvent.beatAt は startBeatNo 相対 (各パート 0 始まり)
#pragma once
#include <Arduino.h>

struct ScoreEvent {
    uint16_t beatAt;       // この拍番号で発火 (startBeatNo 相対)
    uint8_t  noteNumber;   // MIDI ノート番号 (0=休符)
    uint8_t  velocity;     // 0-127
    uint16_t durationQ8;   // 1/256 拍単位 (256 = 1 拍)
    uint8_t  flags;        // bit0=NoteOn / bit1=NoteOff(拡張) / bit2=休符
};

extern const ScoreEvent kScore[];
extern const size_t     kScoreLength;
