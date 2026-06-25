# firmware/production — ゲームモード（かえるのうた輪唱 + テンポ採点）

`firmware/test_v2`（きらきら星→かえるのうた輪唱）の続編。**指揮者 1 + 楽器 5** の
6 ノード構成・マスタクロック同期・拍番号駆動の楽譜進行を踏襲し、
**ゲームモード**を追加した版：

- **2 モード構成**: ①自由演奏（実振り BPM で輪唱）／②ゲーム（目標テンポ 100 BPM を
  どれだけ維持できたかを 0–100 点で採点）
- **IMU メニューナビ**: キャリブレーション完了後に `Menu` 状態へ入り、指揮棒の
  左右振りでカーソル移動・縦振りで決定（`node_01/src/applyPattern.cpp` の `updateNav`）
- **採点**: ゲーム中は拍ごとに「実振り間隔 − 目標拍間隔」の誤差を、メトロノームガイドが
  薄い区間ほど重い重みで累積。32 拍（かえるのうた 1 周）で 0–100 点に写像して `Result` へ
- **メトロノームガイド**: ゲーム序盤 8 拍は LED（node_01）と PC クリック音がフルガイド、
  8〜16 拍で線形フェードアウト、以降はガイドなし（記憶でテンポ維持）
- **CTRL 予約 4B をフィールド化**: `mode/navCursor/targetBpm/score` を指揮者→楽器に配信
- **PKT_UI (type=4)**: node_02 だけが受信 CTRL の中身を USB シリアルで PC に中継する
  （`UiRelayModule`）。UDP には流れないので同期経路（CTRL/BEAT/NOTE）に影響しない
- **楽譜は「かえるのうた」32 拍**（`node_02〜05/src/score_data.cpp`）。8 分音符は
  `subNote`（拍裏の予約発火）で表現
- **4 台輪唱 + ドラム**: 金管4声が 8 拍（1 フレーズ）ずつ遅れて入り、ドラムが
  4/4拍子で全体を支える。周回は輪唱サイクル
  `CANON_CYCLE_BEATS=56` 拍（曲長 32 + 最終声部の遅延 24）を全声部で共有し、
  最終声部（node_05）が 1 周を終えるまで先頭声部は次の周回を始めない

| ディレクトリ | 内容 |
|---|---|
| [`common/`](common/) | 全ノード共通ライブラリ（`OrcProtocol`（PKT_UI 追加） / `OrcNetModule` / `StatusLedModule` / `ModuleCore`） |
| [`node_01/`](node_01/) | 指揮者ノード（XIAO ESP32-S3 Sense + GY-521）。Menu/Result 状態・IMU ナビ・採点 |
| [`node_01_devkitc/`](node_01_devkitc/) | 指揮者の ESP32-S3-DevKitC-1 派生（ロジック同一・ビルド設定のみ差分） |
| [`node_02/`](node_02/) | 輪唱 声部 1（partId=0x02, headRestBeats=0, instrumentId=0=トランペット）+ **UI 中継** |
| [`node_03/`](node_03/) | 輪唱 声部 2（partId=0x03, headRestBeats=8, instrumentId=1=ホルン） |
| [`node_04/`](node_04/) | 輪唱 声部 3（partId=0x04, headRestBeats=16, instrumentId=2=トロンボーン） |
| [`node_05/`](node_05/) | 輪唱 声部 4（partId=0x05, headRestBeats=24, instrumentId=3=チューバ） |
| [`node_06/`](node_06/) | ドラム（partId=0x06, headRestBeats=0, instrumentId=4）。1・3拍目キック、2・4拍目スネアの4/4拍子 |

金管4声の楽譜（`node_02`〜`node_05` の `score_data.cpp`）は同一（= 輪唱）。
ドラム（`node_06`）は別譜で、1・3拍目キック、2・4拍目スネアの4/4拍子を演奏する。
金管側の差分は ProjectConfig.h と node_02 のみ持つ `UiRelayModule` だけ。

## クイックスタート

```bash
# 1. 指揮者ノードを書き込む（XIAO 版。DevKitC なら node_01_devkitc）
pio run -d firmware/production/node_01 -t upload

# 2. 楽器ノードを書き込む
pio run -d firmware/production/node_02 -t upload   # 声部 1（メイン操作 UI 用）
pio run -d firmware/production/node_03 -t upload   # 声部 2
pio run -d firmware/production/node_04 -t upload   # 声部 3
pio run -d firmware/production/node_05 -t upload   # 声部 4（最終声部）
pio run -d firmware/production/node_06 -t upload   # ドラム

# 3. Mac で Processing を起動し pc_app/production/orchestra_resynth/orchestra_resynth.pde を Run
#    画面のポート一覧で繋いだ Arduino のポートをクリックして開く
#    （node_02 を開いた Mac がメイン操作 UI、node_03〜05 はアナライザとして自動判定）
```

## 状態遷移（指揮者 node_01）

```
Idle ─(SoftAP up)→ Calibrating ─(2s)→ Menu
Menu ─(左右振り=カーソル / 縦振り=決定)→ Conducting(自由演奏 or ゲーム)
Conducting(ゲーム) ─(32 拍到達)→ Result ─(縦振り)→ Menu
Conducting ←(IMU/WiFi 喪失)→ Fallback（復帰で元の状態へ）
```

LED: Idle=1Hz 点滅 / Calibrating=2Hz / Menu=約1.7Hz / Conducting=点灯
（ゲーム序盤は目標テンポで点滅=LED メトロノーム）/ Result=高速点滅 / Fallback=5Hz。

## マスタクロック方式（test_v1/v2 から踏襲）

指揮者の `millis()` をマスタ時刻として全ノードで共有する。BEAT は「マスタ時刻
`playAtMasterMs` に発音せよ」という未来時刻指定で送り、楽器側は CTRL/BEAT 受信時に
offset を EMA で学習、`millis() + offset` が `playAtMasterMs` に到達した瞬間に楽譜を
1 拍進める。指揮者がリセットされて時計が巻き戻った場合は offset の大ジャンプを検知して
スナップ追従する（`OrcReceiverModule` の clockSyncSnapThresholdMs）。

## 詳細

- ゲームモード設計の SSOT: `.agent/production-game-design.md`
- プロトコル（CTRL 予約バイト / PKT_UI）: `common/lib/OrcProtocol/OrcProtocol.h`, `.agent/api.md`
- 採点・ナビ・ガイドの実装: `node_01/src/applyPattern.cpp`, `node_01/include/ProjectConfig.h`
- UI 中継: `node_02/lib/UiRelayModule/`
- PC 側の画面・合成: `pc_app/production/orchestra_resynth/`
