---
title: AudioManager
description: 音色ロード、楽器別移調と音量、金管voice、ドラム、回収処理を関数単位で解説する
sidebar:
  order: 7
---

実体: `pc_app/common/AudioManager.pde`（192行）。

## 役割

AudioManagerは独立classではなく、Processingの共有関数群です。

- data内のJSONを読み `InstrModel` 配列を作る
- `instrumentId`から金管またはドラムへ分岐する
- 金管の移調・音量・同時発音を管理する
- voice、合成ドラム、メトロノームを停止・回収する
- テスト音を作る

Minim、各配列、設定値はmainのグローバルを参照します。

## JSONのスキャン

```text
dataPath("")
  → 直下の .json だけ抽出
  → ファイル名を大文字小文字無視で昇順sort
  → loadJSONObject
  → new InstrModel(root, out.sampleRate())
```

読込に失敗したファイルもindexを詰めず、`models.add(null)`します。これにより後続ファイルの
`instrumentId`がずれません。

`modelForId()` はIDを0〜size-1へclampし、そのindexがnullなら最初の有効modelを返します。
堅牢ですが、誤ったinstrumentIdが別音色で鳴る挙動でもあります。厳密な運用にするなら
範囲外やnullをerrorにして無音へ変更します。

## 金管とドラムの判定

```java
boolean isDrumInstrument(int instrumentId){
  return instrumentId >= 4;
}
```

現行編成に合わせた境界です。5つ目の金管をID 4へ追加するとドラム扱いになるため、
編成変更時はこの条件、JSON命名、firmwareのinstrumentIdを同時に見直します。

## ドラム音の選択

```java
int drumTimbreIndex(int noteNumber){
  if (noteNumber == 36) return 0;
  if (noteNumber == 38) return 1;
  if (noteNumber == 42) return 2;
  if (noteNumber == 49) return 3;
  return 2;
}
```

未知noteはclosed hi-hatへフォールバックします。各音でnoise係数も変えます。

| note | timbre | noise scale |
|---:|---|---:|
| 36 | kick | 0.14 |
| 38 | snare | 0.45 |
| 42 | closed hi-hat | 0.42 |
| 49 | crash | 0.30 |

## ドラム音色の起動ロード

`loadDrumTimbres()`は4つの固定ファイルを`DrumTimbreData`へ変換し、
`drum_sample`があれば`AudioSample`も作ります。

```java
AudioFormat(sampleRate, 16, 1, true, true)
```

16 bit、mono、signed、big-endianのJava AudioFormatを使います。
JSON値から作ったfloat配列をMinim sampleへ渡し、bufferは512です。

## 金管の移調

楽譜の共通MIDI音域を各楽器らしいregisterへ移します。

| instrumentId | 楽器 | 半音 |
|---:|---|---:|
| 0 | trumpet | +12 |
| 1 | horn | 0 |
| 2 | trombone | -12 |
| 3 | tuba | -12 |

NOTEの`noteNumber`自体は書き換えず、PCで `effectiveMidi` を作ります。
gate=0のmatchingでも同じ移調を再適用しないと、voiceを見つけられません。

## 金管の音量係数

```text
gain = clamp(velocity/127, 0, 1)
       × partAmplitude
       × masterVolume
```

| 楽器 | 係数 |
|---|---:|
| trumpet | 0.20 |
| horn | 0.17 |
| trombone | 0.18 |
| tuba | 0.25 |

さらにvoice内部で0.9のheadroomを掛けます。`masterVolume`は初期0.55、キー操作で
0.05〜1.5まで動かせるため、1.0を超える設定ではclipを波形と聴感で確認してください。

## triggerNote

```text
instrumentId >= 4 ?
  yes → triggerDrumNote
  no  → modelForId
        → voice上限調整
        → 移調とgain
        → ResynthVoice生成
        → partId/instrumentIdx/off時刻
        → patch(out)
        → activeVoicesへ追加
```

`scheduleOffMs`は:

```java
millis() + max(40, durationMs)
```

40 ms未満を丸めるのは、短すぎる音でattack直後にreleaseするのを避けるためです。

## voice stealing

```java
while (countNonReleasing() >= MAX_POLYPHONY) {
  先頭から最初のnon-releasing voiceをnoteOff
}
```

配列順は作成順なので、古い発音を優先的にreleaseします。release中voiceは上限に数えません。
そのためCPUの厳密な最大voice数は24ではなく、releaseの重なり分だけ増えます。

hard limitが必要なら、release中も数えるか、最古を即`unpatch()`してください。現行は
音切れを滑らかにする方を優先しています。

## triggerDrumNote

音量は:

```text
0.075 × velocity/127 × masterVolume
```

録音sampleがあれば:

```text
linear amplitude
  → 20 log10(amplitude)
  → recorded gain 2.0を加味
  → AudioSample.trigger()
```

sampleがなければ合成します。合成voiceが12以上なら最古へnoteOffして配列から外し、
新しい`DrumNote`を作ります。off時刻は `max(durationMs, 500)` です。

`AudioSample`経路は`activeDrumSynths`へ入りません。Minimがsample再生を管理します。
`stopAll()`でsample自体を明示停止していないため、すでにtrigger済みの録音ドラムは
短い残音が続く可能性があります。

## releaseMatching

金管voiceのうち:

```text
!releasing
partId一致
midiNote一致
```

をすべてreleaseします。同じpartと音高が重なっている場合は全件が対象です。
instrumentIdは比較しません。

## updateVoiceLifecycle

毎drawで次の順に処理します。

1. off時刻を過ぎた金管へ`noteOff()`
2. `done`金管を`unpatch(out)`してremove
3. 合成ドラムのoff時刻で`noteOff()`
4. release開始から500 ms後にenvelopeをunpatchしてremove

音声threadが`done`を書き、drawが読むため、厳密な可視性を要求するなら`done`も
`volatile`にする余地があります。現行は`releasing`だけがvolatileです。

## stopとテスト

`stopAll()`は金管、合成ドラム、メトロノームを停止・clearします。
テスト和音はMIDI 60/64/67をpart 0x02〜0x04、instrument 0〜2へ900 msで送ります。
数字キー0〜3は指定金管でMIDI 60を1秒鳴らします。

## 変更時の確認

- 金管追加: `isDrumInstrument`境界、移調、係数、JSON順
- ドラム追加: note mapping、file配列、noise scale
- voice上限: non-releasing基準か全voice基準か
- volume: 二重に掛かる箇所とclip
- sample停止: `stopAll`に録音sampleの停止が必要か
- gate=0: 送信noteと移調後noteの対応

次は [ドラムエンジン](/pc-audio/drum-engine/) と
[ResynthVoice](/pc-audio/resynth-voice/) を参照してください。
