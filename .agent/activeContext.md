# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **test_v3 ゲームモード Phase 2 firmware（共通＋node_01＋node_02）を実装完了**（2026-06-01、
  `shiozawa-test_v3-game`、案A確定で着手）。設計は `.agent/test_v3-game-design.md`、`.agent/api.md` も同期済み。
  - **2-1 共通** (`common/lib/OrcProtocol/OrcProtocol.h`, `fb86bd8`): CtrlPayload 旧 reserved[4]→
    mode/navCursor/targetBpm/score にフィールド化、PKT_UI(type=4)・UiPayload・UiPacket 新設（20B static_assert 維持）。
  - **2-2 node_01 + node_01_devkitc** (`ef5d818`): ConductorState に Menu/Result、GameData 新設。applyPattern に
    IMU ナビ（dynAcc 左右=カーソル/縦=決定・Armed ゲート+不応期）、Calibrating→Menu、ゲーム経過拍カウント・
    ガイド強度フェード・拍間隔誤差の重み付き採点(0-100)・規定拍で Result。拍検出は既存 state==Conducting ガードで排他。
    OrcSenderModule が予約バイト送出。ProjectConfig に NAV_*/GAME_* 定数。devkitc は同一3ファイルをコピー同期。
  - **2-3 node_02** (`b98cd55`): OrcReceiver が予約バイトを data.ctrl へ展開、新規 UiRelayModule が UI フレームを
    USB シリアルへ低頻度中継（変化時＋最大5Hz＋1s heartbeat）。CtrlData 拡張・UI_RELAY_CONFIG・main の gOutputs 登録。
  - **ビルド**: 全5ノード `pio run` SUCCESS（node_01 RAM13.8%/Flash21.0%、devkitc RAM14.0%/Flash21.7%、
    node_02 RAM20.7%/Flash21.1%、node_03/04 RAM20.6%/Flash20.9%＝中継なしで従来同サイズ）。pio は
    `~/.platformio/penv/bin/pio`。`cp` はエイリアスで対話化するので `/bin/cp -f` を使う。
  - **残**: Phase 2-4＝Processing(pc_app/test_v3) の役割自動判定・type1/4 解釈・4画面＋アナライザ・メトロノームフェード
    （master 指示待ち）。実機 upload と評価はユーザー（鉄則: Claude はコンパイルまで）。
  - **（以下は前フェーズ＝test_v2 latency。完了済み・参照用に残置）**
- **test_v2 低遅延化・パケロス削減・堅牢化を実装**（`shiozawa-test_v2-latency`
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

- **test_v3 Phase 2-4（Processing）**: firmware 3 つ完了・master 報告後、指示が来たら着手。
  `pc_app/test_v3/orchestra_resynth/orchestra_resynth.pde` に①役割自動判定（UIフレーム/partId で node_02=
  メイン操作UI / node_03,04=アナライザ・梅澤の手動選択は廃止）、②type=1/4 フレーム解釈（handlePacket は現状
  type!=NOTE を return＝そこに CTRL/UI 分岐を追記）、③メニュー/自由演奏/ゲーム演奏/結果/アナライザの画面群
  （画面は (state,mode) からデータ駆動で毎フレーム再判定）、④メトロノームクリックのローカルフェード。
  梅澤UI参考: `git show origin/umezawa_work:work/umezawa/hck/processing/{processing.pde,P07_ScreenView.pde}`。
  着手前に `.agent/test_v3-game-design.md` §5 と `.agent/api.md` の UI(type=4) 表を Read。
- **実機検証（ユーザー作業）**: node_01/01_devkitc は applyPattern にゲーム分岐が入ったので要 upload。
  IMU ナビの軸(X=左右/Y=上下)・符号・しきい値(1.0g) は実機で要調整（design §9）。ゲーム長 24拍/目標100BPM は設定値。
- （以下 test_v2 latency 用・完了済み）ユーザー作業: `shiozawa-test_v2-latency` を各マイコンへ upload して実機評価。
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
- 結合レポート最終チェック・夜間レビュー累積指摘の docs/コメント追従（〜e170ba7／PR #18・
  2026-05-28 分は `docs/nightly-2026-05-28-followup`）はいずれも完了。次の指示待ち。
- 残保留はファーム実機検証が要る案件（production の board 名・共通ライブラリ集約・CI 取り込み・
  node_02/03 の SERIAL_DEBUG を本番前に 0 へ戻す）。いずれもユーザーの実機判断待ちで Claude 起点では触らない。
- 中間発表（2026-05-20 は計画発表，発表会は2026-07-01）に向けた追加作業があれば着手。

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
