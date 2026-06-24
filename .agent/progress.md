# 完了タスクの時系列

> 毎ターン**追記**する（上書きしない）。50 件超で `progress-archive.md` への移送を提案。
> 形式: `- YYYY-MM-DD: 一行サマリ（関連コミット）`

## 2026-06 — test_v3 ゲームモードフェーズ

- 2026-06-24: **VS Code の Git 同期分岐を復旧**。ローカル `main`（398 ahead）と `origin/main`（371 behind）が共通祖先を持たない別履歴であることを確認し、旧ローカル履歴を `codex/backup-main-before-sync-20260624-0100` へ退避したうえで、`main` を共有リポジトリの現行 `origin/main`（`1dcdb4b`）に合わせた。未コミット変更なし・ahead/behind なし。

- 2026-06-17: **test_v3 Processing 音色データを最新金管 JSON に差し替え**。
  `/Users/shota/Documents/3S/` の `trumpets`/`horns`/`trombones`/`tuba` を
  `pc_app/test_v3/orchestra_resynth/data/0_〜3_*.instrument.json` へ番号付き命名で取り込み。
  元ファイルと byte 単位一致、`python3 -m json.tool` で 4 ファイル構文 OK。ファーム変更なし。

- 2026-06-10: **4 台輪唱の実機問題を机上検証＝ファームにバグなし**（`390e4ac`、`tools/canon_sim/` 新設）。
  サイクル窓ロジックを Python 再現し拍 1〜120 で 20 アサーション全 PASS。原因は実機側の可能性大
  （楽器ファーム古い/取り違え・3 台構成では拍 49〜56 無音が仕様）。全 6 ノード pio run SUCCESS。

- 2026-06-10: **test_v3 修正 5 タスク**（main 直 4 コミット）。ジャイロ 2D 表示削除（`4b480a6`）、
  メニューナビを重力推定 LPF＋窓積算の縦/横判定に改善（`9f9490c`）、状態遷移デッドタイム 1000ms 追加
  （`b656884`）、新音色 4 種で 4 台輪唱＝node_05 新設＋CANON_CYCLE_BEATS=56 のサイクル窓終端処理
  （`80ec121`）。全 6 ノード pio run SUCCESS 警告 0・processing-java build 成功。実機検証はユーザー。

- 2026-06-10: **test_v3 品質向上（机上レビュー＋7 コミット、`shiozawa-test_v3-polish` ブランチ・PR 提出）**。
  node_01 状態遷移修正（Menu/Result の IMU 監視・Fallback 復帰先・テンポ EMA リセット・beatNo=0 で毎回曲頭から）、
  楽器クロック同期スナップ復帰（指揮者リセット 1 パケット追従）＋ OrcReceiver/SystemData/applyPattern の 3 ノード統一、
  Processing ジャイロ軌跡の重複 push 修正＋全画面に接続ステータス/操作ガイド、指揮者 -std=gnu++17（警告 8 件解消）、
  README 2 本書き直し・api.md 現行同期。全 5 ノード pio run SUCCESS 警告 0・processing-java build 通過。実機検証待ち。

- 2026-06-08: **test_v3 マスターリセット復帰高速化・2D IMUグラフ・8分音符修正**。UI_TIMEOUT_MS 5000→2000、
  onScreenChange に Waiting 遷移時ゲーム状態リセット追加。OrcSenderModule で Conducting 時に navCursor/score を
  IMU 加速度 int8 で上書き、Processing に 2D XY プロット（80 フレームリングバッファ）。score_data.cpp の 8 分音符
  durationQ8/subDurationQ8 を 120→128 に修正（0.03 拍のギャップ解消）。全 5 ノード pio run SUCCESS。

- 2026-06-07: **test_v3 楽譜修正・メニュー横配置・指揮棒軌跡**（`20a0451`）。score_data.cpp フレーズ3/6 の
  上昇パターンを全 C4 に修正、Processing メニュー画面を横並びに変更、drawBatonTrail() で BPM 振り子アニメ追加。

- 2026-06-01: **test_v3 ゲームモード Phase 2 firmware（共通＋node_01＋node_02）を実装**（案A確定、
  `shiozawa-test_v3-game`）。2-1 共通 `fb86bd8`: CtrlPayload 旧 reserved[4]→mode/navCursor/targetBpm/score
  フィールド化＋PKT_UI(type=4)/UiPayload/UiPacket 新設（20B static_assert 維持・api.md 同期）。2-2 node_01
  +devkitc `ef5d818`: ConductorState に Menu/Result、GameData 新設、applyPattern に IMU ナビ（dynAcc 左右=
  カーソル/縦=決定・Armed ゲート+不応期）・Calibrating→Menu・ゲーム経過拍カウント/ガイド強度フェード/拍間隔誤差の
  重み付き採点(0-100)/規定拍で Result、OrcSender が予約バイト送出、ProjectConfig に NAV_*/GAME_* 定数（拍検出は
  既存 state==Conducting ガードで排他。devkitc は3ファイル `/bin/cp -f` 同期）。2-3 node_02 `b98cd55`:
  OrcReceiver が予約バイトを data.ctrl へ展開、新規 UiRelayModule が UI フレームを USB シリアルへ低頻度中継
  （変化時＋最大5Hz＋1s heartbeat・NOTE 20B 不変・同 Serial に別フレーム混在で PC は magic 再同期・SERIAL_DEBUG=1 では
  非送出）、CtrlData 拡張・UI_RELAY_CONFIG・main gOutputs 登録。全5ノード pio run SUCCESS（node_01 RAM13.8%/
  Flash21.0%、devkitc 14.0%/21.7%、node_02 20.7%/21.1%、node_03/04 20.6%/20.9%）。残=Phase 2-4 Processing
  （役割自動判定・type1/4 解釈・4画面＋アナライザ・メトロノームフェード）は master 指示待ち。実機 upload/評価＋
  IMU ナビ軸調整はユーザー。

- 2026-06-01: **test_v3 ゲームモード 設計メモを作成**（`shiozawa-test_v3-game`、`.agent/test_v3-game-design.md`、
  Phase 1 残り＝設計）。(a) CTRL 予約4B を mode/navCursor/targetBpm/score にフィールド化（画面は state を
  Menu=4/Result=5 へ拡張して PC が (state,mode) から導出）、(b) node_01 IMU ナビ（dynAcc の左右(X)/上下(Y)
  成分の符号・閾値で単純判定、左右=カーソル移動/縦=決定。新 Menu/Result state で拍検出と排他＝既存の
  state==Conducting ガードを流用）、(c) node_02 に新 type=4 PKT_UI を追加し CTRL 内容を USB シリアルで PC へ
  中継（変化時＋最大5Hz の低頻度・UiRelayModule 新規・NOTE 20B 不変）、(d) Processing は役割の手動選択を廃止し
  partId/UIフレーム presence で自動判定（node_02=メイン操作UI / node_03,04=アナライザ）、画面はデータ駆動で毎フレーム
  再判定。**計画書 Phase 4A からの逸脱**: 予約4B に targetBpmQ8(2B) だとカーソルの空きが無いため
  targetBpmQ8→targetBpm(1B 生BPM) に簡素化（master 確認事項に明記）。同期経路(BEAT/NOTE/CTRL 20B)・拍検出・
  楽譜進行は不変＝自由演奏は test_v2 同一挙動を維持。実装は Phase 2 以降で master 指示後。

