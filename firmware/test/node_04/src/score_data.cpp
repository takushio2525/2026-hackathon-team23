// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_04
//   pio run -d firmware/test/node_04 -t upload
//   pio device monitor -d firmware/test/node_04
//
// 木管 1 (node_04, partId=0x04) のテスト用楽譜
// node_02 の「ドレミファミレド」を 5 度上に並走させる: G4 A4 B4 C5 B4 A4 G4
// node_02 (C4) + node_03 (E4) と同時演奏すると C major triad のハモリになる。
//
// applyPattern は BEAT 1 個受信ごとに currentEventIndex を 1 個進める純粋 index
// 駆動なので、beatAt は読みやすさのための参考値 (1, 2, 3, ... と拍番号に揃える)。
// 末尾まで来ると先頭に戻ってループ再生する。
#include "score_data.h"

// {beatAt, noteNumber, velocity, durationQ8, flags, subNote, subVelocity,
//  subOffsetQ8, subDurationQ8} — sub なしは 0 を明示
const ScoreEvent kScore[] = {
    { 1, 67, 100, 240, 0x01, 0, 0, 0, 0 },  // ソ G4
    { 2, 69, 100, 240, 0x01, 0, 0, 0, 0 },  // ラ A4
    { 3, 71, 100, 240, 0x01, 0, 0, 0, 0 },  // シ B4
    { 4, 72, 100, 240, 0x01, 0, 0, 0, 0 },  // ド C5
    { 5, 71, 100, 240, 0x01, 0, 0, 0, 0 },  // シ B4
    { 6, 69, 100, 240, 0x01, 0, 0, 0, 0 },  // ラ A4
    { 7, 67, 100, 480, 0x01, 0, 0, 0, 0 },  // ソ G4 (約 2 拍)
};

const size_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
