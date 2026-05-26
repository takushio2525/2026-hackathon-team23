#pragma once

#include <Arduino.h>

constexpr uint8_t SCORE_FLAG_NOTE_ON = 0x01;
constexpr uint8_t SCORE_FLAG_NOTE_OFF = 0x02;  // Reserved for future use.
constexpr uint8_t SCORE_FLAG_REST = 0x04;

// One entry represents one beat. Sub fields reserve one in-beat note event.
struct ScoreEvent {
    uint16_t beatAt;          // Readability only: 1-origin beat number.
    uint8_t noteNumber;       // MIDI note number. 0 means rest.
    uint8_t velocity;         // Score velocity, 0-127.
    uint16_t durationQ8;      // 1/256 beat. 256 = 1 beat.
    uint8_t flags;            // NoteOn / reserved NoteOff / Rest.
    uint8_t subNote;          // In-beat second note. 0 means unused.
    uint8_t subVelocity;      // Velocity for subNote.
    uint16_t subOffsetQ8;     // Offset from beat head. 128 = half beat.
    uint16_t subDurationQ8;   // Duration for subNote.
};

extern const ScoreEvent kScore[];
extern const size_t kScoreLength;