## 2026-06 — test_v2 低遅延化フェーズ

- 2026-06-01: **test_v2 低遅延化・パケロス削減・堅牢化を実装**（`shiozawa-test_v2-latency`
  ブランチ、計画書 `.agent/test_v2-latency-plan.md` 6節 A/B/C）。A=指揮者 config 2ファイル
  (`node_01`/`node_01_devkitc` の ProjectConfig.h) で `beatLookaheadMs` 50→30・`beatGapMs`
  0→2。B=共通 OrcNetModule に `wasLinkUp_` を足し、Sta 側 WiFi down→up 復帰時に
  `udp_.stop()→beginMulticast()` でマルチキャスト購読を貼り直す（init 末尾で wasLinkUp_
  初期化＝起動直後の偽遷移で無駄な再joinを防ぐ。SoftAp 側は isLinkUp が常時 true で無影響）。
  C=Processing の getLineOut バッファ 1024→512・setup 冒頭に frameRate(90) 明示。4ノード
  とも `pio run` SUCCESS（node_01_devkitc RAM14.0%/Flash21.6%、node_02-04 RAM20.6%/
  Flash20.9%＝jitter 時と同サイズ）。実機 upload と評価はユーザー（鉄則: main 不触・push せず・
  コンパイルまで）。残課題: B の WiFiS3 再join 実機確認、5台構成(node_05/06)は編曲＝音楽判断で
  master 確認待ち保留。計画書7節（楽器 Receiver/applyPattern/NoteSender/OrcProtocol/
  score_data）は不変。

## 2026-05 — ドキュメント刷新フェーズ

- 2026-05-28: 夜間レビュー 2026-05-28（PR #19）の **docs 用語追従**。ADR-0004 改訂（楽器5台・partId
  0x02-0x06）と beatRedundancy=4（暫定）に合わせ「4声→5声(ADR-0004)」・BEAT「2連送」→beatRedundancy
  参照の汎用表現（N連送・暫定4）・pc-audio「3〜4声」→「3〜5声」へ修正、連送確率計算に時間相関注釈を追記。
  docs build 70ページ・リンク切れ無し。ファーム本体ロジックは不変（`docs/nightly-2026-05-28-followup`）。
- 2026-05-28: PR #18（e170ba7）で 5/23-27 の累積指摘を一括追従（docs とコメントのみ、ファーム本体
  ロジックは不変）。
- 2026-05-27: **test_v2 Processing 側に「全パート同じ音色」モードを追加** (ユーザー指示「一旦発音を
  全部ピアノにしてわかりやすくして」、`shiozawa-test_v2-jitter` ブランチ)。輪唱の聞き分け補助。
  `pc_app/test_v2/orchestra_resynth/data/piano.json` を新規追加 (手書き音色: attack 8 ms・1.5 s
  指数減衰 τ=0.85 s・倍音 8 本・非調和性 B=0.0004・アタックノイズ 0.04、analyzer 由来ではないので
  厳密なピアノ音ではないが打鍵→減衰の輪郭は出る)。`orchestra_resynth.pde` に
  `forceSingleInstrument`(既定 true) と `FORCED_INSTRUMENT_FILE="piano.json"` を導入し、
  `rescanInstruments()` で piano.json の index を `forcedInstrumentIdx` にキャッシュ、`modelForId(id)`
  が ON 時は instrumentId を無視してその index を返すよう改修。'p' キーで ON/OFF トグル、画面の
  楽器定義パネルにモード表示。ファーム側は無変更 (NOTE には引き続き instrumentId が乗る)。
  既存音色 (0_organ/1_flute/2_bell/3_flute_tweaked) は退避せず data/ にそのまま残し、'p' OFF で
  従来挙動に戻る。`python3 -m json.tool` で JSON 構文 OK 確認。

- 2026-05-27: **ジッタ削減版を楽器 node_02/03 に実機書き込み** (ユーザー指示「各マイコンに書き込んで」)。
  `shiozawa-test_v2-jitter` ブランチのファームを 2 台に upload: node_02 (SER=34B7DA64482C →
  `/dev/cu.usbmodem34B7DA64482C2`、bossac 3.41 秒・total 6.38 秒)、node_03 (SER=F412FAA08558 →
  `/dev/cu.usbmodemF412FAA085582`、bossac 3.55 秒・total 5.67 秒)。両方 `[SUCCESS]`。node_04 は
  未接続のため書き込み不可で 2 声輪唱で評価開始。指揮者 `node_01_devkitc` は今回のブランチで
  コード変更なし (改修対象は楽器側の OrcReceiverModule と ProjectConfig のみ) なので書き込まず。
  Processing は起動していないことを `pgrep` で確認してから書き込み (前回の Resource busy 事故対策)。

- 2026-05-27: **test_v2 楽器側のジッタ削減と多重受信処理を改善** (ユーザー指示、挑戦的変更のため
  `shiozawa-test_v2-jitter` ブランチを新規作成)。node_02/03/04 の OrcReceiverModule と
  ProjectConfig を改修。①`loopIntervalMs` 5 → 2 ms (発火判定ジッタ最大 5 ms → 2 ms)、
  ②`clockSyncEmaAlpha` 0.10 → 0.20 (初回サンプル吸込み倍速化、時定数 ≈0.25 s)、
  ③`OrcReceiverConfig` に `clockSyncEmaAlphaDup` フィールド新設 (= 0.05) して、同一 beatNo の
  連送 2 個目以降は別 α で EMA 更新するよう OrcReceiverModule.cpp の duplicate 判定箇所を
  書き換え。旧実装は連送 4 個を全て α=0.10 で吸って同じサンプルに 4 回追従していた問題
  (= 強相関サンプルの過剰反映) を、初回 0.20 + 重複 0.05×3 で合計影響 ≈0.32 (初回 α 単独に
  近い吸い方) に補正。pending (発音予約) は初到着 1 個固定を維持 (連送 payload は同一・
  発火後後着の再キューによる二重発音事故を避けるため)。3 ノードとも `pio run` SUCCESS
  (Flash 20.9% / RAM 20.6% 不変)。実機書き込みは AGENTS.md の「実機未テスト .ino/.cpp に
  Claude 起点で追加変更を入れない」ルール準拠でユーザー作業に委ねる。

- 2026-05-27: **かえるのうた版を node_02/03 に実機書き込み** (ユーザー指示)。
  接続中の Arduino UNO R4 WiFi 2 台を `pio device list` でシリアル番号判定:
  node_02 (SER=34B7DA64482C, `/dev/cu.usbmodem34B7DA64482C2`, bossac 3.43 秒,
  total 6.12 秒) と node_03 (SER=F412FAA08558, `/dev/cu.usbmodemF412FAA085582`,
  bossac 3.49 秒, total 5.41 秒)。両方 `[SUCCESS]` / Hash verified。初回試行
  時に Processing (orchestra_resynth, PID 54869) が両ポートを `lsof` で掴んで
  おり `[Errno 16] Resource busy` で失敗、ユーザーに Processing 終了を依頼
  して再試行で成功。node_04 (声部 3) は未接続のため未書き込み。指揮者
  `node_01_devkitc` は楽譜を持たないので書き込み不要。これで test_v2 が
  「かえるのうた」2 声輪唱 (位相 0/8) で動作可能な状態。

