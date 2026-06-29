---
title: NOTE・UI受信から音と画面まで
description: SerialCore、packetQueue、AudioManager、画面判定、Minimの実行順をスレッド境界込みで追う
sidebar:
  order: 2
---

## 全体フロー

```text
UNO R4 node_02〜06
  │ USB Serial / 115200 bps / 20 B
  ▼
Serial callback
  PortConnごとに 52 4F を探索
  残り18 Bを集める
  packetQueue.offer(copy)
  │
  ▼
draw() / 90 fps
  drainPackets()
  ├─ type=3 NOTE → triggerNote()
  │                   ├─ instrumentId 0〜3 → ResynthVoice.patch(out)
  │                   └─ instrumentId >=4 → drum sample / synth
  └─ type=4 UI   → ui状態更新 → determineScreen()
  │
  ├─ updateVoiceLifecycle()
  ├─ updateMetronome()
  └─ currentScreenに対応する画面を描画
  │
  ▼
Minim audio / 44.1 kHz / 512 samples
  ├─ ResynthVoice.uGenerate()
  ├─ DrumNote / AudioSample
  └─ MetroClick.uGenerate()
```

## 1. Serialで20 Bを確定する

`SerialCore.serialEvent()` はポートごとに `PortConn` を持ちます。複数ノードを
同じPCへ接続しても、magic探索位置と受信indexは混ざりません。

```java
class PortConn {
  byte[] rxBuf = new byte[PACKET_SIZE];
  int rxIdx;
  boolean inFrame;
}
```

先頭の `0x52, 0x4F` を見つけたら18 Bを追加し、配列をコピーしてqueueへ積みます。
元の`rxBuf`を直接渡すと次の受信で内容が上書きされるため、copyが必要です。

Serial callbackはpacketの意味を解釈しません。この境界により、Serialスレッドは
`activeVoices`、画面状態、Minimへ触れません。

## 2. drawでパケットを振り分ける

```java
void drainPackets(){
  byte[] pkt;
  while ((pkt = packetQueue.poll()) != null) handlePacket(pkt);
}
```

1フレームに到着分をすべて処理します。1件だけ処理すると、複数ポートや同時NOTEで
queueが蓄積し、その蓄積が音の遅延になります。

`packetType()` は20 B以上とversion `0x01`を確認し、offset 3を返します。

### UI type=4

UIは最初に処理し、以下を更新します。

- `uiState`
- `uiMode`
- `uiNavCursor`
- `uiTargetBpm`
- `uiScore`
- `uiPartId`
- `uiBpmQ8`
- `lastUiAtMs`

UIを受けると役割は `ROLE_MAIN_UI` になります。NOTEのように発音処理へは進みません。

### NOTE type=3

NOTE以外の未知typeは無視します。NOTEから `NoteEvent` を作り、初回packetでPCの役割を判定します。

```text
partId = 0x02 → ROLE_MAIN_UI
partId != 0x02 → ROLE_ANALYZER
```

`gate=1` はログ、`triggerNote()`、直近イベント更新へ進みます。`gate=0` は金管だけを
`releaseMatching()`でreleaseします。

## 3. 楽器ごとの発音分岐

`instrumentId >= 4` はドラム、それ以外は金管です。

### 金管

```text
instrumentId
  → modelForId()
  → brassOctaveShift()
  → brassPartAmplitude()
  → new ResynthVoice()
  → scheduledOffMs
  → patch(out)
  → activeVoices
```

音量は次式です。

```text
gain = clamp(velocity / 127)
       × brassPartAmplitude(instrumentId)
       × masterVolume
```

楽器別係数は trumpet 0.20、horn 0.17、trombone 0.18、tuba 0.25です。
移調は trumpet +12、horn 0、trombone -12、tuba -12半音です。

非release voiceが24以上なら、先頭から最初のnon-releasing voiceへ`noteOff()`をかけて
空きを作ります。即座に配列から消さずreleaseを鳴らすため、短時間は配列要素数が
24を超える場合があります。上限は「non-releasing voice数」です。

### ドラム

MIDI noteを音色indexへ変換します。

| note | 音 |
|---:|---|
| 36 | kick |
| 38 | snare |
| 42 | closed hi-hat |
| 49 | crash |
| その他 | hi-hatへフォールバック |

