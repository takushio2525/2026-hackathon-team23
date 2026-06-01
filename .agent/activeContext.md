# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v2 低遅延化・パケロス削減・堅牢化を実装**（2026-06-01、`shiozawa-test_v2-latency`
  ブランチ。`shiozawa-test_v2-jitter` から分岐＝jitter の実機検証済み土台が前提）。
  計画書 `.agent/test_v2-latency-plan.md` の「6. 実装項目」A/B/C を実装しコンパイル確認済み。
  実機 upload と最終評価はユーザー（鉄則: main に触らない／push しない／Claude はコンパイルまで）。
  - **A. 指揮者 config** (`node_01` と `node_01_devkitc` の `include/ProjectConfig.h`):
    `beatLookaheadMs` 50→30（playAt=now+30ms。連送受信完了 ~23ms にマージン約7ms）、
    `beatGapMs` 0→2（連送4発を2ms間隔で時間分散しradio のまとめ落ちを軽減）。
  - **B. 共通 OrcNetModule** (`common/lib/OrcNetModule/OrcNetModule.{h,cpp}`):
    `wasLinkUp_` メンバ追加。Sta 側で WiFi down→up 復帰を検出し `udp_.stop()` →
    `beginMulticast()` で UDP マルチキャスト購読を貼り直す。`init()` 末尾で `wasLinkUp_`
    を初期化（起動直後の偽 false→true 遷移で無駄な再joinを走らせない）。SoftAp 側は
    `isLinkUp()` が `started_` 依存で常時 true のまま＝この遷移が起きず無影響。
  - **C. Processing** (`pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde`):
    `getLineOut` バッファ 1024→512（約23.2ms→11.6ms）、`setup()` 冒頭に `frameRate(90)`
    明示（draw/drainPackets を 16.7ms→~11ms 粒度に）。
  - ビルド: 4ノードとも `pio run` SUCCESS（node_01_devkitc RAM14.0%/Flash21.6%、
    node_02/03/04 RAM20.6%/Flash20.9%＝jitter 時と同サイズ）。pio は
    `~/.platformio/penv/bin/pio`（非対話シェルの PATH に無いのでフルパス指定が必要）。

## 次の一手

- ユーザー作業: `shiozawa-test_v2-latency` を各マイコンへ upload して実機評価。
  - 指揮者は `node_01_devkitc`（DevKitC、A の config 変更あり）を書き込む。
  - 楽器 node_02/03/04 は B（OrcNetModule 再join）の変更を含むので書き込む。
  - Processing は C 適用済みの `.pde` を Open→Run（書き込み不要）。
- **実機で要確認**（B のリスク）: WiFiS3（UNO R4）で `udp_.stop()→beginMulticast()` を
  繰り返したときの挙動。AP を一度落として復帰させ、リンク復活後に BEAT/NOTE が再び
  受信できるか（再join が効くか）を確認。ESP32 側 Sta はこの構成に無いが将来流用時の注意。
- 評価観点: 振り→発音遅延が下がったか（lookahead 30 + audio512 + frameRate90）、
  連続スイングの滑らかさ、パケロス時の挙動（beatGap 2ms 分散の効果）。
- **5台構成（node_05/06）は保留＝master 確認事項**。計画書5節: かえるのうた1周24拍・
  輪唱 headRest 8拍刻みなので 0/8/16 で3声がちょうど一巡。4声以上を等間隔で重ねると
  24=0(node_02と同位相)/32=8(node_03と同位相)で破綻する。5声化は不等間隔位相 or
  楽曲周期延長＝**編曲（音楽判断）**が必要なので勝手に作曲せず保留。

## 現フェーズで Read すべき設計書

- 本作業の全体方針: `.agent/test_v2-latency-plan.md`（遅延チェーン分解・各改善の根拠）。
- ファーム構造: `.agent/architecture.md`（OrcNetModule の3フェーズループ責務）、
  `.agent/api.md`（UDP マルチキャスト・CTRL/BEAT/NOTE 仕様・OrcSenderConfig 各値）。

## ユーザーの好み

- 大規模作業は計画を作ってから着手。短い指示は行間を読み，前提のズレを感じたら着手前に指摘。
- 実機未テストの .ino/.cpp に Claude 起点で変更を入れたらコンパイル確認まで＝upload はユーザー。

## 計画書フェーズ用メモ（latency 作業では非アクティブ・再開時参照）

- draw.io 書き出し: `/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png
  --scale 2 --crop --border 14 --output 出力.png 入力.drawio`。`.drawio` と `.png` を両コミット。
- 本体 .tex の句点は「．」（origin 19edb91 で統一済み）。.agent/・.md 類は「。」のまま。
- 本体ページ数は 53〜54頁が許容範囲。`.gitignore` に
  `!report/計画書_中間発表/23_計画書・設計書.pdf` の例外あり（本体 PDF はコミット対象）。
- CTRL state は `0=Idle/1=Calibrating/2=Conducting/3=Fallback/4=ModeSelect`。
  ADR-0004 は楽器5台（金管4＋ドラム・全体6台）に改訂済み。
