---
title: orchestra_resynth.pdeの全体構造
description: productionメインスケッチ678行の責務、画面判定、ゲームメトロノーム、入力、終了処理を読む
sidebar:
  order: 3
---

実体: `pc_app/production/orchestra_resynth/orchestra_resynth.pde`（678行）。

このファイルは共有モジュールを組み立てるproduction固有のエントリーポイントです。
protocol、Serial、audioの詳細実装は `pc_app/common/` に分割されています。

## タブ構成

Processingは同じディレクトリの`.pde`を一つのスケッチとしてコンパイルします。

```text
orchestra_resynth/
├─ orchestra_resynth.pde  production固有のmainと画面
├─ OrcProtocol.pde        → ../../common/OrcProtocol.pde
├─ SerialCore.pde         → ../../common/SerialCore.pde
├─ AudioManager.pde       → ../../common/AudioManager.pde
├─ InstrModel.pde         → ../../common/InstrModel.pde
├─ SynthVoice.pde         → ../../common/SynthVoice.pde
├─ DrumEngine.pde         → ../../common/DrumEngine.pde
├─ SharedUI.pde           → ../../common/SharedUI.pde
├─ OrcLogger.pde          → ../../common/OrcLogger.pde
└─ data/
   ├─ 0_trumpets...
   ├─ 1_horns...
   ├─ 2_trombones...
   ├─ 3_tuba...
   └─ 4〜7 drum...
```

symlinkを通常ファイルのコピーへ置き換えると、common側の修正が反映されなくなります。

## mainが所有する状態

共有タブが参照するグローバル状態をmainで宣言します。

| 分類 | 主な値 |
|---|---|
| Audio | `Minim minim`、`AudioOutput out` |
| 金管音色 | `instrumentFiles`、`models`、`modelLabels` |
| 金管voice | `activeVoices`、`MAX_POLYPHONY=24` |
| ドラム | `drumTimbres`、`recordedDrumSamples`、`activeDrumSynths` |
| メトロノーム | `metroClicks`、`gameStartMs`、`lastMetroBeat` |
| Serial | port配列、2つのmap、`packetQueue` |
| UI受信 | state、mode、cursor、target、score、bpm、partId |
| 役割 | `nodeRole`、`currentScreen`、`prevScreen` |
| 表示 | 受信数、直近NOTE、font |

共有タブ冒頭の依存一覧と、この宣言は一致させる必要があります。

## 起動

```java
void settings(){
  size(1000, 560);
}

void setup(){
  frameRate(90);
  uiFont = loadJapaneseFont(13);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 512, 44100);
  rescanInstruments();
  loadDrumTimbres();
  refreshPorts();
}
```

起動時にはポートを列挙するだけで、自動では開きません。Port Select画面でユーザーが
必要なUSBを選びます。

`rescanInstruments()` はdata直下の全JSONを名前順で読みます。ドラム専用JSONも
`models`には入りますが、`instrumentId >= 4` は`AudioManager`が先にドラム経路へ
分岐するため、`ResynthVoice`には渡りません。

## パケット処理

mainの `handlePacket()` がアプリ固有の意味を付けます。

### UI

type=4なら `UiEvent` を作り、画面用状態を更新してreturnします。初回UIで
`ROLE_MAIN_UI`を確定し、titleも更新します。

### NOTE

type=3以外は無視します。最初のNOTEのpartIdで役割を推測し、gateに応じて
`triggerNote()`または`releaseMatching()`を呼びます。

ドラムgate=0は無視します。金管のreleaseでは、送信NOTEに楽器別のオクターブ移調を
加えた後のMIDI番号で既存voiceを検索します。

## 画面判定

`determineScreen()` は現在値から純粋に画面IDを返します。

```java
if (openByName.isEmpty()) return SCR_PORT_SELECT;
if (nodeRole == ROLE_ANALYZER) return SCR_ANALYZER;

if (nodeRole == ROLE_MAIN_UI){
  switch (uiState){
    case ST_MENU:       return SCR_MENU;
    case ST_CONDUCTING: return uiMode == 1 ? SCR_GAME_PLAY : SCR_FREE_PLAY;
    case ST_RESULT:     return SCR_RESULT;
    default:            return SCR_WAITING;
  }
}
return SCR_WAITING;
```

画面をpacket内に直接持たせず、マイコンと同じstate/modeから導出します。

## 画面遷移の副作用

`onScreenChange(from, to)` は画面が変わったフレームだけ呼ばれます。