- 2026-05-27: **test_v2 の楽曲を「きらきら星」→「かえるのうた」へ差し替え**
  (`firmware/test_v2/node_02/03/04/src/score_data.cpp`、コミット 655d72e)。
  きらきら星は同型反復で輪唱の聞き分けが難しいというユーザー判断。1 周 24 拍
  (ドレミファミレドー / ミファソラソファミー / ドドドドドドドー) を 2 周ぶん
  直書きして kScoreLength=48 を維持。`headRestBeats=0/8/16` (ProjectConfig.h)
  はそのまま → 楽譜内位相 (0,8,16) で 3 声輪唱成立。16 拍版にすると node_04 が
  node_02 と完全同位相になるため 24 拍周期を採用。3 ノードとも `pio run` で
  SUCCESS (Flash 20.9% / RAM 20.6%)。実機書き込みは未実施 (CLAUDE.md「実機未
  テスト .ino/.cpp に Claude 起点で追加変更を入れない」ルール準拠でユーザー
  作業に委ねる)。`.agent/activeContext.md` の課題曲メモ「かえるのうたでチーム
  判断確定」が今回の差し替えで実装側にも反映された形。

- 2026-05-27: **orchestra_resynth のポート一覧に USB フィルタ+スクロール追加**
  (`pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde`)。ユーザーの Mac
  でポート一覧が画面下に並びきらず、書き込み直後に再認識された
  `usbmodemF412FAA08558` (node_03) が一覧外でクリックできない件への対応。
  追加要素: ①`isUsbSerialName()` で `usbmodem*`/`usbserial*`/`ttyUSB*`/
  `ttyACM*`/`COM*` をマッチさせる USB シリアル判定、②`usbOnly` トグル
  (`f` キー、既定 true、開いてるポートはフィルタ対象でも残して close 操作を
  奪わない)、③`displayPorts` (フィルタ済リスト) と `portScrollY`、毎フレーム
  `rebuildDisplayPorts()` で開閉に追従、④`drawPortList()` を `clip()` で
  クリッピングし、`mouseWheel(MouseEvent)` で 1 ノッチ=1 行スクロール、
  右端 4px のサムバー描画、⑤ヘッダ/上部ヘルプ/起動時 println に `[f]` と
  `[wheel]` を追記。クリック判定 (`mousePressed`) もスクロール量を反映。
  ポート数が多いマシンや書き込みリセット直後でもリストから node_03 を
  確実にクリックできる状態に。

- 2026-05-27: **楽器 node_02/03 を SERIAL_DEBUG=0 に戻して再書き込み**。
  test_v2 起動時に Processing 受信 0 だった原因が `ac8c5ff デバック` で入った
  `-DSERIAL_DEBUG=1` (NOTE バイナリ抑止モード) だったため、`platformio.ini` の
  該当行 1 箇所だけ `=0` に戻して node_02 (16.41 秒) / node_03 (12.67 秒) を
  再書き込み。node_04 は元から `=0` のままだったので変更なし。指揮者
  `node_01_devkitc` は `SERIAL_DEBUG=1` のまま (拍検出デバッグ用)。AGENTS.md
  既定 (楽器=0 / 指揮者=1) と整合する状態に復元。

- 2026-05-27: **test_v2 の 3 台を実機書き込み**（DevKitC + Arduino UNO R4 WiFi
  ×2、ユーザー指示）。`pio device list` で接続デバイスを判定し、CH343 ブリッジ
  (`/dev/cu.usbmodem5B7A1660211`) ← `node_01_devkitc` (12.80 秒)、UNO R4 シリアル
  34B7DA64482C ← `node_02` (5.50 秒)、F412FAA08558 ← `node_03` (5.55 秒) で順次
  `pio run -t upload --upload-port`。3 台とも `[SUCCESS]`。Arduino 2 台の割当は
  AskUserQuestion で確認 (VID/PID 同一で自動判別不可)。node_04 (声部 3) は未接続。
  注意: 楽器側 `platformio.ini` の `-DSERIAL_DEBUG=1` (ac8c5ff 以降) は NOTE
  バイナリ送出を抑止するため、Processing で音を鳴らすには `=0` への切り替えが
  別途必要。

- 2026-05-27: **DevKitC 派生ファームを test_v2 にも展開**
  （`firmware/test_v2/node_01_devkitc/`）。test_v1/node_01_devkitc を実機検証
  したユーザーから「DevKitC でうまく行った」報告を受け、test_v2 (3 声輪唱) でも
  同じ派生を用意。`firmware/test_v2/node_01` をディレクトリごとコピーして
  `.pio/`・`.vscode/` を除外、差分はビルド設定とコメントのみ (board=
  esp32-s3-devkitc-1 / USB CDC マクロ無効化 / upload_protocol コメントアウトで
  PIO デフォルト UART 側 esptool / ProjectConfig.h の冒頭・I2C ピン・StatusLed
  コメント更新と activeLow=false / README.md を DevKitC 用に書き直し)。`src/`
  `lib/` `include/SystemData.h` はバイト単位で同一。`pio run` で RAM 14.0%・
  Flash 21.6%・警告 0・11.54 秒でビルド通過。XIAO 版との比較検証はユーザー側。

- 2026-05-27: **パケロス原因切り分け用 DevKitC 派生ファームを追加**
  （`firmware/test_v1/node_01_devkitc/`）。test_v1 で 5/11 以降の UDP パケロス多発の
  原因がコード退行ではない（5/11 以降の test_v1/ への変更は SERIAL_DEBUG 無効化の 1
  件のみ）と確認し、最有力候補の「XIAO ESP32-S3 Sense 外付け IPEX アンテナ接触不良」
  を切り分けるために PCB 内蔵アンテナの ESP32-S3-DevKitC-1 用派生を作成。`node_01` を
  ディレクトリごとコピーしてビルド設定だけ差し替え（board=esp32-s3-devkitc-1 / USB CDC
  OFF / upload_protocol デフォルト UART 側）、ロジック (`src/` `lib/`) は完全同一。I2C
  ピンは GPIO5/GPIO6 のまま (DevKitC 左列 5・6 番目に並ぶのでブレッドボード配線でも
  そのまま使える)。`pio run` で RAM 14%・Flash 22%・警告 0 でビルド通過。実機書き込み
  と XIAO 版との比較検証はユーザー側 (CLAUDE.md「実機未テスト .ino に Claude 起点で
  追加変更を入れない」ルール準拠)。
  （`work/shiozawa/work-0525/作業ログ0525/作業ログ0525.tex` + `.pdf`）。
  本体計画書 19edb91 と同方針で「、」→「，」「。」→「．」を全置換。
  Docker latexmk で 6 ページ・Overfull 0 ビルド成功。

- 2026-05-26: **塩澤の作業ログ第1回の事実関係訂正と付録改訂**
  （`work/shiozawa/work-0525/作業ログ0525/作業ログ0525.tex` + `.pdf`）。
  前ターン 31aedae のパケロス重点リライトに対するユーザー指摘を反映:
  ①「test_v2 で 3 声輪唱を実装／鳴らした」記述は嘘になるため全削除、
  ②4 ノード同期試験（test_v1）もパケロスによる停滞で進捗 70\% に訂正
  （マイルストーン「test_v1 達成」を「未達」へ）、
  ③§4.2 検証方法の「参照資料」リスト削除、
  ④付録: 回路図・配線資料項目を削除、GitHub リポジトリ URL を `\url{}` で追加
  （preamble に `\usepackage{url}` 追加）、プライベートリポジトリで TA・教員が
  閲覧不可な点を「閲覧の要検討事項」として記載（パブリック化／Collaborator 招待の
  2 案）。Docker latexmk で 6 ページ・Overfull 0 ビルド成功。

