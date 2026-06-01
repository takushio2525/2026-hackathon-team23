# test_v3 ゲームモード 設計メモ

> 本ファイルは test_v3（ゲームモード）実装の設計 SSOT。Phase 1 残り（設計）の成果物。
> 実装は Phase 2 以降で master 指示のもと着手する。本メモは「何をどう作るか」を確定し、
> 各 Phase の着手前に Read する位置づけ。test_v2 / firmware/production は一切触らない。
>
> 前提: Phase 1 コピー（`6e27071`）で `firmware/test_v3`（node_01/01_devkitc/02/03/04 + common）と
> `pc_app/test_v3/orchestra_resynth` は test_v2 の複製済み。ファイル冒頭コメントの `test_v2` パスは
> コピー由来でまだ未修正（実害なし。実装時に test_v3 へ直す）。

## 0. ゲーム仕様（計画書 §4-2 準拠）

- **2 モード構成**: ①自由演奏（実振り BPM で輪唱）／②ゲーム（目標テンポを提示→維持精度を 0–100 点採点）。
- **司令塔 = node_01**: モード選択（IMU ナビ）も採点も node_01 が担う。指揮者ノードに PC は付かない。
- **演奏テンポは常に実振り BPM**（ゲームでも CTRL の `bpmQ8` 源は切り替えない）。目標テンポは採点基準＋ガイド用。
- **目標テンポ = 1 曲 1 つ固定**（config 値）。曲を通して維持できたかを採点。
- **メトロノームガイド**: 曲頭は目標テンポで刻み（node_01 の LED ＋ PC のクリック音）、進行とともに段階フェードアウト、
  終盤はガイドなし。フェードは固定スケジュール（経過拍ベース）で **通信不要**（各々がローカルに計算）。
- **採点**: 実振り間隔と目標拍間隔の誤差を集計。ガイドが薄い／無い区間ほど重く配点。
- **伝達**: CTRL 予約 4 バイトに mode／目標 BPM／score／ナビ状態を載せ、指揮者→楽器→PC へ中継。**新 UDP 種別は増やさない**。
- **表示 = 楽器側 PC（Processing）**。

## 1. 全体フローと状態機械（node_01）

既存 `ConductorState`（Idle/Calibrating/Conducting/Fallback）に **Menu** と **Result** を追加する。

```
Idle ─(WiFi up)→ Calibrating ─(2s 完了)→ Menu
Menu ─(IMU 縦振り=決定: 自由演奏)→ Conducting(mode=free)
Menu ─(IMU 縦振り=決定: ゲーム)──→ Conducting(mode=game, ゲーム計数リセット, score=0)
Conducting(free)  : 従来どおり。拍検出→BEAT/CTRL。終了概念なし（手動でやめる）
Conducting(game)  : 拍検出に加え、経過拍カウント＋採点＋ガイドフェード。
                    経過拍 ≥ GAME_LENGTH_BEATS で → Result
Result            : 拍検出オフ。score を凍結表示。IMU 縦振り=決定 → Menu へ戻る
任意状態 ─(IMU timeout / WiFi down)→ Fallback ─(復帰)→ 直前へ（実装簡略のため Menu へ戻すのも可）
```

排他の要点（後述 §3）: **拍検出は `state==Conducting` のときだけ**動く（既存構造そのまま）。
**IMU ナビは `state==Menu || state==Result` のときだけ**動く。両者は状態が排他なので同時実行されない。

`state`（CTRL offset 15）の値割当（api.md / 計画書と整合）:

| 値 | 状態 | 備考 |
|---|---|---|
| 0 | Idle | |
| 1 | Calibrating | |
| 2 | Conducting | 演奏中（mode で自由/ゲームを区別） |
| 3 | Fallback | |
| 4 | Menu | 計画書の `ModeSelect` に対応（本実装では Menu と命名） |
| 5 | Result | ゲーム結果表示中 |

## 2. (a) CTRL 予約 4 バイトの割当