録音sampleがあればgainをdBへ変換して `AudioSample.trigger()` します。
無ければ `DrumNote` を作り、最大12の合成voiceを管理します。

## 4. voiceの時間管理

`updateVoiceLifecycle()` は毎drawで呼ばれます。

```text
now >= scheduledOffMs
  → noteOff()
  → audio threadがrelease曲線を生成
  → done=true
  → drawがunpatchして配列から除去
```

`durationMs` は最低40 msに丸めます。短すぎるNOTEでattack前にreleaseして
ほぼ無音になるのを防ぎます。

ドラム合成は `max(durationMs, 500)` 後にnoteOffし、さらに500 ms後に
envelopeをunpatchして回収します。

## 5. audio threadでの生成

金管の各サンプルは概略として次式です。

```text
s(t) = gain × a(t) × 0.9
       × Σ A_k E_k(t) sin(phi_k(t))
       + shapedNoise(t)
```

周波数は:

```text
f_k(t) = targetF0 × ratio_k × sqrt(1 + B n_k^2) × vibrato(t)
```

詳細は [ResynthVoice](/pc-audio/resynth-voice/) と
[加算合成の数式](/deep-dive/additive-synthesis/) に分離しています。

Minimは512 samples単位で出力します。voiceの`done`判定後、次のdrawでunpatchされるまで
無音sampleを返すため、回収の瞬間に古い値を出しません。

## 6. UIから画面を決める

`determineScreen()` は毎フレーム、受信済みデータだけで画面を決めます。

| 条件 | 画面 |
|---|---|
| ポート未接続 | Port Select |
| role=Analyzer | Analyzer |
| role=Main、state=Menu | Menu |
| role=Main、state=Conducting、mode=0 | Free Play |
| role=Main、state=Conducting、mode=1 | Game Play |
| role=Main、state=Result | Result |
| その他 | Waiting |

画面遷移時の副作用は `onScreenChange()` に集約しています。

- Game Playへ入る: ローカルゲーム開始時刻と拍indexを初期化
- Menu/Waitingへ入る: score、メトロノーム、ゲーム時刻を初期化
- UIが2秒途絶える: master resetと判定、全音停止、Waitingへ戻す

## 7. ゲームのメトロノーム

PCはUI packetの `targetBpm` とGame Playへ入ったローカル時刻から拍番号を求めます。

```text
intervalMs = 60000 / targetBpm
beatNum    = floor((millis - gameStartMs) / intervalMs)
```

0〜15拍は最大音量、16〜31拍で線形に小さくし、32拍以降は鳴らしません。
56拍を超えたクリックも作りません。クリックは880 Hz、50 msの`MetroClick` UGenです。

このメトロノームはガイド音であり、NOTEの同期時計ではありません。マイコンの
ゲーム拍数とPCローカル時刻に小さな差が出る可能性はあります。

## 典型タイムライン

| 相対時刻 | 処理 |
|---:|---|
| 0 ms | 楽器ノードがNOTE 20 BをSerialへ書く |
| 約1〜2 ms | Serial callbackが20 Bをqueueへ積む |
| 0〜11.1 ms後 | 次のdrawがNOTEを復号 |
| 同draw | voice生成またはsample trigger |
| 次のaudio block | スピーカー出力へ反映 |
| `durationMs`後 | drawが金管voiceをrelease |
| `releaseSec`後 | audioがdone、drawがunpatch |

これはアプリ内部の概算です。OS、USB、Audioデバイスを含む実遅延は
ループバック録音やオシロスコープで測定してください。

## 異常系

| 症状 | 現行動作 |
|---|---|
| NOTE欠落 | その音だけ鳴らない。次のNOTEから復帰 |
| UI欠落が2秒未満 | 最後の画面状態を維持 |
| UI欠落が2秒以上 | 全音停止、Waiting、reset表示 |
| unknown type | 無視 |
| JSON読込失敗 | null modelを保持し、別の有効modelへフォールバック |
| 金管voice上限 | 古いnon-releasing voiceをrelease |
| drum synth上限 | 最古をnoteOffして配列から外す |
| Serialの1 Bずれ | 次のmagicで再同期 |

次は [メインスケッチ](/pc-audio/resynth-main/) と
[SerialCore](/pc-audio/serial-handling/) で各実装を分けて読みます。
