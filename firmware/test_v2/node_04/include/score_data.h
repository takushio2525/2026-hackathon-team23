// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v2/node_04
//   pio run -d firmware/test_v2/node_04 -t upload
//   pio device monitor -d firmware/test_v2/node_04
//
// 輪唱用の楽譜データ — 全声部 (node_04/03/04) で同一の「きらきら星 全曲」を持つ。
// 1 拍 = 1 ScoreEvent。指揮者の BEAT を 1 個受けるたびに kScore のインデックスを
// 1 個進める (= 拍番号で引く)。末尾まで来たら先頭に戻ってループする。
//
// 輪唱 (canon) は「先頭に休符を入れて声部ごとにずらす」方式:
//   各ノードの ProjectConfig.h の headRestBeats だけ頭の拍を読み飛ばしてから
//   kScore[0] を鳴らし始める (node_04=0, node_03=8, node_04=16 拍ずらし)。
//   applyPattern が firedBeatNo と headRestBeats から実インデックスを算出する。
//
// 細分音符 (8 分音符など) は ScoreEvent 1 行内に subNote として持たせる仕組みが
// 残っているが、きらきら星は 4 分音符と 2 拍の伸ばしだけなので全行 subNote=0。
#pragma once
#include <Arduino.h>

struct ScoreEvent {
    uint16_t beatAt;       // 参考値: 1 始まりの拍番号 (ログ可読性のため。進行は index 駆動)
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