`OrcProtocol.h` の `CtrlPayload`（offset 12–19、計 8B）。前半 4B（`bpmQ8`/`velocity`/`state`）は不変。
**`reserved[4]`（offset 16–19）を以下に割り当てる**。

| offset | サイズ | 新フィールド | 内容 |
|---|---|---|---|
| 16 | 1B | `mode` | 0=自由演奏 / 1=ゲーム |
| 17 | 1B | `navCursor` | メニューカーソル位置 0..N（Menu/Result で有効。演奏中は 0） |
| 18 | 1B | `targetBpm` | 目標テンポ（**生 BPM 40–240**、0=未設定/自由演奏では無視） |
| 19 | 1B | `score` | 0–100。0xFF=採点中/未確定 |

**「画面」はバイトを消費しない**: PC は `(state, mode)` から画面を導出する（§5）。`state` が
Menu/Result/Conducting を、`mode` が自由/ゲームを示すので画面は一意に決まる。カーソルだけ別バイトが要る。

構造体（実装時の `CtrlPayload` 置換案、20B 固定・static_assert は維持される）:

```cpp
struct CtrlPayload {
    uint16_t bpmQ8;        // 実振り BPM ×8（不変）
    uint8_t  velocity;     // 0-127（不変）
    uint8_t  state;        // 0..5（Menu=4/Result=5 を追加）
    uint8_t  mode;         // 0=自由演奏 / 1=ゲーム
    uint8_t  navCursor;    // メニューカーソル 0..N
    uint8_t  targetBpm;    // 目標テンポ（生 BPM, 0=未設定）
    uint8_t  score;        // 0-100, 0xFF=未確定
};
```

> ⚠️ **計画書 §4-2 / Phase 4A からの逸脱（master 確認）**: 計画書は予約 4B を `mode(1B)/targetBpmQ8(2B)/score(1B)`
> と記述したが、それだと「ナビ状態（カーソル）」を入れる空きが 0 になる。目標テンポに 0.125 BPM 精度は
> 不要（曲ごとの粗い固定値）なので **`targetBpmQ8`(2B) → `targetBpm`(1B 生 BPM)** に簡素化し、空いた 1B を
> `navCursor` に充てた。**代替案**: targetBpmQ8(2B) を維持し mode+navCursor を 1B にビットパック（offset18:
> bits0-3=cursor / bit4=mode、offset19=score）。報告書の表記を優先するならこの代替案。**推奨は前者**
> （本プロジェクトは全域でビットパック非採用＝1 バイト 1 フィールドの素直な並びで統一されているため）。
> どちらにせよ報告書（`report/計画書_中間発表/`）の CTRL 表は後で追従が要る（本メモでは触らない）。

## 3. (b) node_01 IMU ナビ＋拍検出との排他

### 排他の仕組み
既存 `applyPattern.cpp` は拍検出を `if (state==Conducting && imu.ready)` でガードし、
`else if (state != Conducting)` で `gateToIdle()` している。**この構造を流用**し、Menu/Result では拍検出が
自動的に止まる。ナビは別ブロック `if (state==Menu || state==Result)` で動かす。両者は state が排他なので
衝突しない。`applyPattern.cpp` 冒頭の IMU LPF＋`dynNorm`/`dynAcc` 算出（`imu.ready` で常時実行）はそのまま
利用でき、ナビでも `dynAcc[]` が使える（経路長の二重積分 `sVel/sPathLen` は Conducting+Armed 限定なので
ナビには影響しない）。

### ナビ判定（単純閾値・複雑なジェスチャ認識はしない）
加速度ベクトル `dynAcc[]`（重力差し引き済み・LPF 後）の **左右(X)・上下(Y)成分の符号と大きさ**で判定する。

- **支配軸の決定**: `|dynAcc[LR]|` と `|dynAcc[UD]|` の大きい方を「今の振り方向」とする。
- **しきい値超え**: `dynNorm > NAV_SWING_THRESHOLD_G` を満たした瞬間（立ち上がりエッジ）に 1 回だけイベント発火。
  - 支配軸 = 左右 → カーソル移動（`dynAcc[LR]` の符号で −1/+1）。`navCursor` を `[0, itemCount-1]` でクランプ（巡回でも可）。
  - 支配軸 = 上下 → 決定（カーソル位置の項目を確定）。
