---
title: orchestra_resynth.pde の全体構造
description: Processing スケッチを setup / draw / UI / 入力 のレイヤで分解し、どこに何が書かれているか読み解く
sidebar:
  order: 3
---

実体: `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde`（約 720 行）。

このページは **「ファイルを上から眺めるとどんな構造か」** を把握するためのもの。
個別アルゴリズム（合成・解析・シリアル）は別ページに分かれている。

## ファイルレイアウト

```
orchestra_resynth.pde
├─ 先頭コメント (1〜48)     仕様・操作・パケット仕様の要約
├─ import 群 (50〜56)
├─ 設定定数 (58〜69)        SERIAL_BAUD / PACKET_SIZE / MAGIC_LO,HI / MAX_POLYPHONY 等
├─ グローバル状態
│   ├─ Minim audio (71〜73)
│   ├─ 楽器定義 配列 (75〜78) instrumentFiles / models / modelLabels
│   ├─ PortConn クラス + ポート集合 (80〜96)
│   └─ activeVoices / 表示用 (98〜108)
│
├─ settings() / setup() (111〜143)
│   ├─ ウィンドウサイズ
│   ├─ Minim 初期化
│   ├─ rescanInstruments() : data/ をスキャンして JSON ロード
│   └─ refreshPorts()      : Serial.list() で USB を列挙
│
├─ 楽器スキャン (146〜184)   rescanInstruments / modelForId
├─ シリアル開閉 (187〜223)   refreshPorts / openPort / closePort / togglePort
├─ シリアル受信 (227〜250)   serialEvent (Serial スレッド)
├─ パケット復号 (253〜280)   drainPackets / handlePacket
├─ 発音管理 (283〜319)       triggerNote / releaseMatching / stopAll / playTestChord
│
├─ draw() (322〜339)         ① drainPackets ② scheduledOffMs 判定 ③ done 回収 ④ UI 描画
├─ UI パーツ (342〜450)
│   ├─ drawBackground (グラデ)
│   ├─ glassPanel       (角丸半透明パネル)
│   ├─ drawHeader       (タイトルバー)
│   ├─ drawScope        (波形オシロ)
│   ├─ drawStatus       (受信状況)
│   ├─ drawInstrumentList (data/*.json リスト)
│   └─ drawPortList     (シリアルポート開閉ボタン)
├─ 入力 (453〜470)            mousePressed / keyPressed
├─ dispose() (472〜477)       終了処理
│
├─ class InstrModel (485〜585)    JSON → 合成用配列
└─ class ResynthVoice (599〜721)  1 音ぶんの UGen
```

## 起動シーケンス

```
settings()                 size(900, 560) を宣言（Processing の決まり事）
   ↓
setup()
  ├─ surface.setTitle()
  ├─ loadJapaneseFont(13) → Hiragino → Yu Gothic → Meiryo → Noto の順に試す
  ├─ minim = new Minim(this)
  ├─ out = minim.getLineOut(STEREO, 1024, 44100)
  ├─ rescanInstruments()
  │     ├─ dataPath("") を listFiles()
  │     ├─ *.json を name で昇順ソート (= 楽器番号 0,1,2,…)
  │     └─ 各 JSON を InstrModel に変換
  └─ refreshPorts()
        └─ Serial.list() でポート名一覧を取得 (まだ open はしない)
```

`out = minim.getLineOut(...)` の **第 2 引数 1024 は内部バッファサイズ**。これを小さく
すると音は早く出るが xrun のリスクが上がる。1024 は安全側（≈ 23 ms）。

## draw() の責務 — 1 フレーム約 16.7 ms (60 fps) でやること

```java
void draw(){
  drainPackets();                              // ① 受信したパケットを発音指示に変換

  int now = millis();
  for (ResynthVoice v : activeVoices)         // ② durationMs 到達した voice を release
    if (!v.releasing && now >= v.scheduledOffMs) v.noteOff();

  for (Iterator<ResynthVoice> it = activeVoices.iterator(); it.hasNext();){
    ResynthVoice v = it.next();
    if (v.done){ v.unpatch(out); it.remove(); }   // ③ 終わった voice を回収
  }

  drawBackground();                           // ④ UI 描画
  drawHeader(); drawScope(); drawStatus();
  drawInstrumentList(); drawPortList();
}
```

**1 フレームあたりの計算量** は: voice 数 × 数演算（patch 操作のみ）＋ UI 描画。
voice の音そのものは Audio スレッドが別途まわす。

### なぜ `noteOff()` を draw() で呼ぶのか

選択肢として「Audio スレッドの `uGenerate()` 内で `tSec >= scheduledOffSec` を見て自分で
release に入る」も考えられる。塩澤が draw() に置いたのは:

1. `scheduledOffMs` は `millis()` 基準 (Animation 時計)。Audio スレッドの `tSec` とは
   時計が違う。両者をまたぐと境界バグが出やすい
