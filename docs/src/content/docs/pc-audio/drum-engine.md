---
title: DrumEngine
description: ドラムJSON、録音再生、倍音＋Noise＋ADSRフォールバック、MetroClickの数式とライフサイクル
sidebar:
  order: 9
---

実体: `pc_app/common/DrumEngine.pde`（167行）。

## 収録する機能

| class | 役割 |
|---|---|
| `DrumTimbreData` | ドラムJSONを配列へ読む |
| `DrumNote` | 倍音、Noise、ADSRで合成 |
| `RecordedDrumNote` | `AudioSample`をInstrumentとして鳴らす補助 |
| `ActiveDrumSynth` | 合成ドラムのoff/release時刻 |
| `MetroClick` | ゲーム用880 HzクリックUGen |

実際の分岐と配列管理は [AudioManager](/pc-audio/audio-manager/) にあります。

## 固定値

```java
KICK_DRUM      = 36
SNARE_DRUM     = 38
CLOSED_HI_HAT  = 42
CRASH_CYMBAL   = 49

MAX_DRUM_HARMONICS = 12
MAX_DRUM_POLYPHONY = 12
DRUM_AMPLITUDE = 0.075
RECORDED_DRUM_GAIN = 2.0
```

JSONファイルは `4_kick`、`5_snare`、`6_hi_hat`、`7_crash` の4つです。
ここでの4〜7はdataの並びで、wire上の`instrumentId`はドラム全体を4として扱います。
個別音色はMIDI noteで選びます。

## DrumTimbreData

constructorは次を読みます。

- `name`
- `fundamental_hz`
- `envelope.attack_sec`
- `decay_sec`
- `sustain_level`
- `release_sec`
- `noise.level`
- `harmonics[].ratio`
- `harmonics[].amp`
- 任意の `drum_sample.values`
- 任意の `drum_sample.sample_rate`

倍音は最大12個です。振幅の総和を求めて:

```text
g'_k = g_k / Σ g_i
```

と正規化します。総和が0以下なら例外にし、無音またはNaNの音色を起動時に検出します。

`drum_sample`が無ければ配列はnullのままです。AudioManagerはその場合だけ合成経路を使います。

## 録音再生

`createRecordedDrumSample()`はfloat sample配列からMinimの`AudioSample`を作ります。

音量変換は:

```text
dB = 20 log10(clamp(
       0.075 × velocity/127 × masterVolume × 2.0,
       0.001,
       1.0
     ))
```

0をlogへ渡さないため下限0.001、clipしないため上限1.0です。`trigger()`は
同じsampleを頭から再生します。

`RecordedDrumNote` classも同様の処理を持ちますが、現行AudioManagerでは直接
`AudioSample.trigger()`を使っており、このwrapperは主要経路ではありません。

## 合成ドラム

録音sampleが無い場合、`DrumNote`を作ります。

### 倍音部

各JSON倍音に1つのsine oscillatorを作ります。

```text
frequency_k = fundamentalHz × ratio_k
amplitude_k = noteAmplitude × normalizedGain_k
```

すべてを`Summer`へpatchします。金管voiceのようなサンプルごとの位相配列ではなく、
Minimの`Oscil`が生成を担当します。

### noise部

```text
noiseAmplitude =
  noteAmplitude
  × timbre.noiseLevel
  × drumNoiseScale(noteNumber)
```

0.001を超える場合だけwhite `Noise`を作り、同じ`Summer`へpatchします。
kickを0.14、snareを0.45にすることで、kickの周期成分を残し、snareの広帯域成分を
強くしています。

### 包絡

```java
envelope = new ADSR(
  1.0,
  attackSec,
  decaySec,
  sustainLevel,
  releaseSec
);
```

`Summer → ADSR → out` の順です。`noteOn()`でenvelopeをoutへpatchし、
`noteOff()`で`unpatchAfterRelease(out)`を設定してからreleaseを開始します。

## ActiveDrumSynth

次の3値を持ちます。

- `offAtMs`: noteOff予定
- `released`: release開始済みか
- `releaseMs`: 開始時刻

AudioManagerは最低500 ms後にnoteOffし、さらに500 ms待って
`envelope.unpatch(out)`します。JSONの`releaseSec`が500 msを超える音色では
余韻途中で切る可能性があります。長いcrashを合成するなら、固定500 msを
`releaseSec`に基づく値へ変更します。

## MetroClick

ゲーム用クリックは外部sampleではなく、小さいUGenです。

```text
frequency = 880 Hz
duration  = 0.05 s
attack    = 0.005 s
output    = sin(phase) × envelope × gain × 0.25
```

包絡は区分線形です。

```text
e(t) = t / 0.005                         0 <= t < 0.005
e(t) = 1 - (t - 0.005)/(0.05 - 0.005)   0.005 <= t < 0.05
e(t) = 0                                 t >= 0.05
```

位相更新:

```text
phase[n+1] = phase[n] + 2π × 880 / sampleRate
```

0.05秒で`done=true`になります。mainの`updateMetronome()`が次フレームにunpatchして
`metroClicks`から除去します。

クリックの`gain`にはゲームguide強度とmaster volumeが掛かります。さらに0.25を掛け、
音楽より前に出すぎないようにしています。

## 金管合成との違い

| 項目 | 金管 | ドラム |
|---|---|---|
| 生成 | 自作UGenでサンプル単位 | AudioSample優先、Minim UGen fallback |
| 倍音 | 実測時間包絡あり | 静的ratio/gain |
| noise | FFT整形noise table | white Noise |
| 持続 | loop区間 | ワンショット |
| note選択 | MIDI pitch | noteがtimbre ID |
| release | JSON release | sample自然終了または合成release |

## 調整ポイント

- 音が大きい: `DRUM_AMPLITUDE`、`RECORDED_DRUM_GAIN`
- snareが白色雑音すぎる: `drumNoiseScale(38)`
- kickに芯がない: JSONの`fundamental_hz`と低次`harmonics`
- crashが途中で切れる: lifecycleの500 ms固定
- CPU負荷: `MAX_DRUM_HARMONICS`と合成上限
- sampleが使われない: JSONの`drum_sample.values`が空でないか

音色JSONの共通項目は [InstrModel](/pc-audio/instr-model/)、
解析の詳細は [音声解析](/pc-audio/analyzer-overview/) を参照してください。