- **多重発火防止**: 拍検出と同じく簡易ゲート（navIdle⇄navArmed）。`NAV_SWING_THRESHOLD_G` 超えで navArmed＋発火、
  `dynNorm < NAV_RELEASE_G` で navIdle に復帰。加えて `NAV_REFRACTORY_MS` の不応期で 1 振り=1 操作を担保。

### 新規 config（`node_01/include/ProjectConfig.h` の `logic_params` に追加）
```cpp
constexpr uint8_t  NAV_LR_AXIS            = 0;     // 左右 = X 軸（実機の取付向きで確定。要実機調整）
constexpr uint8_t  NAV_UD_AXIS            = 1;     // 上下 = Y 軸（同上）
constexpr float    NAV_SWING_THRESHOLD_G  = 1.00f; // ナビ振り検出（拍検出 1.20g より気持ち低め。要実機調整）
constexpr float    NAV_RELEASE_G          = 0.30f; // ナビゲート解放
constexpr uint32_t NAV_REFRACTORY_MS      = 400;   // ナビ不応期（誤連打防止）
constexpr uint16_t GAME_LENGTH_BEATS      = 24;    // ゲーム 1 セッションの拍数（かえるのうた 1 周。要相談）
constexpr uint8_t  GAME_TARGET_BPM        = 100;   // 目標テンポ（固定）
```

> **要実機確認**: LR/UD の軸番号と符号は IMU の物理取付に依存する。実機で「右に振る→カーソル右」になる軸/符号を
> 確定する（机上では決められない＝鉄則どおり実機はユーザー）。本メモは X=左右 / Y=上下 を暫定とし config で差し替え可能に。

### SystemData 追加（node_01）
`ConductorStateData` を Menu/Result 込みに拡張、`mode`/`navCursor`/`targetBpm`/`score`/`gameBeatCount` を持つ
`GameData`（新規）を追加。`TempoLogicData` 等は不変。CTRL 送信（`OrcSenderModule`）が `data.game.*` を
予約バイトに詰める。

## 4. (c) node_02 UI 状態シリアル中継フレーム

### 方針: 既存 20B プロトコルに **新 type=4 (PKT_UI)** を追加（NOTE 20B は不変）
node_02 は受信した CTRL（mode/state/navCursor/targetBpm/score/bpmQ8）を、**演奏 NOTE バイナリ出力に加えて**
UI 状態フレームとして USB シリアルで PC に中継する。ヘッダ（magic 0x4F52 / version 1 / 12B）と全長 20B は
NOTE と同形式なので、PC の既存フレーム同期（magic 探索→20B 収集）はそのまま使える。

`OrcProtocol.h` に追加（UDP では type=4 を一切送らないので同期経路に無影響）:
```cpp
enum PacketType : uint8_t { PKT_CTRL=1, PKT_BEAT=2, PKT_NOTE=3, PKT_UI=4 };

struct UiPayload {              // 8B（offset 12-19）
    uint8_t  state;            // 0..5（Idle/Calibrating/Conducting/Fallback/Menu/Result）
    uint8_t  mode;            // 0=自由演奏 / 1=ゲーム
    uint8_t  navCursor;       // メニューカーソル
    uint8_t  targetBpm;       // 目標テンポ（生 BPM）
    uint8_t  score;           // 0-100 / 0xFF
    uint8_t  partId;          // どの楽器ノードからの中継か（PC の役割判定用）
    uint16_t bpmQ8;           // 実振り BPM ×8（演奏画面のテンポ表示用）
};
```

### 送出頻度（制約: 低頻度・別管理で BEAT/NOTE 経路を阻害しない）
CTRL は 20Hz で届くが、**UI フレームは「内容が変化したとき」＋「最大 5Hz の保険送出」**に絞る。これで USB シリアル
（115200bps）上の NOTE バーストを邪魔しない（UI フレーム 20B×5Hz=100B/s ≪ 11.5KB/s）。実装は node_02 の出力フェーズに
軽量モジュール `UiRelayModule`（新規・`updateOutput` のみ）を足し、`data.ctrl` の前回値と比較して変化時のみ
`Serial.write(UiPacket)`＋`Serial.flush()`。`SERIAL_DEBUG=1` 時はバイナリを流さない（既存 NoteSender と同じ扱い）。

