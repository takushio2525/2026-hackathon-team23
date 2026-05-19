# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-19**: 夜間レビュー PR #8（`claude/nightly-report-2026-05-18`、
  `.agent/reports/2026-05-18.md`）の **取り込み + 残存指摘の修正**。
  PR #8 は `24a1a05` 時点のスナップショットを見ており、レポート内の
  「次のアクション 1（High, 自走可）」6 件（1.1 / 1.2 / 1.3 / 1.4 / 1.7 / 2.1）を
  ドキュメントとコメントのみで対応可能と判断、1 コミットで一括反映した。
  1.5 / 1.6 / 2.x 系は方針判断・実機ビルド要のため明示的に保留。

## 直近の観点

1. **1.1 が High（SSOT 汚染）**: `.agent/architecture.md:159` の `ScoreEvent { beatOffset, midiNote, durationBeats, velocity }` は架空の 4 フィールド版。
   実体 `firmware/test_v2/node_02/include/score_data.h:21-32` は 9 フィールドで全部別名。
   AGENTS.md → `.agent/architecture.md` の導線で AI が一番最初に開くページなので、
   今回最優先で `beatAt/noteNumber/velocity/durationQ8/flags/subNote/subVelocity/
   subOffsetQ8/subDurationQ8` に置換、`durationQ8` 単位（1/256 拍）と `flags` ビット
   （bit0=NoteOn / bit2=休符）も補足。
2. **1.2 の楽器名「金管/木管/弦」**: `.agent/architecture.md:104` と
   `docs/src/content/docs/architecture/score.md:78` の 2 箇所で「オルガン/フルート/ベル」に
   置換。score.md は同一ファイル内に line 134 の正典表「オルガン/フルート/ベル/
   フルート（調整版）」があるので、line 78 表の直下に「楽器名は data/*.json に依存。
   下の正典表が正」と注記。`team/roles.md:96`「金管音色のサンプル合成試作」と
   `team/schedule.md:54,79` は当時の役割分担を残す方針なので**触らず保留**
   （レビューでも user 判断要とされていた）。
3. **1.3 / 1.4 の partId 範囲**: pc_app 側（`.pde:39`・`README.md:56`）は test_v2 単独表記
   「0x02-0x04」を、ファーム側（`OrcProtocol.h:53`）は production 想定単独「0x02-0x05」を、
   それぞれ「test_v2 0x02-0x04 / production 想定 0x02-0x05」併記表現に揃えた。
   `.agent/api.md:50` の表現と一文で対応。
4. **1.7 の instrumentId 補足**: `.pde` ヘッダ line 8-9 には既に「ファイル名昇順で
   0,1,2,3…」が書かれていたが、line 39 のフィールド表「楽器番号 — data/ の何番目」が
   曖昧だったので、`data/*.json をファイル名昇順ソートしたときの index` と明示。
5. **2.1 の sed 過誤**: `node_03/src/score_data.cpp:6,17` と `node_04/src/score_data.cpp:6,17`
   で「(node_03/03/04)」「(node_03=0,」「(node_04/03/04)」「(node_04=0,」と
   sed コピーミスが残っていた。コメントのみなのでビルド/挙動への影響なし。
6. **保留したもの（変更しない理由を 1 行で）**:
   - 1.5 `firmware/production/node_01/platformio.ini` board 修正: 実機ビルド検証要、**3 夜連続保留**
   - 1.6 `report/計画書_中間発表/` PDF 追補: LuaLaTeX ローカル + 5 台/3 台方針判断要、user 作業
   - 2.2 NoteSender/OrcReceiver common 化: 実機テスト要、Med-High（2.1 と組合せて根治候補）
   - 2.3 `int32_t` wraparound: ハッカソン稼働時間で実害なし、Low
   - 2.4 CI に production 追加: 1.5 解決後、Med
   - 2.5 SoftAP 平文: 意図的設計、Low
7. **docs build 検証**: `cd docs && npm run build` → 70 ページ生成、リンク切れ無し。
   sitemap warning は `site` 未指定の既知・無関係。

## 次の一手

- **コミット + push**: 残存修正は `[ドキュメント] 夜間レビュー 2026-05-18 指摘 1.1-1.4/1.7/2.1 の残存乖離を一括修正` で `029fef0` として済。
  作業文脈更新は別コミットで `[ドキュメント] .agent/ 作業文脈を夜間レビュー 2026-05-18 対応で最新化` 想定。
- **PR #8 を close**: レポート本体は cherry-pick で取り込み済み（`0808e52`）、
  残存修正も反映済みなので、対応コミット sha を貼ったコメント付きで close。
- **次回ユーザーが実機を出せるタイミングで着手**:
  - 1.5 `firmware/production/node_01/platformio.ini` を XIAO ESP32-S3 設定に変更（**3 夜連続**）
  - 2.1 と 2.2 を組合せて NoteSenderModule / OrcReceiverModule / score_data.cpp を `common/lib/` に集約
- **中間発表 LaTeX**: トピック A の 5 台 / 3 台 / 4 台の方針判断が user 判断要。
  決まったら `plan_25G1021.tex` 本文・楽器名・PDF 追補をまとめて 1 コミットで。

## 現フェーズで Read すべき設計書

- 夜間レビュー対応中: `.agent/reports/2026-05-18.md`（指摘の根拠引用）と
  `.agent/architecture.md` / `.agent/api.md`（SSOT）を都度参照
- 実機作業に進む場合: `.agent/architecture.md` の楽器ノード節 + 該当 node の
  `ProjectConfig.h` を Read

## ユーザーの今回の好み

- **autonomous モード継続**: 「make the reasonable call and continue」で、
  「ドキュメント＆コメントのみで CLAUDE.md ルール抵触なし」と判断できた 6 件は
  質問返さず即修正、実機要・方針要は保留と理由付きで明示。
- **質問返しせず即着手**: 「夜間ログ処理 / マージと修正」の短い指示に対し、
  PR #8 確認 → cherry-pick 取り込み → 残存箇所 grep 確認 → 1 コミット修正 →
  docs build 検証の流れで一気通貫。

## 既知の論点

- **指摘 1.5 が 3 夜連続保留**（2026-05-15 / 17 / 18）。CI で拾えない（production 配下が
  matrix 対象外）ことが累積指摘の根本原因。レポート 2.4 (b)「production を CI 外と
  明文化」も選択肢だが、雛形が壊れたまま参照されるリスクの方が大きいので、
  user 側で `pio run -d firmware/production/node_01` を 1 回回すのが解。
- **レビュー bot の sha 乖離は今回は起きていない**（PR #8 本文の `24a1a05` と
  cherry-pick 時の main 先頭が一致）。だが今後も起こる前提で
  `.agent/conventions.md` への運用追記候補（毎朝 sha 照合）は残り。
- **`progress.md` 記述粒度**: レポート 4-B「指摘 N.M のうち XX 件を対応」明示の
  習慣化を、今回のエントリから採用（6 件中 6 件対応 / 6 件保留と明示）。
- **score_data.cpp 三重複の構造的問題**: 2.1 の sed 過誤は「3 ノード分の
  score_data.cpp を手で揃える運用が確実に壊れる」サイン。レポート 3.1 の
  `tools/sync_score.sh` 提案 or 2.2 の common 化のどちらかで根治したい。
