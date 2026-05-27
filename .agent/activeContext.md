# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v2 のジッタ削減と多重受信処理の改善**（2026-05-27、ユーザー指示）。
  応答性が悪い・連送 BEAT の 2 個目以降が消されている雰囲気、という指摘への対応。
  挑戦的変更のため `shiozawa-test_v2-jitter` ブランチを切って作業。`shiozawa-work` には未マージ。
  実機書き込みは未実施（AGENTS.md「実機未テスト .ino/.cpp に Claude 起点で追加変更を
  入れない」ルール準拠でユーザーに委ねる）。
  - 変更ファイル (3 ノード × 2 種類 + 3 ノードの ProjectConfig = 9 ファイル):
    - `firmware/test_v2/node_02/03/04/lib/OrcReceiverModule/OrcReceiverModule.h`
    - `firmware/test_v2/node_02/03/04/lib/OrcReceiverModule/OrcReceiverModule.cpp`
    - `firmware/test_v2/node_02/03/04/include/ProjectConfig.h`
  - 変更内容:
    1. **ループ周期 5 ms → 2 ms** (`loopIntervalMs`): 発火判定ジッタを最大 5 ms → 2 ms に。
    2. **`clockSyncEmaAlpha` 0.10 → 0.20**: 初回サンプル吸込みを倍速化。時定数 ≈0.5 s → ≈0.25 s。
    3. **`clockSyncEmaAlphaDup` 新設 = 0.05**: 同一 beatNo の連送 2 個目以降に使う EMA 係数。
       旧実装は連送 4 個を全て α=0.10 で吸って同じサンプルに 4 回追従していた
       (= 強相関を独立サンプル扱いして過剰反映)。新実装は初回 0.20 + 重複 0.05×3 で
       4 連送合計影響 ≈ 0.32 (初回 α 単独に近い吸い方)。
    4. **重複時の updateClockOffset 呼び出しを継続**: 元から呼ばれていたが意図が曖昧
       だったのでコメントで「sync 用には 4 連送ぶん全部使う・ただし α を分ける」を明記。
    5. **pending (発音予約) は初到着 1 個固定**を維持: 連送 payload は同一なので
       2 個目以降で上書きする意味がなく、むしろ「発火後の後着で再キューして二重発音」
       事故を避けるため初回のみ。
  - ビルド: 3 ノードとも `pio run` SUCCESS (Flash 20.9% / RAM 20.6%、変化なし)。
  - **実機書き込み済み** (2026-05-27、ユーザー指示「各マイコンに書き込んで」):
    - node_02 (SER=34B7DA64482C → `/dev/cu.usbmodem34B7DA64482C2`): bossac 3.41 秒・total 6.38 秒
    - node_03 (SER=F412FAA08558 → `/dev/cu.usbmodemF412FAA085582`): bossac 3.55 秒・total 5.67 秒
    - node_04 は未接続のため書き込み不可 (2 声輪唱で評価開始)
    - 指揮者 `node_01_devkitc` は今回のブランチでコード変更なしのため書き込まず
      (改修対象は楽器側の OrcReceiverModule と ProjectConfig のみ)
    - 書き込み時 Processing は停止確認済み
  - 次の一手: Processing 起動 → 応答性 (振り→発音遅延) と連続スイング時の発音タイミング滑らかさ、
    パケロス時挙動を耳とログで評価。rollback したい場合は `git checkout shiozawa-work` で元ファームに戻れる。

- **test_v2 の楽曲を「きらきら星」→「かえるのうた」に差し替え済み**（2026-05-27、
  ユーザー指示）。`firmware/test_v2/node_02/03/04/src/score_data.cpp` の 3 ファイル。
  きらきら星は構造が複雑で輪唱の聞き分けが難しい (≒同型反復で 8 拍ずれが分かりに
  くい) ため、3 フレーズで識別しやすい「かえるのうた」に。
  - 1 周 = 24 拍 (ドレミファミレドー / ミファソラソファミー / ドドドドドドドー)
  - kScoreLength=48 を維持 (24 拍版を 2 周ぶん直書き)
  - `headRestBeats=0/8/16` (ProjectConfig.h) は不変 → 楽譜内位相が (0, 8, 16) と
    3 声とも違うので輪唱成立。16 拍版にすると node_04 が node_02 と完全同位相に
    なるため 24 拍周期を選択。
  - 3 ノードとも `pio run` で SUCCESS (Flash 20.9% / RAM 20.6%)。
  - **node_02/03 は実機書き込み済み** (2026-05-27、ユーザー指示):
    - node_02 (SER=34B7DA64482C → `/dev/cu.usbmodem34B7DA64482C2`): bossac
      3.43 秒・total 6.12 秒・Hash verified
    - node_03 (SER=F412FAA08558 → `/dev/cu.usbmodemF412FAA085582`): bossac
      3.49 秒・total 5.41 秒・Hash verified
    - 初回試行時 Processing (orchestra_resynth, PID 54869) が両ポートを掴んで
      `[Errno 16] Resource busy` で失敗。ユーザーに Processing 終了を依頼して
      再書き込み成功。
  - node_04 は未接続のため未書き込み (前回 2026-05-27 のときと同じ状態)。
