# 完了タスクの時系列

> 毎ターン**追記**する（上書きしない）。50 件超で `progress-archive.md` への移送を提案。
> 形式: `- YYYY-MM-DD: 一行サマリ（関連コミット）`

## 2026-05 — ドキュメント刷新フェーズ

- 2026-05-15: docs/ に「要点ダイジェスト（まず読む）」章を新規追加（`essentials/` 配下 4 ページ）。①プロジェクト全体・②ファームウェア・③Processing・④音声解析を、それぞれ 10〜15 分で読み切れる優しい入門として整備。詳細群（`deep-dive/` `firmware/` `pc-audio/`）が増えすぎて初学者の入り口が無くなった問題への回答。各ページは「この章で分かること → 全体図（Mermaid）→ 登場人物 → 中核理屈 → 用語ミニ辞典 → 次に読むべき詳細」の統一構造。CTRL/BEAT/NOTE の役割、EMA 3 フェーズ、加算合成と倍音、9 段の解析パイプラインまで、数式・コードは要所だけに絞って絵的に解説。`astro.config.mjs` のサイドバーは「はじめに」直下に新セクションを置き、`index.md` 上部にも 4 本への直接導線を追加。`npm run build` で 70 ページ生成成功（66→70）。リンク切れ・slug エラーなし
- 2026-05-15: docs/ に「PC アプリ・音声処理（塩澤の実装例）」章を新規追加（`pc-audio/` 配下 11 ページ・合計 3500 行超）。設計層 2 本（design・signal-flow）、Processing 層 4 本（resynth-main・resynth-voice・instr-model・serial-handling）、解析層 3 本（analyzer-overview・analyzer-harmonics・analyzer-modulation）、移行支援 1 本（extending）、index 1 本。各ページは「実体ファイル → 役割 → データ構造 → 中の数学/コード → 落とし穴 → どこを書き換えるか表」の統一構造で、**「塩澤の実装は一例、他メンバーが自分の方針で書き直すための参考」**のトーンを全ページに分散。`orchestra_resynth.pde`（720 行）と `analyzer.py`（670 行）を題材に、加算合成数式（非調和性 f_n=n·f0·√(1+B·n²)、ビブラート pitchMul=2^(Δcent/1200) 等）、シリアル受信のスレッド分離（ConcurrentLinkedQueue）、pyin と自己相関の 2 段基音検出、ADSR 当てはめのアルゴリズム、FFT/STFT による倍音抽出と残差ノイズ分離まで実コード基準で解剖。`code/pc-app.md` の「さらに深掘りしたい」に新章への導線を追加。`astro.config.mjs` にサイドバー登録（ファーム章の直下）、`npm run build` で 66 ページ生成成功（55→66）。リンク切れ・slug エラーなし
- 2026-05-15: docs/ に「ファームウェア モジュール詳説」章を新規追加（`firmware/` 配下 12 ページ・合計 4000 行超）。共通 5 本（IModule/ModuleTimer・OrcProtocol・OrcNetModule・StatusLedModule・SerialDebug）、指揮者 2 本（ImuModule・OrcSenderModule）、楽器 2 本（OrcReceiverModule・NoteSenderModule）、統合 2 本（main-conductor・main-instrument）、index 1 本。各ページは「実体ファイル → 役割 → Config/Data → init() → updateInput/Output → 落とし穴」の統一構造で、責務境界（書くフィールド/読むフィールド）を表で明示。`code/firmware.md` から導線を追加。`astro.config.mjs` にサイドバー登録、`npm run build` で 55 ページ生成成功（43→55）。`serial-debug.md` の frontmatter description にバッククォートを入れて YAML パース失敗 → ダブルクォート化で解決
- 2026-05-14: docs/ に「アルゴリズム詳説」章を新規追加（`deep-dive/` 配下 8 ページ・合計 1700 行超）。拍検出・時刻同期・UDP マルチキャスト・バイナリパケット・楽譜進行・加算合成・モジュール拡張を実コード基準で深掘り。同時に既存 `architecture/protocol.md` `score.md` `sync.md` と `.agent/api.md` の実装乖離（`bpmQ8 ×8` / NOTE フィールド順 / `kScore/kScoreLength` / `ScoreEvent` 構造 / 楽器側発音は次ループ判定）を最小修正。`architecture/` と `code/` の既存ページ末尾に「さらに深掘りしたい」リンクを追加して学習導線を接続。サイドバー（`astro.config.mjs`）に新セクション追加、`npm run build` で 43 ページ生成を確認
- 2026-05-14: 所属表記の矛盾を修正。誤「工学院大学 情報通信工学科」→ 正「千葉工業大学 情報変革科学部 情報工学科」に AGENTS.md / docs/index.md / docs/intro/overview.md / docs/concept/why.md の 4 ファイルを一括置換。grep で残存ゼロを確認
- 2026-05-14: 第 4 回議事録（2026-05-13）反映で docs/ 全面整合。サイトタイトルを「タクトーン」に切替（astro.config.mjs / index.md）、`concept/why`・`concept/goals`・`intro/overview` に議事録 9〜10 章の目的・対象/非対象・成果物・既存技術差分を反映、`team/schedule` を計画書 11〜13 章で全面書き直し（4 フェーズ・WBS 表・MOE/MOP/TPM・5/20 プレゼン担当）、`team/roles` にプレゼン章別担当を追加。`npm run build` 通過
- 2026-05-14: AGENTS.md 中心構成へフル移行（`b3f3b67`）と docs/ の Astro Starlight 化・初学者向け 35 ページ整備（`dc3da4f`）、関連 README 整合（`09c530d`）を一括 push。次の検討は GitHub Pages 公開先決定と未公開 ADR の追加
- 2026-05-13: 発表用 rink ファイルを新規追加（`1d11877`）。シリアルデバッグ出力を無効化（`fd7eb18`）

## 2026-05 — test_v2 / 計画書整備

- 2026-05-09 前後: 提出用計画書（基本設計・詳細設計）整理と再コンパイル（`906f85b` 他）
- 2026-05-05 前後: ADR-0006「同期誤差 20 ms」の根拠を河瀬2014「数10ms」に修正（`c862dad`）
- 2026-05-05 前後: Git ワークフロー方針を更新（基本 main 直マージ、PR は作業完了時のみ）（`4022184`）

## 2026-04 — test_v2 立ち上げ

- 2026-04-下旬: `test_v2` で「きらきら星」3 声輪唱 + 楽器番号付き NOTE + PC 側加算合成（`64032cd`）
- 2026-04-下旬: `firmware/test` → `firmware/test_v1` にリネーム（`eb19771`）

## 2026-04 — 初期セットアップ

- 2026-04-21: ADR-0005 採択（Embedded-Module-Architecture をファーム全体に適用）
- 2026-04-22: 第 2 回 MTG。塩澤が Arduino 全般を一括担当、楽器ノードもまとめて設計・実装する運用に変更
- 2026-04-15: 第 1 回 MTG。指揮者ノードに IMU を採用（ADR-0003）、5 台構成決定（ADR-0004）、UDP オリジナルプロトコル方針（ADR-0002）
