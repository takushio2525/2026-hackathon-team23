// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_02
//   pio run -d firmware/test/node_02 -t upload
//   pio device monitor -d firmware/test/node_02
//
// 金管 1 のテスト用楽譜 — 「ドレミファミレド」(C4 D4 E4 F4 E4 D4 C4)
//
// applyPattern は BEAT 1 個受信ごとに currentEventIndex を 1 個進める純粋 index
// 駆動なので、beatAt は読みやすさのための参考値 (1, 2, 3, ... と拍番号に揃える)。
// 末尾まで来ると先頭に戻ってループ再生する。
//
// 8 分音符を試したい場合は ScoreEvent に subNote 等を持たせた行を追加する:
//   { 1, 60, 100, 128, 0x01, /*sub*/ 64, 100, 128, 128 },  // ド (8分) + 半拍後ミ (8分)
#include "score_data.h"

// {beatAt, noteNumber, velocity, durationQ8 (256=1拍), flags (bit0=NoteOn),
//  subNote, subVelocity, subOffsetQ8, subDurationQ8}
// 細分音符を持たない 4 分音符は subNote=0 で残り 3 つも 0 を明示する
// (-Wmissing-field-initializers 抑止 & 意図を明示)
const ScoreEvent kScore[] = {
    { 1, 60, 100, 240, 0x01, 0, 0, 0, 0 },  // ド C4
    { 2, 62, 100, 240, 0x01, 0, 0, 0, 0 },  // レ D4
    { 3, 64, 100, 240, 0x01, 0, 0, 0, 0 },  // ミ E4
    { 4, 65, 100, 240, 0x01, 0, 0, 0, 0 },  // ファ F4
    { 5, 64, 100, 240, 0x01, 0, 0, 0, 0 },  // ミ E4
    { 6, 62, 100, 240, 0x01, 0, 0, 0, 0 },  // レ D4
    { 7, 60, 100, 480, 0x01, 0, 0, 0, 0 },  // ド C4 (約 2 拍)
};

const size_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