- 2026-05-26: **塩澤の個人作業ログ第1回をパケロス重点へ全面リライト**
  （`work/shiozawa/work-0525/作業ログ0525/作業ログ0525.tex` + `.pdf`）。
  スコープを「test_v1 完了まで」→「test_v1 完了 + test_v2 のパケロス調査」に拡張し、
  重大課題を WiFi 到達ばらつき（解決済）から UDP マルチキャストのパケロス
  （未解決・対応中）へ全面置換。作業ログ表に test_v2 輪唱検証行とパケロス計測・対策行を
  追加、課題管理表でパケロスを最上段化、AI 利用・検証方法・ファクトチェック・次回計画も
  シーケンス番号付与＋同一パケット連送と NOTE のユニキャスト分離検討の話に書き直し。
  付録の `\texttt` 長尺パス並列で Overfull 2 件が出たため test_v1/test_v2 を別 item に
  分割して解消。Docker latexmk で 6 ページ・Overfull 0・Underfull は表組み内の和文行末の
  微小なもののみ。

- 2026-05-26: **塩澤の個人作業ログ第1回（test_v1 まで）を作成**
  （`work/shiozawa/work-0525/作業ログ0525/作業ログ0525.tex` + `.pdf`）。教員配布テンプレ
  `report/作業ログテンプレート/` を流用し、GW から続けた IMU モーション取得・WiFi UDP 通信・
  回路結線・4ノード同期試験を「作業ログ表」に整理。重大課題は WiFi 到達ばらつきとし
  マスタクロック方式＋EMA で吸収済みを明記。AI 利用は ADR-0002／-0003／-0006 と河瀬2014 を
  ファクトチェック源とした旨を記述。Docker latexmk でビルド成功（5ページ・Overfull 0・
  Underfull は和文行末の微小なもののみ）。次回計画は test_v2 輪唱検証。
- 2026-05-25: ac8c5ff で node_02/03 を `SERIAL_DEBUG=1` に切り分け中。本番演奏前に 0 へ戻す前提（.ini は今回不変）。

- 2026-05-25: **作業ログ LaTeX テンプレートを追加**（`report/作業ログテンプレート/`）。教員配布
  「作業ログ.pdf」と同じ章構成（1〜7章＋見出し・3階層箇条書き・素朴な表・章末水平線）を
  jsarticle+uplatex+dvipdfmx で再現。Docker `paperist/texlive-ja:debian` で `latexmk` ビルド可。
  配布原本は `作業ログ_配布.pdf` として併置、`.gitignore` に両 PDF の例外を追加（`2ccc584`）。
  落とし穴: `\item [xxx]` は `\item` のオプション引数として解釈され中身が外に飛ぶため
  `\item {}[xxx]` で回避。

- 2026-05-22: **最終チェック残2件（高③・中⑨）を対応し指摘15件すべて決着**。齋藤への確認で方針確定。
  高③＝「平均5.52cent」の出所が不確かなため ref:onkai 論文要旨の精度「3.6cent未満」へ修正・中⑨＝MOE
  「音階の誤差」の測定方法を「合成出力音を録音・周波数分析し楽譜の平均律理論音高と比較」と明記
  （元音源比較は調律差・演奏揺れが混入するため不採用）。ビルド53ページ・Overfull/Underfull 0・未定義参照0。

- 2026-05-22: **最終チェック15件のうち残10件を処理し13/15件対応完了**。中④CTRL state を現行
  ファーム整合で再採番（0=Idle/1=Calibrating/2=Conducting/3=Fallback/4=ModeSelect）・中⑦課題曲
  「かえるのうた」はチーム判断で確定として本文修正不要で決着・中⑧ADR-0004を楽器5台（金管4＋ドラム・
  全体6台）へ改訂し改訂履歴明記・低⑪節名「状態遷移図」は現状維持で決着・低⑫楽譜idx式を実コード準拠
  beatNo-1-headRestBeats へ・低⑬同期通信／USB Serial／全ノードの表記ゆれ統一（fbs・system-overview・
  class-diagram の3図を再書き出し）・低⑭アロー図は 410・520 を足さず散文で省略注記・低⑮CTRL予約4Bに
  注記。ビルド53ページ（§7「53〜54頁は許容範囲」内）・Overfull/Underfull 0・未定義参照0，docs 70ページ。
  残2件は齋藤への事実確認待ち＝高③（ref:onkai「5.52cent」出所）と連動する中⑨（MOE音階指標）。

- 2026-05-21: **最終チェック指摘のうち即修正可5件を修正**。高①ref:douki を Barbosa→河瀬2014
  に差し替え（ADR-0006・MOPメモが示す同期20msの本来の出典。J-STAGEオープンアクセスで実在確認）、
  高②NOTEパケット表にinstrumentId行を追加、中⑤強弱を必達ゴール→発展目標、中⑥対象範囲
  「振り速度→音量」を「振りの大きさ→強弱」に統一、低⑩F1「ピーク検出」→「振り下ろしの検出」。
  ビルド49ページ・Overfull/Underfull 0維持（b678370・53fbf7c）。残10件は事実確認/方針判断/図修正。

- 2026-05-21: **結合レポート提出前の最終チェック実施**。本体49ページ＋全10図＋ファーム実コード
  ＋議事録＋参考文献6件を突き合わせ**15件の指摘**（高3・中6・低6）を抽出（高3＝ref:douki引用が
  出典と逆／NOTE表のinstrumentId欠落で本文と矛盾／ref:onkai 5.52cent出所不明）。LaTeX体裁
  （Overfull/Underfull 0・未定義参照0）とコード整合は良好。指摘15件の全文と進め方は
  `_作業計画.md` §6-6（Phase 6）に起票。未修正でユーザーの修正方針待ち。

- 2026-05-21: **ガントチャート整合修正完了**。現行ガント図 `fig/gantt.drawio` のバーが同じ
  計画書内のアロー図 `arrow.drawio`・WBS・授業スケジュールと数値不一致（バー長がアロー図週数と
  全タスクで乖離，クリティカルパスの逐次依存崩れ＝210/220同位置同時開始，設計フェーズ4週化で
  WBS「設計3週」と矛盾，CP実測約11週で「約8週」と不一致）だった件を修正。13バーをアロー図週数
  ＋WBS工数（設計3/製造2/テスト2週）＋授業日程（計画発表5/20・製造5/27〜・評価会6/24・発表7/1）
  に合わせ引き直し，CPを階段配置・now line を 5/20 へ。本体 .tex ガント散文の月表現も追従。
  本物画像 `ganto.png` は楽器4台・実装5/13開始の旧計画のため日程ソース不採用。ビルド成功・
  49ページ（不変）・Overfull/Underfull 0・未定義参照0。