2. release 開始ロジックは Voice の **外側の状態（activeVoices の最古を release する判断）**
   に依存することもあるので、Animation 側で集中管理した方が安全
3. 60 fps なら最大 16.7 ms ぶん発音が伸びる可能性があるが、ハッカソンの聴感上は許容

## UI 設計（Glass Pastel 流用）

| パネル | 関数 | 内容 |
|---|---|---|
| 背景グラデ | `drawBackground()` | 青→ピンク→水色のリニアブレンド |
| 角丸半透明 | `glassPanel(x,y,w,h)` | 全パネル共通の角丸 + 白半透明 + 内側ハイライト |
| ヘッダ | `drawHeader()` | タイトル・読み込み状況・キー操作ヒント |
| 波形オシロ | `drawScope()` | `out.left.get(i)` を走査して折れ線描画 |
| 受信状況 | `drawStatus()` | 累計パケット・最後の NOTE 経過時間・声部ごとの直近イベント |
| 楽器一覧 | `drawInstrumentList()` | data/*.json と楽器番号の対応表 |
| ポート一覧 | `drawPortList()` | クリックで開閉できるボタンリスト |

全パネルで `glassPanel(x,y,w,h)` を最初に呼んで角丸ガラスを敷く、そのうえに文字を載せる、
の繰り返し。**ロジックは無く UI 描画のみ**。

## キー操作

`keyPressed()` で `Character.toLowerCase(key)` してから分岐:

| キー | 動作 |
|---|---|
| `r` | `refreshPorts()` を呼んでシリアルポートを再列挙 |
| `i` | `rescanInstruments()` で data/ の JSON を再読み込み |
| `t` | `playTestChord()` で C・E・G を楽器 0/1/2 で同時に鳴らす |
| `0`〜`3` | その番号の楽器で C4 を 1 発鳴らす（試聴用） |
| `a` | 振幅包絡を「実エンベロープ ↔ ADSR 4 値」で切替 |
| `+` / `-` | `masterVolume` を 0.05 刻みで増減（範囲 0.05〜1.5） |
| Space | `stopAll()` で全ボイス即停止 |

**Arduino を繋がなくても `t` キー 1 つで音が出る** ようにしてあるのは、リハーサル時に
PC 側だけ動作確認するため。

## マウス操作

`mousePressed()` は **ポート一覧の行をクリックで開閉** する 1 機能のみ:

```java
for (int i=0;i<portRowCount;i++){
  float ry = portRowY0 + i*portRowH;
  if (mouseOver(portRowX, ry, portRowW, portRowH-2)){
    togglePort(availablePorts[i]); return;
  }
}
```

`portRowX / portRowY0 / portRowH / portRowCount` は `drawPortList()` が
当該フレームで計算して保存している（描画の都度更新）。**描画時に確定した座標を入力側で
使う**ので、ウィンドウリサイズしても座標が追従する（現状リサイズは無効化しているが、設計の保険）。

## 終了処理（`dispose()`）

Processing が閉じるときに呼ばれる:

```java
void dispose(){
  closeAllPorts();        // 全 PortConn を stop() してマップから削除
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}
```

シリアルポートの close を忘れると、次回起動時に「ポートが他のプロセスにつかまれている」
状態になりやすい。**`closeAllPorts()` を最初に呼ぶ** のがコツ。

## マルチスレッドの境界

| スレッド | 触っていい状態 | 禁止 |
|---|---|---|
| Serial | `PortConn` 内のフィールド、`packetQueue.offer()` | `activeVoices` / `models` / `out` |
| Animation (draw) | 全部 | `serialEvent` 内のローカル変数 |
| Audio (Minim) | `ResynthVoice` 内部の自分のフィールド | `activeVoices` の構造変更（add/remove） |

特に **`activeVoices.iterator()` を draw() 以外から触らない** のがルール。draw() の
回収ループ中だけ `it.remove()` を許可している。

## どこを書き換えるか（別構成にしたい人向け）

- **UI を全部消して CLI ヘッドレスで動かしたい**: `draw()` から `drawXxx()` 群を消す。
  `setup()` の `surface.setTitle` も不要。Minim と triggerNote の経路はそのまま動く
- **複数音色を同じ Voice で混ぜたい**: `ResynthVoice` の代わりに「複数 InstrModel を抱える
  Voice」を作って `triggerNote` で `new` する型を変える
- **ボイス上限を別の方針で管理する** (LRU でなく音量低い順を切る等): `triggerNote()` の
  `while (countNonReleasing() ...)` ループを差し替える
- **音色のクロスフェード** (instrument 切替え時に滑らかに変える): `InstrModel` を 2 つ
  抱える Voice を作り、`harmonicCount` をブレンドする

## 次のページ

- 中で何を計算しているか → [加算合成ボイス（ResynthVoice）](/pc-audio/resynth-voice/)
- JSON から InstrModel への展開 → [音色定義モデルと JSON](/pc-audio/instr-model/)
- マルチポートの仕組みだけ → [マルチポート同時受信](/pc-audio/serial-handling/)
