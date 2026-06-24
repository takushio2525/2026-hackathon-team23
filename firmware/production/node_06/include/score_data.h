// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/production/node_06
//   pio run -d firmware/production/node_06 -t upload
//   pio device monitor -d firmware/production/node_06
//
// ドラム楽譜データ — 56 拍分 (輪唱サイクル全体を担当)。
// 齋藤版 (week9/kaeru_score_debug) の createDrumScore() を静的配列に展開したもの。
//
// GM ドラムマップ: 36=キック, 38=スネア, 42=ハイハット, 49=クラッシュ
// 拍頭にキックまたはスネア、裏拍 (subNote) にハイハットを入れる基本パターン。
// 各声部の入り (0/8/16/24 拍) にクラッシュ、終盤 4 拍にフィルを入れる。
//
// headRestBeats=0 でサイクル全体を通しで演奏する（金管のように頭ずらししない）。
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