- 2026-05-21: **結合レポート Phase 5 完了（状態遷移図のシーケンス図化・整合性修正）**。
  §状態遷移図の状態機械図2枚（`state-conductor`／`state-performer`）を廃し，システム動作
  シーケンス図（`fig:sequence`，指揮者・楽器×5・PC の4ライフライン，起動→モード選択→
  キャリブレーション→演奏ループ→ゲーム採点→曲終了）を draw.io で新規作成。状態定義表3つは
  存置。整合性 中3件も修正（Ch1「音量」→「強弱（velocity）」／WBS 240 を主旋律譜＋ドラム譜
  基準へ具体化／クラス図キャプションに所属ノード併記を明記）。ビルド成功・**49ページ**・
  Overfull/Underfull 0・未定義参照0。廃止図 `state-conductor`／`state-performer` の
  `.drawio`／`.png` は削除。

- 2026-05-21: **本物画像12点（コミット `1c82ffc`）の到着を受け差分を徹底調査し，Phase 5 を起票**。
  FBS/PBS が技術版（現行 draw.io の下敷き）／素朴版（元結合版 .tex が採用）の2系統で食い違い，
  本物画像は全点「楽器4台・ゲームなし」，参考文献は両版で中身完全同一（現行版が整形済みで良好）
  と判明。届いた10点中 .tex 参照は5点（FBS/PBS/WBS/arrow/ganto）のみで他5点は未使用素材。
  ユーザーが4論点決定＝台数ゲーム・FBS/PBS・参考文献は現行維持，状態遷移図のみシーケンス図化。
  `_作業計画.md` に Phase 5（残作業 A: 状態遷移図のシーケンス図化／B: 整合性中程度3件）を追記。

- 2026-05-21: **結合レポート全面リライト Phase 4D（生成 AI 章・全図 draw.io 化・全体整合）完了 ＝
  全面リライト完了**。Ch4「生成 AI の利用」を執筆（対話を通じた共同執筆／設計判断は著者が正／
  EMA・Arduino 制約に照らしたレビュー／誤りの責任は著者，の 3 段落・約 0.5 頁）。残る TikZ 2 図を
  draw.io 化: `class-diagram`（IModule 抽象基底へ 6 具象モジュールが開三角矢印で継承），`flow`
  （楽器処理フロー・縦フロー・判定 3 分岐・側枝 3・戻り矢印「次の拍へ」）。本体の TikZ 2 ブロックを
  `\includegraphics` へ置換し，preamble から `\usepackage{tikz}`／`\usetikzlibrary` を除去
  （**TikZ 全廃完了**・全 9 図が draw.io）。§9 整合チェックリスト全消化: ①同期誤差 20ms＝Ch1 結合
  MOP を「数十 ms は気づかれにくい→ADR-0006 安全側 20ms」へ書き換え Ch3 設計目標値表と統一，
  ②`ref:beat`＝Ch3 §3.4.4 楽譜進行の自己修復記述に `\cite` 付与（参考文献 6 件すべて被引用），
  ③NOTE `gate`＝パケット表で「常に 1。0 は将来拡張用予約・現設計は送らない」と注記，④CPU 時間＝
  「3 フェーズ合計 5ms 以内・入力はその一部 2ms」と制御周期基準で書き直し，⑤magic エンディアン＝
  「固定バイト列 0x4F 0x52・エンディアン対象外」を散文とヘッダ表へ明記，⑥相互参照＝未定義 0，
  ⑦用語＝node 名/モジュール名/CTRL・BEAT・NOTE 一貫，⑧数値＝5ms/20Hz/200Hz/BPM 40–240/同期
  20ms 章間一致。ゲーム整合 3 項＝モード名・CTRL 予約 4B（Ch2 通信メッセージ表にも明記し Ch3
  パケット表と一致）・ModeSelect 等の状態名を点検済み。ビルド `latexmk -lualatex` 成功・**47 ページ**
  （60 未満・50 以内）・Overfull/Underfull 0・参照/引用の未定義なし（`undefined` 3 件は Hiragino
  W6 bold series 警告のみ・実害なし）。**Phase 0〜4D 全フェーズ完了し，結合レポート全面リライトの
  全工程が完結**（`report/計画書_中間発表/` に 47 ページの計画書・設計書を再構築）。
- 2026-05-21: **結合レポート全面リライト Phase 4C（Ch1 へのゲーム反映・図の作り直し）完了**。
  Ch1 にゲームモードを反映: §目的に 2 モード構成（自由演奏／ゲーム＝メトロノームガイドのフェード＋
  テンポ維持の採点）の段落を追加，§成果物の Processing 項にゲーム UI を明記，§対象範囲に「2 モード
  構成と選択機能」「目標テンポの提示とテンポ維持精度の採点」の 2 項を追加，§FBS 説明を「4→5 機能群」
  へ改めゲーム進行を加筆，§PBS 説明に「ゲーム進行モジュール」「ゲーム画面 UI」を加筆，FBS↔PBS
  対応表にゲーム進行行を追加，§リスク管理に「ゲーム機能はコア機能の上に重ねる追加層・遅れても
  自由演奏のみで発表成立」の一文を追加。図 4 点を作り直し（`.drawio`＋`.png` 両コミット）: `fbs` に
  第 5 機能群「ゲーム進行」（葉＝モード選択／目標テンポの提示／テンポ維持の採点，幅 1478→1830），
  `pbs` に指揮者側「ゲーム進行モジュール」と PC 側「ゲーム画面 UI」（計画の「ゲーム UI のみ」から
  踏み込み，FBS↔PBS 対応整合のため node\_01 側モジュールも追加，幅 1532→1768），`arrow` に
  「260 ゲーム機能（1.5 週）」並行アーク（E3→E6・240/250 と同様，クリティカルパス約 8 週は不変，
  高 430→470），`gantt` に「260 ゲーム機能」行（12→13 行・製造緑・5/27〜6/17）。WBS 表に製造
  フェーズ「260 ゲーム機能」行（担当 塩澤・梅澤）を追加し，110 に「動作モード」，250 末尾を
  「演奏画面の描画」へ更新（モード待機・スコア・結果は 260 へ移動）。作業計画・ガント・リスクの
  散文も 260 を反映。ビルド `latexmk -lualatex` 成功・**47 ページ**・Overfull/Underfull 0・参照/
  引用の未定義なし。留意: FBS は 5 機能群化で横長になり葉の文字がやや小さいが図は崩れず据え置き。
  次は Phase 4D（生成 AI 章・残 TikZ 2 図の draw.io 化・§9 整合チェックリスト全消化・最終調整）
- 2026-05-21: **結合レポート全面リライト Phase 4B（Processing 記述拡充・ゲーム UI 節新設）完了**。
  Ch3 §3.3.6 を「音色合成（PC 側）」→「PC 側ソフトウェア（Processing）」へ改題・約 0.5 頁→約 2 頁へ
  増量し，`orchestra_resynth.pde` 実体準拠で フレーム同期（magic 走査・type 振り分け・ポート別
  同期状態）／Serial スレッド分離と受信キュー（発音処理を描画スレッドへ集約）／Voice 管理
  （durationMs 自動消音・同時発音上限 24・最古強制リリース）／音色合成（倍音加算＋非調和性＋
  ビブラート/トレモロ＋整形ノイズ）／音色定義の JSON 外部化（instrumentId＝ファイル名昇順 index）
  を `\textbf` 小節化。§3.3.7「画面とゲーム UI の設計」を新設し，モード待機画面（ModeWait）・
  演奏画面（Playing，共通＋ゲーム）・メトロノーム表示・結果画面（Result）を小節化，画面と表示
  要素を表 `tab:pc-screens` に集約。CTRL 中継（楽器ノード→専用 PC へ転送，PC が mode/targetBpmQ8/
  score を読む，新パケット種別不要）を明記。Ch2 PC 状態定義表 `tab:state-pc` をモード対応へ更新
  （Ready→ModeWait に改め Result を追加，PortSelect/ModeWait/Playing/Result/Muted/Error の 6 状態）。
  整合: §3.3.2 クラス図節の PC 記述末尾を `sec:pc-software`/`sec:pc-ui` 参照へ，Ch2 F5 を
  `\ref{sec:pc-ui}節` へ精緻化。新ラベル 3 件（`sec:pc-software`・`sec:pc-ui`・`tab:pc-screens`）。
  図は §8 方針に従い新設せず表で対応。ビルド `latexmk -lualatex` 成功・**47 ページ**・
  Overfull/Underfull 0・未定義参照/引用なし。次は Phase 4C（Ch1 へのゲーム反映・図の作り直し）
