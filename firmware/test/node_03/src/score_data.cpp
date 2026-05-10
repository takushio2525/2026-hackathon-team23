// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_03
//   pio run -d firmware/test/node_03 -t upload
//   pio device monitor -d firmware/test/node_03
//
// 金管 2 (node_03, partId=0x03) のテスト用楽譜
// node_02 の「ドレミファミレド」を 3 度上に並走させる: E4 F4 G4 A4 G4 F4 E4
// node_02 (C4 ベース) と同時演奏すると C major 圏内のハモリになる。
//
// applyPattern は BEAT 1 個受信ごとに currentEventIndex を 1 個進める純粋 index
// 駆動なので、beatAt は読みやすさのための参考値 (1, 2, 3, ... と拍番号に揃える)。
// 末尾まで来ると先頭に戻ってループ再生する。
#include "score_data.h"

// {beatAt, noteNumber, velocity, durationQ8, flags, subNote, subVelocity,
//  subOffsetQ8, subDurationQ8} — sub なしは 0 を明示
const ScoreEvent kScore[] = {
    { 1, 64, 100, 240, 0x01, 0, 0, 0, 0 },  // ミ E4
    { 2, 65, 100, 240, 0x01, 0, 0, 0, 0 },  // ファ F4
    { 3, 67, 100, 240, 0x01, 0, 0, 0, 0 },  // ソ G4
    { 4, 69, 100, 240, 0x01, 0, 0, 0, 0 },  // ラ A4
    { 5, 67, 100, 240, 0x01, 0, 0, 0, 0 },  // ソ G4
    { 6, 65, 100, 240, 0x01, 0, 0, 0, 0 },  // ファ F4
    { 7, 64, 100, 480, 0x01, 0, 0, 0, 0 },  // ミ E4 (約 2 拍)
};

const size_t kScoreLength = sizeof(kScore) / sizeof(kScore[0]);
