#pragma once
#include <stdint.h>

struct ScoreEvent {
    uint16_t beatAt;      // Part-relative beat number.
    uint8_t noteNumber;   // MIDI note number. 0 means rest.
    uint8_t velocity;     // 0-127.
    uint16_t durationQ8;  // 256 = 1 beat.
    uint8_t flags;        // bit0=NoteOn, bit2=Rest.
};

extern const ScoreEvent kScore[];
extern const uint16_t kScoreLength;