### 中継は node_02 のみ（最小構成・タスク準拠）
node_02 = メイン操作 UI が付く PC、node_03/04 = アナライザ PC。よって **UI 中継は node_02 だけに入れる**。
node_03/04 はアナライザで「待機↔演奏」を NOTE 到来（`lastNoteAtMs`）から判定すればよく、mode/score は不要。
- **代替案**: 全楽器ノードに `UiRelayModule` を入れ、アナライザ側でも「演奏/ゲーム」ラベルや score を出す。
  ファームが node 間で完全均一になり EMA 的に綺麗だが、タスクの役割分担（node_02=操作 / node_03,04=解析）を
  そのまま満たすなら node_02 のみで十分。**推奨は node_02 のみ**（最小・タスク文言どおり）。全ノード化は後で容易。

### node_02 の OrcReceiver / CtrlData 追加
`OrcReceiverModule` が CTRL 受信時に予約バイトを `data.ctrl` の新フィールド（`mode`/`navCursor`/`targetBpm`/`score`）へ
展開する（既存の bpm/velocity/state 展開に追記）。`CtrlData` にそれらのフィールドを追加。

## 5. (d) Processing（pc_app/test_v3）の画面遷移

### 役割の手動選択を廃止し、来たデータで自動判定
梅澤 UI（`work/umezawa/hck/processing/`）は Title 画面で Node1/Node2-6 を手動選択していたが、**これを廃止**。
画面は「ポート選択（マウス）」→「以降はマイコンから来るデータで自動判定」に変える。

役割判定:
- **UI フレーム（type=4）を受信**、または **NOTE の partId==0x02** → **メイン操作 UI**（node_02 接続）。
- **NOTE のみ（partId==0x03 / 0x04）で UI フレーム無し** → **アナライザ**（node_03/04 接続）。

### 画面集合
- **ポート選択画面**: 既存どおりマウスでポートをクリック（`drawPortList` を流用）。役割選択は出さない。
- **メイン操作 UI（node_02）**: UI フレームの `(state, mode, navCursor, targetBpm, score, bpmQ8)` で画面を自動決定:
  - `state==Menu` → **メニュー画面**（項目: 自由演奏 / ゲーム。`navCursor` でハイライト。指揮者の操作が即反映）。
  - `state==Conducting && mode==free` → **自由演奏画面**（実振り BPM・受信状態を表示。NOTE で発音）。
  - `state==Conducting && mode==game` → **ゲーム演奏画面**（目標テンポ表示・メトロノームクリック（フェード）・ライブ score）。
  - `state==Result` → **結果画面**（最終 score を大きく表示）。
- **アナライザ（node_03/04）**: NOTE 到来で「待機→演奏/ゲーム」を切替え、**FFT / 波形**を描画（既存 `drawScope` 拡張）。
  mode を持たないので「演奏中」を NOTE 活動から汎用表示（ゲーム/自由のラベル分けは不要、最小構成）。

### 画面導出は「データ駆動」（梅澤の screenState 手動遷移を置換）
`draw()` 冒頭で `drainPackets()` 後、最新の UI 状態 or NOTE 活動から **毎フレーム画面を再判定**（明示的な
画面遷移コマンドは持たない＝マイコンが真実）。これにより指揮者の Menu 操作が PC に即反映される。

### メトロノームクリックのフェード（ゲーム画面・PC ローカル計算・通信不要）
PC はゲーム画面に入った時刻と `targetBpm` を持つので、`60000/targetBpm` ms ごとにクリック音を鳴らし、
経過に応じて音量を 1.0→0 に固定スケジュールでフェードする（node_01 の LED ガイドと独立・同方針）。score は
node_01 が算出して中継するので PC は表示のみ。