- 2026-05-21: **結合レポート全面リライト Phase 4A（ゲーム機能を Ch2・Ch3 へ織り込み）完了**。Ch2 に
  ①章冒頭の 2 モード宣言（自由演奏／ゲーム），②要求 R-5（モード選択）・R-6（テンポ維持の採点），
  ③機能分解 F7「ゲーム進行・採点」（node\_01）と F5 を「音響合成・演奏画面（PC）」へ改名・加筆，
  ④操作 IF の「モード選択」（規定モーション・既定自由演奏・大振り 1 回でゲーム・数秒静止で確定）と
  「メトロノームガイド」，⑤LED 表 node\_01 ModeSelect 行，⑥指揮者状態遷移の ModeSelect 状態，
  ⑦楽器状態はモードで不変の明記，を追加。Ch3 で CTRL 予約 4B を mode（1B・0/1）・targetBpmQ8（2B）・
  score（1B・0–100）へ割当（state は ModeSelect 挿入で 0–4 へ再採番），指揮者処理フローに採点
  ステップ，新節「ゲームモードの採点とメトロノームガイド」を追加（フェード＝固定スケジュールで
  強度 1.0→0・通信不要，採点＝振り間隔と目標拍間隔の誤差をガイド強度で重み付け集計→0–100 写像）。
  状態遷移 2 図（`state-conductor`／`state-performer`）を draw.io 新規作成（`.drawio`＋`.png` 両コミット）
  し本体の TikZ 状態遷移 2 ブロックを `\includegraphics` へ置換（クラス図・処理フロー図の TikZ は
  Phase 4D 据え置き，`tikz` パッケージ存置）。`.agent/api.md` は未修正（現行ファーム＝予約 4B が事実，
  報告書は将来設計を記述する立場で差を許容）。ビルド `latexmk -lualatex` 成功・**45 ページ**・
  Overfull/Underfull 0・未定義参照/引用なし。次は Phase 4B（Processing 記述拡充・ゲーム UI 節新設）
- 2026-05-21: **ゲームモード追加で `_作業計画.md` を Phase 4A〜4D へ再分割**（本体 `.tex` 未編集）。
  自由演奏＋ゲームモード（モード選択／目標テンポ提示／維持精度の採点）を設計へ織り込む方針を §4-2 に
  記録（司令塔 node\_01・メトロノームのフェードアウト・演奏は実振り BPM・CTRL 予約 4 バイトで伝達・
  表示は楽器側 PC）。全図 draw.io 化＝TikZ 廃止も決定。ページ上限を 60 未満へ緩和（50 以内が望ましいが
  超過可，ユーザー指示）。前回レビューの本体不整合 6 件は §9 で Phase 4D 消化。次は Phase 4A。
- 2026-05-21: **結合レポート全面リライト Phase 3（Chapter 3「システムの詳細設計」）完了**。Block A/B の 2 版
  収録を Block B 土台へ統合し，部品一覧／HW 設計／SW 設計／処理フロー／テスト設計の 5 節を執筆。Block B の
  apibox 約 15 個・`verbatim`・`lstlisting` を要点の散文＋小表へ大幅圧縮（`IModule`/`OrcNetConfig` 等の
  全項目列挙を削除しモジュール責務は 1 表に集約）。図 2 点を TikZ 新規（クラス継承図・楽器処理フロー図）、
  HW 接続図は Ch2 と重複のため作らず参照に。楽器 5 台・partId 0x02–0x06・node\_02〜06 で統一、`ScoreEvent`
  は実体準拠 9 フィールド、`bpmQ8` は「8 倍整数」表現。`.agent/api.md` の本番想定 partId も 4 台→5 台
  （0x02–0x06）へ追従（別コミット）。ビルド成功・**45 ページ**（Ch3≈16）・Overfull/Underfull 0・未定義参照
  なし・≤50 内。次は Phase 4（生成 AI 章・§9 整合チェックリスト全消化・最終調整）
- 2026-05-21: **結合レポート全面リライト Phase 2（Chapter 2「システムの基本設計」）完了**。①楽器台数を
  4→5 に変更（ユーザー決定）。最終構成＝指揮者 1（XIAO ESP32-S3）＋楽器 5（金管 4＋ドラム、node\_02〜06、
  partId 0x02–0x06）＋PC 5（各楽器に 1 対 1）。授業制約「Arduino 人数分−1＝5 台」は楽器用 UNO R4 を 5 台で
  満たし指揮者 XIAO は別枠、で整理。Ch1 の台数表記 5 箇所（成果物・WBS・資源欄）と作業計画 §9 整合
  チェックリストも 4→5 へ更新。②システム構成図を draw.io 新規作成（`fig/system-overview.drawio`＋`.png`）。
  指揮者→楽器 5（WiFi UDP・実線）→PC 5（USB Serial・破線）の 3 列。Block A 行 613 / Block B 行 894 の
  TikZ 構成図 2 枚を 1 枚に統合。③Ch2 を全執筆（Block B 土台に Block A 固有事実を畳み込み）: §1 機能一覧
  （要求一覧表＋FBS F1–F6）、§2 システム構成図（全体構成図＋ノード/パート対応表＋役割分担表＋データ
  フロー＋EMA 方針）、§3 操作 IF（ユーザー操作＋LED 表＋通信メッセージ表）、§4 状態遷移図（指揮者・楽器の
  TikZ 図＋指揮者/楽器/PC の状態定義表）。Block A の「2 版収録」を解消、Block A 旧楽器状態遷移
  （SelfRun 含む・Block B 設計と矛盾）は削除。指揮者・楽器の状態遷移は正常レンダリングのため TikZ 据え置き。
  ④`latexmk -lualatex` 成功・**29 ページ**（Ch2≈8 ページ）・Overfull/Underfull 0 件・未定義参照/引用なし。
  AGENTS.md・architecture.md の本番想定台数も 4→5 へ追従（別コミット）。api.md（partId 範囲）と ADR-0004
  は未追従、Phase 3／チーム判断に送り。次は Phase 3（Chapter 3「システムの詳細設計」）
