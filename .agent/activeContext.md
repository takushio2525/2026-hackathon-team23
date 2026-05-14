# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-14**: docs/ の充実化フェーズ第 2 弾。これまで `architecture/` `code/` は
  120〜270 行で「概要 + 中核解説」レベルだったが、ユーザー要求「順々に深く読み進めていく
  学習導線」「ロジックや仕組みの解説をどんどん入れる」に応えるため、新セクション
  **「アルゴリズム詳説」** を追加し、プログラム系の中核アルゴリズムを 8 ページに渡って
  深掘りした（`docs/src/content/docs/deep-dive/`）。

## 直近の観点

1. 既存ページの中身と実コードに**乖離**が複数あったため、deep-dive を書く前に最小修正：
   - CTRL の `bpmFixed × 256` → `bpmQ8 × 8`
   - NOTE のフィールド順（実装は `partId/noteNumber/velocity/gate/durationMs/instrumentId`）
   - `SCORE_DATA[]/SCORE_TOTAL_BEATS` → `kScore[]/kScoreLength`
   - `ScoreEvent` 構造（`beatAt, noteNumber, velocity, durationQ8, flags, subNote, ...`）
   - 楽器側発音は `delay()` ではなく次ループ判定（`waitMs > 0` で先送り）
   修正先: `architecture/protocol.md`、`architecture/score.md`、`architecture/sync.md`、
   `.agent/api.md`
2. deep-dive 章を新規 8 ページ作成（合計 1700 行超）：
   - `deep-dive/index.md` — 読み順ガイド・前提・各ページの位置づけ
   - `deep-dive/beat-detection.md` — LPF/動加速度ノルム/状態機械/経路長積分/閾値根拠
   - `deep-dive/time-sync.md` — EMA オフセット推定/playAtMasterMs/誤差予算
   - `deep-dive/udp-multicast.md` — UDP/SoftAP/239.0.0.1/IGMP/OrcNetModule 実装
   - `deep-dive/binary-packet.md` — pragma pack/エンディアン/static_assert/Processing パース
   - `deep-dive/score-progression.md` — firedBeatNo→scoreIndex 変換/輪唱/細分音符/途中起動耐性
   - `deep-dive/additive-synthesis.md` — 倍音/非調和性/ADSR/ボイスプール/ノイズ/モジュレーション
   - `deep-dive/module-extension.md` — IModule 拡張手順 step-by-step/落とし穴/トラブルシューティング
3. 既存ページ（`architecture/{overview,ema,protocol,score,sync}.md`、`code/{firmware,pc-app}.md`）の
   末尾に「さらに深掘りしたい」セクションを追加して深掘り章への導線を作成
4. サイドバー設定 `docs/astro.config.mjs` に「アルゴリズム詳説」セクションを追加
5. `npm run build` 実行: 43 ページ生成、リンク切れ・slug エラーなし（`deep-dive/index` 指定を
   Starlight 仕様の `deep-dive` に修正してから通過）

## 次の一手

- **コミット 〜 push**: `[ドキュメント] アルゴリズム詳説章を新規追加し既存ページと実装乖離を修正` で
  1 コミット（今回はドキュメントだけの変更）
- **追加の深掘り候補**（次セッション以降）:
  - `deep-dive/imu-i2c.md` — MPU6050 / I2C レジスタアクセスの詳細
  - `deep-dive/platformio-build.md` — `platformio.ini` / `lib_extra_dirs` / `build_flags` の解剖
  - 残された乖離: `code/firmware.md` の楽器側説明、`code/pc-app.md` の旧 NOTE 順記述（一部）
- **次の整備項目**: ADR 系の追加（test_v2 の楽譜進行を拍番号駆動にした経緯、サウンドラボ JSON
  フォーマット採択の経緯など）

## ユーザーの今回の好み

- 「ロジックや仕組みについての解説をどんどん入れてほしい」「順々に詳しい内容に読み進めていく
  学習導線」を明示。深掘りページは数式・状態機械・コード断片を含めて 200〜500 行で書く方針が
  受け入れられた（手前で確認なし即着手）
- 既存ドキュメントの実装乖離は **発見次第その場で潰す**（深掘りページで矛盾を増幅させないため）

## 既知の論点

- `architecture/protocol.md` の test_v2 NOTE 順は修正済みだが、`code/pc-app.md` の Processing
  パース例にも旧オフセット記述がうっすら残っている（実コードと一致しているのでビルドは通る
  が、要・追跡）
- 深掘り章は Mermaid / KaTeX を使えればさらに見やすくなるが、Starlight Paper Theme の現行
  設定ではプレーン Markdown のまま。数式は LaTeX 風コードブロックで表現中
