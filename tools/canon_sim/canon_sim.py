#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_v3 4 台輪唱の机上シミュレーション。

firmware/test_v3 の楽器ノード applyPattern.cpp の楽譜進行ロジック
(輪唱サイクル窓方式) を Python で忠実に再現し、拍番号 1〜120 で
4 ノード (node_02〜05, headRestBeats=0/8/16/24) の発音タイミング表を
生成・検証する。

再現対象 (node_0X/src/applyPattern.cpp 楽譜進行部):
    cyclePos = (firedBeatNo - 1) % CANON_CYCLE_BEATS
    local    = cyclePos - headRestBeats
    if 0 <= local < kScoreLength: fire(kScore[local])

検証項目:
    1. 各声部の入り拍が 1/9/17/25 (8 拍ずつズレて入る)
    2. 各声部の楽譜 idx が周回内で 0..31 を欠落なく連続消化する
    3. 輪唱性: rest=r の声部が拍 b で鳴らす idx は、先頭声部が拍 b-r で
       鳴らした idx と一致する (= 完全な r 拍遅れカノン)
    4. 終端: 拍 33..56 で node_02 が沈黙し (次周回を始めない)、
       拍 49..56 は node_05 のみ、拍 57 で node_02 が idx=0 から再入する
    5. 2 周目 (拍 57..112) も 1 周目と同一パターン

比較シナリオ (実機の聞こえ方の切り分け用):
    A. 現 HEAD     : CANON_CYCLE_BEATS=56 のサイクル窓 (上記)
    B. 旧 test_v3  : effective % 32 の無限周回 (80ec121 以前)
    C. test_v2 残留: 24 拍曲を 2 周直書き kScoreLength=48・% 48
                     (2026-05-27 に実機へ書き込まれた最後の楽器ファーム)