- 指揮者 `node_01_devkitc` は楽譜を持たない (`score_data.cpp` なし) ため、今回の
  楽曲差し替えでは書き込み不要。前回 `SERIAL_DEBUG=1` のまま (拍検出デバッグ用)。

## 次の一手

- `shiozawa-test_v2-jitter` ブランチで楽器 2 台 (node_02/03) を書き込み、応答性と
  多重受信時の挙動を耳とログで評価する (ユーザー作業)。改善体感があれば
  `shiozawa-work` (= main 代替) へマージ、駄目なら別 α/loopInterval 値で再試行。
- 評価観点:
  - 振り → 発音までの遅延感が下がっているか (loopInterval 5→2 ms + EMA α 倍速の効果)
  - 連続スイング時の発音タイミングが滑らかか (重複 α 分離による offset 安定化の効果)
  - パケロス時の挙動が変わっていないか (pending 初回固定は維持しているので原理的に同じ)
- 後続候補 (このブランチで評価成功後):
  - lookahead 50 → 30 ms 短縮 (`OrcSenderConfig.beatLookaheadMs`)
  - 発火直前マイクロ待機 (micros() スピン) で 2 ms ループ粒度を更に削る
- パケロス観察と ADR-0007 (パケロス対策方針＝DevKitC 移行) 起票は継続案件。

## 現フェーズで Read すべき設計書

- 作業ログ本体: `work/shiozawa/work-0525/作業ログ0525/作業ログ0525.tex`、
  教員配布テンプレ `report/作業ログテンプレート/作業ログ.tex`。
- パケロス対策の技術背景: `.agent/architecture.md`（プロトコル設計節）、
  `.agent/api.md`（UDP マルチキャスト構造・CTRL/BEAT/NOTE 仕様）。
- ADR-0007（パケロス対策方針）は起票予定で未存在。本格起票時は
  `report/計画書_中間発表/23_計画書・設計書.tex` の ADR 既存節フォーマットを参照。

## draw.io ワークフロー（再修正時の参照）

- 書き出し: `/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png
  --scale 2 --crop --border 14 --output 出力.png 入力.drawio`
- `.drawio` と `.png` を両方コミットする。`.png` を手で描き換えない。

## ガント図の整合基準（再修正時の参照）

- バー週数は **アロー図 `arrow.drawio` が正**: 110/120=各1.5週，210=0.5，220=1.0，
  230=0.5，240=1.0，250/260=各1.5，310/320=1.0，330=1.0，510=1.0週。図上 1週=66px。
- 絶対日付は授業スケジュール: 計画発表5/20・実装5/27〜・評価会6/24・発表会7/1。
- フェーズ工数は WBS 表: 設計3週・製造2週・テスト2週。
- クリティカルパスは逐次（階段配置）。240/250/260 は製造期間に並行・フロートあり。

## ユーザーの好み

- 大規模作業は計画を作ってから着手。設計章は大まかに（内容が伝われば可）。
- 図は draw.io に一本化（TikZ 廃止済み）。表が読みやすければ図を表化してよい。
- 短い指示は行間を読み，前提のズレを感じたら着手前に指摘する。

## 既知の論点

- 本体ページ数は **53頁が許容範囲**（§7「53〜54頁は許容範囲・無理な圧縮不要」）。
  図表が `[H]` 固定配置のため本文を数行足すと図の押し出しでページが増えやすい。
- 本体 .tex の句点は **「．」**（origin コミット 19edb91 で「。→．」一括統一済み）。
  本体 .tex を編集するときは句点を「．」で書く。.agent/ や .md 類は「。」のまま。
- CTRL state は現行ファーム整合で `0=Idle/1=Calibrating/2=Conducting/3=Fallback/4=ModeSelect`。
- ADR-0004 は楽器5台構成（金管4＋ドラム・全体6台）に改訂済み。改訂履歴を本文に明記。
- 状態遷移図はユーザー決定でシーケンス図を主図とし，節名「状態遷移図」は現状維持で決着（低⑪）。
  課題曲「かえるのうた」はチーム判断で確定（中⑦）。
- `.gitignore` に例外 `!report/計画書_中間発表/23_計画書・設計書.pdf` あり。本体 PDF はコミット対象。
- 図インベントリは全10点 draw.io（`_作業計画.md` §8）。