- 2026-05-20: **結合レポート全面リライト Phase 1（Chapter 1「計画書」）完了**。①draw.io 図 4 点を作成し `fig/` に `.drawio`＋`.png` を両方コミット: `fbs`・`pbs`（`meetings/0429_3回/事前課題共有/PBS/FBS/` の実画像を Read→下敷きに mxGraph XML 直書きで再描画。実画像は計画書旧記述や片岡レビューの記述より整理されていたため実画像準拠で作成）、`arrow`（アローダイアグラム・9 イベント・クリティカルパス約 8 週を赤強調・並行 240/250 を弧で表現）、`gantt`（13 週×12 タスク・5 フェーズ色分け・5/20 計画発表マーカー入り）。書き出しは `draw.io --export --format png --scale 2 --crop --border 14`。②WBS は 51 タスクのツリーが A4 で潰れるため**表化**（要素成果物粒度 13 行の `tabularx`、担当列付き）。③Ch1 を全執筆: 概要（題目/目的/独自性）・スコープ（成果物/対象範囲/FBS/PBS/対応表）・作業計画（WBS 表/アロー図/役割分担表/ガント図）・V&V（MOE 表＋MOP/TPM の 7 小節）・資源調達・リスク管理。片岡レビュー指摘を反映（24G 勢 3 名の役割を WBS の担当列と役割分担表に明示、「齊藤/斎藤」表記を「齋藤」に統一）。④参考文献（`thebibliography` 6 件）を Ch3 と Ch4 の間に追加（Ch1 引用は teru/ninntenndo/ref:douki/ref:onkai の 4 件、ref:chien/ref:beat は Ch2・3 用）。⑤MOE 表は当初 `\multirow{3}{10em}` で長文がセル高さを超え重なったため、WBS 表と同じ「MOE をヘッダ行（`\multicolumn`）にし MOP を字下げ」方式へ作り直して解消。ビルド `latexmk -lualatex` 成功・**21 ページ**（Ch1 は 11 ページ・予算 15 以内）・Overfull \hbox 0 件・Overfull \vbox 0 件・未定義参照なし。次は Phase 2（Chapter 2「システムの基本設計」、Block A/B 重複解消）。Phase 2 着手時に楽器名/音色（金管 vs オルガン/フルート/ベル）をユーザー確認
- 2026-05-20: **結合レポート全面リライト Phase 0（環境構築・骨格作成）完了**。①draw.io 書き出し環境を `brew install --cask drawio` で構築、CLI（`/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png --scale 2`）で日本語ラベル入り `.drawio` の PNG 書き出し疎通を確認。②ベースライン計測: `23_計画書・設計書_24G1075.tex` を欠損 3 画像（WBS/arrow/ganto）に実在画像を流用してビルド → **97 ページ**（Overfull \hbox 54 件・うち 12 件 20pt 超）。目標 ≤50 に対し約半減が必要と確定。③新本体 `report/計画書_中間発表/23_計画書・設計書.tex`（ファイル名はユーザー確定）を作成。preamble は `23_` 版から移植し graphicx 重複除去・`\usetikzlibrary` 統合・`\graphicspath{{fig/}}` 追加、章立ては `plan_template.tex` 準拠＋Ch4「生成AIの利用」、各 \section 直下に `% TODO(Phase N)` で作業計画 §6・§7 への対応を記入。骨格ビルド成功（11 ページ・Overfull 0）。④`fig/`（`.gitkeep`）作成。判明事項: `.gitignore` の `report/**/*.pdf` により report 配下 PDF は非コミット運用（conventions §4-3 と相違、要確認）。次は Phase 1（Chapter 1「計画書」）
- 2026-05-20: **結合レポート全面リライトの実行計画を策定**（大規模・複数セッション作業の起点）。先輩が結合した `report/計画書結合/23_計画書・設計書_24G1075.tex`（3077 行・178 KB）が枚数肥大・図表崩れを起こしているため、`report/計画書_中間発表/` 配下に 50 ページ以内の計画書・設計書を再構築する計画を `report/計画書_中間発表/_作業計画.md` に作成。調査で判明した要点: ①肥大の主因は Chapter 2・3 が「音楽/Processing 班マージ版(Block A)」と「Arduino/EMA 班マージ版(Block B)」を各節 2 回ずつ収録していること（重複行マップは計画書 付録 A）、②図参照 5 点中 `WBS.PNG`/`arrow.png`/`ganto.png` の 3 点が実体不在、FBS/PBS も `meetings/` 配下のみ、③`longtable` 30・`table` 11 で列幅オーバーフロー疑い多数。ユーザー確認で方針確定: 図は Claude が `.drawio`(XML) 直書き→draw.io CLI で PNG 書き出し→`\includegraphics`（draw.io MCP は未導入のため不採用）、変換スコープは欠損図＋崩れ図を優先。計画は Phase 0（環境構築・骨格）〜Phase 4（生成 AI 章・整合・最終調整）の 5 フェーズに分割、各フェーズ＝1 `/clear` 単位。今セッションは計画立案のみで実装は未着手
- 2026-05-19: 夜間レビュー PR #8（`claude/nightly-report-2026-05-18`、`.agent/reports/2026-05-18.md`）の **取り込み + 残存指摘 6 件中 6 件対応**。レポート本体を cherry-pick で main に取り込み（`0808e52`）、「次のアクション 1」の自走可能 6 件（1.1 / 1.2 / 1.3 / 1.4 / 1.7 / 2.1）を 1 コミット（`029fef0`）で一括反映。要点: ①1.1 `.agent/architecture.md:159` の `ScoreEvent` 架空 4 フィールド版 → 実体 9 フィールド（`beatAt/noteNumber/velocity/durationQ8/flags/subNote/subVelocity/subOffsetQ8/subDurationQ8`）に置換し `durationQ8` 単位（1/256 拍）と `flags`（bit0=NoteOn / bit2=休符）を補足、②1.2 `.agent/architecture.md:104` と `docs/.../architecture/score.md:78` の楽器名「金管/木管/弦」を実体「オルガン/フルート/ベル」に置換、score.md は「楽器名は data/*.json に依存」注記を追加、③1.3 `orchestra_resynth.pde:39` と `pc_app/test_v2/README.md:56` の partId 範囲「0x02-0x04」を「test_v2 0x02-0x04 / production 想定 0x02-0x05」併記に、④1.4 `OrcProtocol.h:53` NotePayload.partId コメントを同併記表現に、⑤1.7 `.pde` line 39 の instrumentId 行に「data/*.json をファイル名昇順ソートしたときの index」を明示、⑥2.1 `node_03/04/src/score_data.cpp` ヘッダコメント sed 過誤 4 箇所（`(node_03/03/04)` / `(node_03=0,` / `(node_04/03/04)` / `(node_04=0,`）を `(node_02/03/04)` / `(node_02=0,` に修正。**保留 6 件**: 1.5 `production/node_01/platformio.ini` board 修正（実機ビルド検証要・**3 夜連続保留**、CI が production を見ていないことが累積指摘の根本原因）、1.6 中間発表 `plan_25G1021.tex` PDF 追補（LuaLaTeX ローカルコンパイル要 + 5 台/3 台/金管 vs organ 方針判断要、user 作業）、2.2 NoteSender/OrcReceiver の `common/lib/` 集約（実機テスト要、2.1 と組合せて根治候補に昇格、Med-High）、2.3 `int32_t` wraparound（実害なし Low）、2.4 production CI 取り込み（1.5 解決後、Med）、2.5 SoftAP 平文（意図的設計 Low）。`team/roles.md` / `team/schedule.md` の「金管」表記は当時の役割分担として残す user 判断要のため未修正。docs build: `cd docs && npm run build` → 70 ページ生成、リンク切れエラー無し。レポート 4-B 提案「指摘 N.M のうち XX 件を対応」明示の習慣化を本エントリから採用
- 2026-05-18: 夜間レビュー PR #7（`claude/nightly-report-2026-05-17`、`.agent/reports/2026-05-17.md`）の **取り込み + 残存指摘の修正**。レビューファイルを cherry-pick で main に取り込み（`316c5b0`）、続けて昨日 1ad766b で取りこぼしていた docs 側の残存指摘 1.2/1.3/1.4/1.6/1.7/1.8 を 1 コミットで一括修正。要点: ①1.2 `<id>.json` 誤誘導を `firmware/note-sender.md` / `pc-audio/index.md` / `pc-audio/analyzer-overview.md` / `code/pc-app.md` / `essentials/analyzer.md`（2 箇所）/ `essentials/processing.md`（Mermaid 2 箇所）の 8 箇所で「pc_app/test_v2/orchestra_resynth/data/ のファイル名昇順 index」表現に置換、②1.3 essentials/firmware.md:129 の架空構造体名 `OrcReceiverData/ScoreData/NoteEmitterData` を実体名 `ReceiverLogicData/SyncLogicData/CtrlData/ScoreProgressData/NoteOutData/NoteSenderData` に置換、③1.4 `INSTRUMENT_ID/HEAD_REST_BEATS/PART_ID` 擬似定数の残存（deep-dive/score-progression / architecture/overview / architecture/score の 4 箇所）を `OrcReceiverConfig`/`NoteSenderConfig` の構造体リテラル引数（`instrumentId`/`partId`/`headRestBeats`）に書き換え、④1.6 docs 側 `bpmQ8` の「Q8 固定小数」表記を `architecture/protocol.md`（×2）/ `firmware/orc-protocol.md` / `firmware/orc-receiver.md` で「×8 整数（分解能 0.125 BPM、一般的な Q8 固定小数 = ×256 ではない）」に書き換え（`durationQ8` / `subOffsetQ8` 等は本物の Q8 固定小数なので不変）、⑤1.7 essentials/project.md の Mermaid から `N5["node_05<br/>未着手"]` を削除し図直下に「production 想定では node_05 を追加して 4 台構成」注釈追加、subgraph ラベルを `" 楽器ノード（test_v2 は 3 台）"` に変更（ダブルクォート維持）、本文 4 箇所と intro/overview.md 3 箇所を「現行 test_v2 3 台 / production 想定 4 台」併記に統一、⑥1.8 architecture/protocol.md の `partId | 0x02〜0x05` を「test_v2 0x02〜0x04（楽器 3 台）/ production 想定 0x02〜0x05（楽器 4 台）」併記に。**保留**: 1.9 `production/node_01/platformio.ini` の `board = uno_r4_wifi` → `seeed_xiao_esp32s3` 変更は実機ビルド検証要のため CLAUDE.md ルール準拠で保留（production は雛形扱い）、2.1 NoteSender/OrcReceiver の `common/lib/` 集約・2.2 `subOffsetQ8 < 256` コメント・2.3 `int32_t` wraparound も同ルールで保留。レビュー前提のズレ（PR #7 本文 `最新コミット: 703d30b` は bot のスナップショット時点、実 main は `ffac733` まで進行済）も認識。docs ビルド: `cd docs && npm run build` → 70 ページ生成、リンク切れエラー無し
- 2026-05-17: 夜間レビュー PR #6（`claude/nightly-report-2026-05-15`、`.agent/reports/2026-05-15.md`）の **マージ + 修正対応**。レビューファイルを cherry-pick で main に取り込み（`ac7fbb4`）、コード変更を伴わないドキュメント整合 1.1〜1.9 を 2 コミットに分けて反映: ①「[修正] essentials/firmware.md の時刻同期説明を実コードに同期」（`d4fa9ee`）で指摘 1.8 単独対応（offset の符号 `master − local`、EMA 係数 α=0.10、発音目標時刻 `playAtMasterMs − offsetMs`）、② 「[ドキュメント] 夜間レビュー 1.1-1.7/1.9 のドキュメント実装乖離を一括修正」（`1ad766b`）で残り 14 ファイルを修正。要点: 楽器ノード台数は `test_v2 は 3 台 / production 想定は 4 台` 併記に統一、音色 JSON パスを `pc_app/test_v2/orchestra_resynth/data/` に修正し `sound_lab/` は試作場と位置づけ、`instrumentId` はファイル名昇順ソートの index 参照（`0_organ.json` 等を実体名で列挙）、`bpmQ8` を「×8 整数（分解能 0.125 BPM）」に、`beatNo` は 1 オリジン、楽器側 SystemData の構造体名（`ReceiverLogicData`/`NoteOutData`/`NoteSenderData`/`SyncLogicData`/`CtrlData`/`PerformerStateData`/`ScoreProgressData`）と各フィールドを実体に置換、`HEAD_REST_BEATS`/`INSTRUMENT_ID`/`PART_ID` の架空擬似定数を `OrcReceiverConfig`/`NoteSenderConfig` の構造体リテラル引数に書き換え、`partId` 範囲を `0x02-0x04`（test_v2）/`0x02-0x05`（production 想定）併記に。実機テストが要るコード改修（2.1 楽器ノード重複モジュールの `common/lib/` への集約、2.2 `subOffsetQ8` 範囲制限コメント、2.3 `int32_t` wraparound 対策）は CLAUDE.md「実機未テスト .ino/.cpp に Claude 起点で追加変更を入れない」ルールに従い次回保留。docs ビルド: `cd docs && npm run build` で 70 ページ生成、リンク切れエラーなし
- 2026-05-15: essentials 4 ページに Mermaid 図解を合計 24 個追加。同時に **Starlight への Mermaid 描画機能を導入**。Starlight は標準で Mermaid をレンダリングせず既存図もコードブロックとして生表示されていた問題に対し、`astro.config.mjs` の `head:` に CDN（jsdelivr）から mermaid@11 を読み込み、`<pre data-language="mermaid">` を `<div class="mermaid">` に置換して `mermaid.run` を呼ぶ自前スクリプトを登録。expressive-code が各行を `<div class="ec-line">` に分解するため、`.ec-line` を走査して `\n` で連結する `extractCode` 関数で本来のソースを復元。Mermaid v11 はノードラベル内の `()` `:` を厳密に拒否するため、project.md の「(1台)/(4台)/(未着手)」、processing.md の `y(t)`、analyzer.md の「(JSON に書かない)」をダブルクォート囲みに修正。追加図解の内訳: project.md は「1 拍が鳴るまでの旅」sequenceDiagram と「同期は 4 つの層」flowchart の 2 個、firmware.md は状態機械 stateDiagram・拍検出 flowchart・時刻同期 sequenceDiagram・輪唱頭ずらしの 4 個、processing.md は 3 スレッド sequenceDiagram・加算合成信号フロー・揺れの効果比較・音色 JSON の流れの 4 個、analyzer.md は基音検出/揺れ検出/ADSR フィット/倍音抽出/残差ノイズの 5 個と既存 1 個の補強。Playwright で全 24 図の `svg .error-icon` が無いことを確認、既存 architecture/overview の Mermaid も同スクリプトで描画。npm run build で 70 ページ生成、リンク切れ無し
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
