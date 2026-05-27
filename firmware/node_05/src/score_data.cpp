#include "score_data.h"

// 「かえるのうた」のチューバ用低音伴奏。C3、F2、G2 で輪唱の和声を支える。
const ScoreEvent kScore[] = {
    { 0, 48, 84, 1024, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、4拍
    { 1,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    { 2,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    { 3,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    { 4, 43, 80,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G2、2拍
    { 5,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    { 6, 48, 84,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    { 7,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    { 8, 48, 84,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    { 9,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {10, 41, 80,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // F2、2拍
    {11,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {12, 43, 80,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G2、2拍
    {13,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {14, 48, 84,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    {15,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {16, 48, 84,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    {17,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {18, 43, 80,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G2、2拍
    {19,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {20, 48, 84,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    {21,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {22, 43, 80,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G2、2拍
    {23,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {24, 48, 84,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    {25,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {26, 41, 80,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // F2、2拍
    {27,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {28, 43, 82,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G2、2拍
    {29,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {30, 48, 88,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    {31,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {32, 48, 84, 1024, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、4拍
    {33,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {34,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {35,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {36, 43, 82,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // G2、2拍
    {37,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
    {38, 48, 88,  512, SCORE_FLAG_NOTE_ON, 0, 0, 0, 0 }, // C3、2拍
    {39,  0,  0,    0, SCORE_FLAG_REST,    0, 0, 0, 0 },
};

const uint16_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
