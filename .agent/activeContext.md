# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-15**: docs/ 充実化フェーズ第 3 弾。アルゴリズム詳説（数学・状態機械・理論的根拠）
  を 5/14 で書いたので、今回は **「モジュール」を主役にした実装解説章** を追加。
  ユーザー要望「ファームウェアについて、各モジュールの実装内容や詳しい解説、メインでの処理
  フローとか、実際のコードについての詳しい解説を追加」「モジュールメインな方針で」に応える形。

## 直近の観点

1. 新セクション **「ファームウェア モジュール詳説」** を独立で追加（`docs/src/content/docs/firmware/`）。
   既存「アルゴリズム詳説」（`deep-dive/`）と並ぶ位置に置いた。サイドバーは
   `astro.config.mjs` で 9 番目のセクションとして登録
2. 全 12 ページを `firmware/` 配下にフラットで配置（カテゴリ別ネストは UX を悪化させるため避けた）:
   - `index.md` — 読み順ガイド・モジュール一覧マップ
   - 共通 5 本: `imodule.md` / `orc-protocol.md` / `orc-net.md` / `status-led.md` / `serial-debug.md`
   - 指揮者 2 本: `imu-module.md` / `orc-sender.md`
   - 楽器 2 本: `orc-receiver.md` / `note-sender.md`
   - 統合 2 本: `main-conductor.md` / `main-instrument.md`
3. 各ページは統一フォーマット:
   - 実体ファイルパス（`firmware/test_v2/...`）と行数
   - 役割と責務（書くフィールド / 読むフィールド の表）
   - Config / Data 構造体の全フィールド意味
   - `init()` の初期化シーケンス
   - `updateInput/Output` の処理フロー
   - 落とし穴セクション（実機で踏んだ罠を実コードコメントから抽出）
   - 関連ページへのリンク
4. `code/firmware.md` の末尾「さらに深掘りしたい」に新セクションへの導線を追加
5. `npm run build` で **55 ページ生成成功**（43 → 55、新規 12 ページ）。リンク切れ・slug エラーなし
6. ビルド中に踏んだ唯一の罠: `serial-debug.md` の frontmatter description に
   バッククォート ``` ` ``` を入れたら YAML パーサが失敗。ダブルクォートで括って解決

## 次の一手

- **コミット 〜 push**: `[ドキュメント] ファームウェア モジュール詳説章を新規追加` で 1 コミット
  （ドキュメントだけの変更）
- **次に深掘りしたい候補**:
  - `firmware/platformio-build.md` — `platformio.ini` / `lib_extra_dirs` / `build_flags` の解剖
  - `firmware/score-data.md` — `kScore[]` フォーマットと `score_data.cpp` の書き方
  - PC アプリ側のモジュール詳説（`orchestra_resynth.pde` の内部構成）
- **既存ドキュメントとの整合**: `code/firmware.md` 自体も将来「概要だけ残し詳細は新章に委譲」
  形にリファクタしてもよい

## ユーザーの今回の好み

- 「モジュールメインな方針」を明示。横断的なアルゴリズム解説（5/14 で書いた deep-dive）とは
  別軸で、**コードファイル 1 つにつき 1 ページ** の縦割り解説を望んだ
- 「実装内容や詳しい解説、メインでの処理フロー、実際のコードについての詳しい解説」と
  「コード基準」を重視
- 質問返しせず即着手の運用が継続好まれている（system-reminder の `Work without stopping for
  clarifying questions` も明示）

## 既知の論点

- `code/firmware.md` は依然「ツアー形式の入り口」として残し、深掘りは新章に移譲した形。
  今後、深掘り側に厚みが出てきたら入り口側はさらに短く（あるいは廃止）する選択肢あり
- 楽器ノードの `gOutputs` 配列に `gNet` が入っているが実質何もしない件は、
  `main-instrument.md` 内で「将来送信したくなったときのためのプレースホルダ」と説明済み
- `node_02/03/04` の `applyPattern.cpp` / `score_data.cpp` は完全同一だが、現状は
  3 ファイルコピペで運用。`common/lib/` への共通化はリスク（楽譜編集時の同期忘れより
  バージョン差分が出る方が怖い）と判断したまま