実行: python3 tools/canon_sim/canon_sim.py
"""

CANON_CYCLE_BEATS = 56   # 全ノード ProjectConfig.h logic_params と一致
SCORE_LEN_V3 = 32        # test_v3 score_data.cpp の kScoreLength
HEAD_REST = {"node_02": 0, "node_03": 8, "node_04": 16, "node_05": 24}
NODES = list(HEAD_REST.keys())

# test_v3「かえるのうた」32 拍 (score_data.cpp と同順)。表示用の音名。
SCORE_V3 = [
    "ド", "レ", "ミ", "ファ", "ミ", "レ", "ドー", "・",      # フレーズ 1
    "ミ", "ファ", "ソ", "ラ", "ソ", "ファ", "ミー", "・",    # フレーズ 2
    "ド", "・", "ド", "・", "ド", "・", "ド", "・",           # フレーズ 3
    "ドド", "レレ", "ミミ", "ファファ", "ミ", "レ", "ドー", "・",  # フレーズ 4
]
assert len(SCORE_V3) == SCORE_LEN_V3

# test_v2「かえるのうた」24 拍×2 周直書き (kScoreLength=48)。
# フレーズ: ドレミファミレドー / ミファソラソファミー / ドドドドドドドー
SCORE_V2_24 = (
    ["ド", "レ", "ミ", "ファ", "ミ", "レ", "ドー", "・"]
    + ["ミ", "ファ", "ソ", "ラ", "ソ", "ファ", "ミー", "・"]
    + ["ド", "ド", "ド", "ド", "ド", "ド", "ドー", "・"]
)
SCORE_V2 = SCORE_V2_24 * 2   # 48 行
SCORE_LEN_V2 = len(SCORE_V2)


def fire_head(beat_no: int, head_rest: int):
    """A. 現 HEAD: サイクル窓方式。発音するなら楽譜 idx、しないなら None。"""
    cycle_pos = (beat_no - 1) % CANON_CYCLE_BEATS
    local = cycle_pos - head_rest
    if 0 <= local < SCORE_LEN_V3:
        return local
    return None


def fire_old_v3(beat_no: int, head_rest: int):
    """B. 旧 test_v3 (80ec121 以前): effective % 32 の無限周回。"""
    effective = beat_no - 1 - head_rest
    if effective >= 0:
        return effective % SCORE_LEN_V3
    return None


def fire_v2(beat_no: int, head_rest: int):
    """C. test_v2 残留ファーム: 24 拍曲×2 周直書き % 48。"""
    effective = beat_no - 1 - head_rest
    if effective >= 0:
        return effective % SCORE_LEN_V2
    return None


def build_table(fire_fn, score, max_beat: int):
    """beatNo 1..max_beat の発音表 {node: [idx or None]} を作る。"""
    return {
        n: [fire_fn(b, HEAD_REST[n]) for b in range(1, max_beat + 1)]
        for n in NODES
    }


def print_table(title, table, score, max_beat, nodes=NODES):
    print(f"\n{'=' * 100}\n{title}\n{'=' * 100}")
    header = f"{'拍':>4} | " + " | ".join(f"{n:^14}" for n in nodes)
    print(header)
    print("-" * len(header))
    for b in range(1, max_beat + 1):
        cells = []
        for n in nodes:
            idx = table[n][b - 1]
            cells.append(f"{'—':^14}" if idx is None
                         else f"[{idx:2d}] {score[idx]:<6}"[:14].ljust(14))
        print(f"{b:>4} | " + " | ".join(cells))


def verify_head(table, max_beat):
    """現 HEAD ロジックの検証アサーション。すべて通れば輪唱成立の数値証明。"""
    results = []

    # 1. 入り拍 = headRest + 1 (8 拍ずつズレて入る)
    for n in NODES:
        first = next(b for b in range(1, max_beat + 1) if table[n][b - 1] is not None)
        expected = HEAD_REST[n] + 1
        ok = (first == expected)
        results.append((f"入り拍: {n} は拍 {expected} で入る (実測 {first})", ok))

    # 2. 各周回で idx 0..31 を欠落なく連続消化
    n_cycles = max_beat // CANON_CYCLE_BEATS
    for n in NODES:
        for c in range(n_cycles):
            seq = [table[n][b - 1]
                   for b in range(c * CANON_CYCLE_BEATS + 1,
                                  (c + 1) * CANON_CYCLE_BEATS + 1)
                   if table[n][b - 1] is not None]
            ok = (seq == list(range(SCORE_LEN_V3)))
            results.append(
                (f"周回 {c + 1}: {n} の楽譜 idx が 0..31 を欠落なく消化", ok))

    # 3. 輪唱性: rest=r の声部の拍 b の idx == 先頭声部の拍 b-r の idx
    for n in NODES[1:]:
        r = HEAD_REST[n]
        ok = True
        for b in range(1, max_beat + 1):
            idx = table[n][b - 1]
            if idx is None:
                continue
            if b - r < 1 or table["node_02"][b - r - 1] != idx:
                ok = False
                break
        results.append((f"輪唱性: {n} は node_02 の完全な {r} 拍遅れ", ok))

    # 4. 終端: 拍 33..56 で node_02 沈黙 / 49..56 は node_05 のみ / 57 で再入
    ok = all(table["node_02"][b - 1] is None for b in range(33, 57))
    results.append(("終端: 拍 33..56 で node_02 は次周回を始めない", ok))
    ok = all(
        table[n][b - 1] is None
        for b in range(49, 57) for n in ("node_02", "node_03", "node_04")
    ) and all(table["node_05"][b - 1] is not None for b in range(49, 57))
    results.append(("終端: 拍 49..56 は node_05 のみが演奏 (3 台構成なら全員無音)", ok))
    ok = (table["node_02"][57 - 1] == 0 and table["node_05"][56 - 1] == 31)
    results.append(("終端: node_05 が拍 56 で idx=31 を終え、拍 57 で node_02 が idx=0 再入", ok))

    # 5. 2 周目 (57..112) が 1 周目 (1..56) と同一
    for n in NODES:
        ok = all(table[n][b - 1] == table[n][b + CANON_CYCLE_BEATS - 1]
                 for b in range(1, CANON_CYCLE_BEATS + 1))
        results.append((f"周期性: {n} の 2 周目は 1 周目と同一パターン", ok))

    print(f"\n{'=' * 100}\n検証アサーション (現 HEAD ロジック)\n{'=' * 100}")
    all_ok = True
    for desc, ok in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {desc}")
        all_ok &= ok
    print(f"\n  => 総合: {'すべて PASS — 4 声輪唱は数値的に成立' if all_ok else 'FAIL あり — バグ'}")
    return all_ok


def main():
    max_beat = 120

    # A. 現 HEAD
    table_head = build_table(fire_head, SCORE_V3, max_beat)
    print_table("A. 現 HEAD (CANON_CYCLE_BEATS=56 サイクル窓) — 拍 1..120",
                table_head, SCORE_V3, max_beat)
    ok = verify_head(table_head, max_beat)

    # B. 旧 test_v3 (% 32 無限周回) — 終端の違いだけ要点表示
    table_old = build_table(fire_old_v3, SCORE_V3, max_beat)
    print(f"\n{'=' * 100}\nB. 旧 test_v3 (% 32 無限周回) との差分 — 拍 33..60 のみ\n{'=' * 100}")
    print("旧方式は拍 33 で node_02 が勝手に 2 周目へ入る (終端なし):")
    for b in range(33, 61):
        cells = []
        for n in NODES:
            idx = table_old[n][b - 1]
            cells.append(f"{'—':^14}" if idx is None
                         else f"[{idx:2d}] {SCORE_V3[idx]:<6}"[:14].ljust(14))
        print(f"{b:>4} | " + " | ".join(cells))

    # C. test_v2 残留ファーム (24 拍曲 % 48) — 入りは同じだが曲が別物
    table_v2 = build_table(fire_v2, SCORE_V2, max_beat)
    print(f"\n{'=' * 100}\nC. test_v2 残留ファーム (24 拍曲×2 % 48) — 拍 1..56\n{'=' * 100}")
    print("入り拍 (1/9/17/25) は同じだが、楽譜が 24 拍周期の旧曲なので")
    print("test_v3 (32 拍) と混在すると拍 17 以降フレーズがすれ違い輪唱に聞こえない:")
    for b in range(1, 57):
        cells = []
        for n in NODES:
            idx = table_v2[n][b - 1]
            cells.append(f"{'—':^14}" if idx is None
                         else f"[{idx:2d}] {SCORE_V2[idx]:<6}"[:14].ljust(14))
        print(f"{b:>4} | " + " | ".join(cells))

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