## 6. 採点とメトロノームフェード（node_01・Phase 2 詳細）

- **ガイド強度** `guide(t)`: ゲーム開始からの経過拍 `b` に対し固定スケジュールで 1.0→0（例: 前半 1.0、中盤で線形減衰、終盤 0）。
  node_01 の LED と PC のクリック音が各々ローカルに同じ式で計算（通信不要）。
- **採点**: 拍が確定するたび「実振り間隔 `instInterval` と目標拍間隔 `60000/targetBpm` の誤差」を取り、
  `weight = 1 - guide(b)`（ガイドが薄いほど重い）で重み付けして誤差を累積。曲終了時に累積誤差を 0–100 に写像
  （誤差小=高得点）。`score` は途中経過（0xFF=確定前 or 暫定値）として CTRL に載せ、Result で確定。
- これらは `Conducting && mode==game` の `applyPattern` 内で動く。自由演奏・Menu・Result では走らせない。

## 7. 同期性能・互換性への影響（制約遵守の確認）

- **UDP 同期経路（BEAT/NOTE/CTRL）は不変**。CTRL は予約バイトの中身を埋めるだけで長さ 20B・送出 20Hz・seq とも不変。
  → 楽器間 20ms / 指揮→楽器 30ms の同期目標に影響しない。
- **新 type=4 は USB シリアルのみ**（楽器→PC）。UDP マルチキャストには一切流さない → radio 負荷・パケロスに無影響。
- **UI フレームは低頻度（変化時＋最大 5Hz）** で NOTE バーストと干渉しない。NOTE 20B 出力・`Serial.flush()` の挙動は不変。
- **既存 20B プロトコル互換**: magic 0x4F52 / version 1 / 全長 20B / ヘッダ 12B は不変。PC は未知 type を無視する設計を維持
  （現状 `handlePacket` は type!=NOTE を return。type==CTRL/UI を解釈する分岐を追記するだけ）。
- 拍検出ロジック・楽譜進行・OrcReceiver の発音判定は **無変更**（自由演奏は test_v2 と同一挙動を保つ）。

## 8. Phase 2 以降の実装タスク分解（master 指示後）

1. **共通**: `OrcProtocol.h` に `PKT_UI=4`・`UiPayload` 追加、`CtrlPayload` の予約 4B をフィールド化（20B static_assert 維持）。
2. **node_01**: `ConductorState` に Menu/Result、`GameData` 追加。`applyPattern.cpp` に Menu ナビ・ゲーム計数・採点・ガイド、
   Calibrating→Menu 遷移。`OrcSenderModule` で予約バイトを送出。`ProjectConfig.h` に NAV_*/GAME_* 追加。（node_01_devkitc も同期）
3. **node_02**: `CtrlData` 拡張＋`OrcReceiverModule` で予約バイト展開、`UiRelayModule`（新規）を出力フェーズに追加。
4. **Processing(test_v3)**: 役割自動判定、type=1/4 フレーム解釈、メニュー/自由/ゲーム/結果/アナライザの画面群、メトロノームフェード。
5. 各ノード `pio run` でビルド確認（実機 upload・評価はユーザー）。区切りごとにコミット。

## 9. 未確定・master 確認事項

- **CTRL レイアウト**: `targetBpm`(1B) 案（推奨）か、`targetBpmQ8`(2B)＋mode/cursor ビットパック案か（§2 の警告）。
- **ゲーム長 `GAME_LENGTH_BEATS`** と目標テンポ `GAME_TARGET_BPM` の具体値（かえるのうた 1 周=24 拍を仮置き）。
- **採点式の写像**（誤差→0-100 のカーブ）の具体化。Phase 2 で詰める。
- **UI 中継を node_02 のみ／全ノード** どちらにするか（§4 推奨は node_02 のみ）。
- **IMU ナビの軸/符号/しきい値**は実機調整必須（机上では決め切れない）。
- **5 台構成（node_05/06）** は test_v2-latency 同様、輪唱の位相（編曲＝音楽判断）が絡むので本設計では非対象（保留）。
</content>
</invoke>