- Game Playへ入る: `gameStartMs=millis()`、メトロ拍を-1
- Menuへ入る: ゲーム時刻、score、クリックを初期化
- Waitingへ入る: Menuと同様に音声ガイド状態を初期化

毎フレーム初期化するとゲーム経過時間が0へ戻り続けるため、
`currentScreen != prevScreen` の条件が重要です。

## drawの順序

```text
1. drainPackets
2. UI 2秒タイムアウト検査
3. updateVoiceLifecycle
4. updateMetronome
5. determineScreen
6. 画面変更ならonScreenChange
7. 画面別draw関数
```

UIタイムアウトでは:

```text
uiState = Idle
uiScore = 0xFF
game clockを初期化
stopAll()
masterResetDetected = true
lastUiAtMs = 0
```

`lastUiAtMs=0`にして同じerrorを毎フレーム記録しないようにしています。

## 7画面

| ID | 関数 | 内容 |
|---|---|---|
| Port Select | `drawPortSelectScreen()` | USB選択、filter、scroll |
| Waiting | `drawWaitingScreen()` | Idle、Calibrating、Fallback、reset |
| Menu | `drawMenuScreen()` | 自由演奏/ゲームとcursor |
| Free Play | `drawFreePlayScreen()` | BPM、波形、5ノードの受信 |
| Game Play | `drawGamePlayScreen()` | target、current BPM、guide、score |
| Result | `drawResultScreen()` | 100点満点、色分け |
| Analyzer | `drawAnalyzerScreen()` | 波形と直近NOTE |

Menuのクリックは見た目上hoverを描くだけです。選択と決定は指揮棒側で行い、
PCは`uiNavCursor`とstateを表示します。

## ゲームガイド

`gameGuideIntensity(beatCount)` はfirmwareと同じ区分です。

```text
beat < 16       : 1.0
16 <= beat < 32 : 1 - (beat - 16) / 16
32 <= beat      : 0.0
```

`updateMetronome()` はGame Playかつtarget BPMが正のときだけ動きます。経過時間から
beatを求め、前回より進んだときだけ `MetroClick` をpatchします。56拍以降は作りません。

フレーム落ちでbeatが2つ以上進んだ場合、抜けたすべてのクリックを後追い連打せず、
現在beatに1回だけ鳴らします。ガイド音なので遅れを蓄積しない方を選んでいます。

## 画面別の重要表示

Free Playは `uiBpmQ8 / 8`、24 voice中の発音数、5 partの受信を表示します。
Game Playの進捗はPCローカルtarget時計であり、マイコンから直接beat数を受けている
わけではありません。Resultは `score=0xFF` を未確定として `---` にします。

`drawHelpPanel()` は全画面共通で、part 0x02〜0x06の直近2秒受信、role、接続port数、
UI同期遅延を表示します。

## ポート画面

`drawPortListAt()` は毎フレームfilter結果を更新します。

- `usbOnly=true`: usbmodem、usbserial、ttyUSB、ttyACM、COMだけ
- 開いているportはfilterに関係なく残す
- mouse wheelは1行40 px単位
- clip領域外の行は描画しない
- map内に存在すればOPENと受信数を表示

UIの行座標をグローバルに保持し、`mousePressed()`は同じ座標からportを開閉します。

## キー

| キー | 動作 |
|---|---|
| `r` | 全port close、再列挙、role/state/scoreをreset |
| `i` | JSON再読込 |
| `t` | 金管0/1/2でC-E-Gテスト |
| `a` | ADSR4値と実測包絡を切替 |
| `0`〜`3` | 指定金管でCを試聴 |
| `+` / `-` | master volumeを0.05刻み、0.05〜1.5 |
| Space | 全音停止 |
| `f` | USBのみ/全port表示を切替 |

初期値 `useSimpleADSR=true` なので、起動直後はADSR4値です。`a`で実測包絡へ切り替えます。

## 終了

```java
void dispose(){
  closeAllPorts();
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}
```

Serialを先に閉じ、callbackの流入を止めてからaudioを閉じます。強制終了時は
`dispose()`が完走しない可能性があり、portがbusyなら別ProcessingやSerial Monitorを
閉じてから再実行します。

## 次に読む

- 共有処理の中心: [AudioManager](/pc-audio/audio-manager/)
- 画面部品: [SharedUI](/pc-audio/shared-ui/)
- ログ: [OrcLogger](/pc-audio/orc-logger/)
