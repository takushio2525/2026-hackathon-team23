#include "score_data.h"

// 「かえるのうた」のハ長調主旋律。主旋律担当の3ノードで共有する。
const ScoreEvent kScore[] = {
    { 0, 60, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4
    { 1, 62, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // D4
    { 2, 64, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // E4
    { 3, 65, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // F4
    { 4, 64, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // E4
    { 5, 62, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // D4
    { 6, 60, 96, 512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4、2拍
    { 7,  0,  0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    { 8, 64, 92, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // E4
    { 9, 65, 92, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // F4
    {10, 67, 92, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G4
    {11, 69, 92, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // A4
    {12, 67, 92, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G4
    {13, 65, 92, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // F4
    {14, 64, 96, 512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // E4、2拍
    {15,  0,  0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {16, 60, 90, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4
    {17,  0,  0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {18, 60, 90, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4
    {19,  0,  0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {20, 60, 90, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4
    {21,  0,  0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {22, 60, 90, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4
    {23,  0,  0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {24, 60, 96, 128, SCORE_FLAG_NOTE_ON, 60, 96, 128, 128 }, // C4 C4
    {25, 62, 96, 128, SCORE_FLAG_NOTE_ON, 62, 96, 128, 128 }, // D4 D4
    {26, 64, 96, 128, SCORE_FLAG_NOTE_ON, 64, 96, 128, 128 }, // E4 E4
    {27, 65, 96, 128, SCORE_FLAG_NOTE_ON, 65, 96, 128, 128 }, // F4 F4
    {28, 64, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // E4
    {29, 62, 96, 256, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // D4
    {30, 60, 100, 512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C4、2拍
    {31,  0,   0,   0, SCORE_FLAG_REST,    0, 0, 0, 0 },
};

const uint16_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
