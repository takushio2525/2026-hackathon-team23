#pragma once
#include <stdint.h>

constexpr uint8_t SCORE_FLAG_NOTE_ON = 0x01;
constexpr uint8_t SCORE_FLAG_NOTE_OFF = 0x02;  // 将来用に予約。
constexpr uint8_t SCORE_FLAG_REST = 0x04;

constexpr uint8_t kInstrumentId = 0;      // トランペット。
constexpr uint16_t kHeadRestBeats = 0;    // 曲頭から開始。

// 1要素が1拍を表す。sub 系フィールドで拍の途中の第2音を保持できる。
struct ScoreEvent {
    uint16_t beatAt;          // パート開始からの0始まりの拍番号。
    uint8_t noteNumber;       // MIDI ノート番号。0 は休符。
    uint8_t velocity;         // 楽譜上の強さ。0〜127。
    uint16_t durationQ8;      // 1/256拍。256 = 1拍。
    uint8_t flags;            // NoteOn / 予約済み NoteOff / 休符。
    uint8_t subNote;          // 拍内の第2音。0 は未使用。
    uint8_t subVelocity;      // subNote の強さ。
    uint16_t subOffsetQ8;     // 拍頭からのずれ。128 = 半拍。
    uint16_t subDurationQ8;   // subNote の発音長。
};

extern const ScoreEvent kScore[];
extern const uint16_t kScoreLength;
