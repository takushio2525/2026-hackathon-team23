---
title: 加算合成ボイス（ResynthVoice）
description: 1 音ぶんの UGen が倍音・非調和性・揺れ・包絡を組み合わせて音を作る数学と実装
sidebar:
  order: 4
---

実体: `pc_app/common/SynthVoice.pde`（126行、productionスケッチから共有タブとして参照）。

このページは **「1 音をどう作っているか」** の解剖。スケッチ全体構造は
[orchestra_resynth.pde の全体構造](/pc-audio/resynth-main/) を先に読むこと。

:::tip[読み方のヒント]
このクラスは Minim の `UGen`（unit generator）を継承していて、Audio スレッドが
`uGenerate(float[] channels)` を 1 サンプルごとに呼ぶ。**1 行 1 行が 1/44100 秒に 1 回**
実行される。重い処理は書けない。
:::

## 出力する音の数学的な姿

時刻 `t` における出力サンプル `s(t)` は、おおむね次で表せる。

```
s(t) = a(t) · gain · 0.9 · [ Σ_{k=0..N-1}  amp_k · env_k(t) · sin(φ_k(t))                ]
                          [        × (1 / Σ amp)         ※ harmNorm                       ]
                          [   + noise_table[noisePos] · noiseEnv(t) · noiseLevel · relMul  ]
                          [   × (1 - tremDepth/2 + (tremDepth/2)·sin(2π·tremRate·t))      ]
```

各部の意味:

| 記号 | 意味 | 出所 |
|---|---|---|
| `a(t)` | 全体の振幅エンベロープ（0..1） | `envelope.values[]` または ADSR 4 値 |
| `gain` | velocity × masterVolume の合算 | `triggerNote` 時に算出 |
| `amp_k` | 第 k 倍音の静的振幅 | JSON `harmonics[k].amp` |
| `env_k(t)` | 第 k 倍音の時間エンベロープ | JSON `harmonics[k].env` |
| `φ_k(t)` | 第 k 倍音の位相 | `phase[k] += 2π·f_k/sr` で逐次更新 |
| `f_k` | 第 k 倍音の瞬時周波数 | `targetF0 · ratio_k · √(1+B·n_k²) · pitchMul` |
| `B` | 非調和性係数 | JSON `inharmonicity_b` |
| `pitchMul` | ビブラート由来のピッチ倍率 | `2^(Δcent·sin(...)/1200)` |
| `noise_table` | スペクトル整形された白色ノイズ | `InstrModel.makeShapedNoise()` で生成 |
| `relMul` | release 中のノイズ減衰係数 | `releasing` 状態で 1 → 0 線形 |

## クラスのフィールド一覧

```java
class ResynthVoice extends UGen {
  InstrModel m;                   // 音色定義（読み取り専用、複数 Voice で共有）
  int   midiNote;                 // 鳴らす MIDI ノート
  float targetF0;                 // 上から計算した基音 Hz (= 440 · 2^((midi-69)/12))
  float gain;                     // 0..1.5 (velocity * masterVolume)
  boolean simpleADSR;             // false=実エンベロープ / true=ADSR 4 値

  // 自動noteOffと送信元の追跡
  int   partId = -1;              // どの声部か
  int   instrumentIdx = -1;       // どの音色か
  int   scheduledOffMs = Integer.MAX_VALUE;  // millis() でこれを超えたら noteOff

  float[] phase;                  // 倍音ごとの位相 [rad]
  double  noisePos;               // ノイズテーブルの読み出し位置
  float   tSec = 0;               // 発音開始からの経過秒（audio thread が更新）
  float   vibPhase = 0;           // ビブラート LFO の位相
  float   tremPhase = 0;          // トレモロ LFO の位相

  boolean done = false;           // true なら次から無音 + draw() で回収
  volatile boolean releasing = false;
  float releaseStartT = 0;        // release 開始時の tSec
  float releaseStartLevel = 0;    // release 開始時の振幅 (release カーブ起点)
  float releaseHoldWarpT = 0;     // release 中の倍音 env 参照位置 (固定)

  float origDur, headT, loopLen;  // ループ再生用の計算済み定数
}
```

`m` は **複数 Voice で共有される** ことに注意。`m` のフィールドを書き換えないこと
（ノイズテーブル `m.noiseTable` を Voice 内でいじったらバグの温床になる）。

## コンストラクタでやること

```java
ResynthVoice(InstrModel model, int midi, float velocity, boolean simple){
  this.m = model;
  this.midiNote = midi;
  this.targetF0 = 440f * pow(2, (midi-69)/12.0f);    // MIDI → Hz
  this.gain = constrain(velocity, 0, 1.5f);
  this.simpleADSR = simple;
  phase = new float[m.N];
  for (int i=0;i<m.N;i++) phase[i] = m.harmPhase[i]; // 解析した位相を初期値に
  origDur = m.origDurSec();
  headT   = m.loopStartSec;
  loopLen = max(m.loopEndSec - m.loopStartSec, 1e-3f);
}
```

要点:

- `targetF0 = 440 · 2^((midi-69)/12)` は MIDI 標準（A4 = 69 = 440 Hz）
- 位相を 0 ではなく **解析時の位相** で初期化することで、複数声部が重なったときの
  位相干渉を「実音と同じ」に近づけている
- `loopLen` は `loopEndSec - loopStartSec`。0 やマイナスにならないよう `1e-3` でクランプ

## uGenerate() — Audio スレッドが呼ぶ本体

```java
protected void uGenerate(float[] channels){
  float sr = sampleRate();
  if (done){ for (int i=0;i<channels.length;i++) channels[i]=0; return; }

  // ① 振幅
  float a = ampAt(tSec);

  // ② ビブラート → ピッチ倍率
  float pitchMul = 1.0f;
  if (m.vibDepthCents > 0.01f && m.vibRateHz > 0.001f){
    float vg = m.vibOnsetSec > 0.001f ? min(1, tSec/m.vibOnsetSec) : 1;
    pitchMul = pow(2, (m.vibDepthCents*0.5f*vg*sin(vibPhase))/1200.0f);
    vibPhase += TWO_PI * m.vibRateHz / sr;
    if (vibPhase >= TWO_PI) vibPhase -= TWO_PI;
  }

  // ③ 倍音加算
  float s = 0;
  for (int k=0;k<m.N;k++){
    float amp = m.harmAmp[k]; if (amp<=0) continue;
    int   n1  = m.harmN[k];
    float f   = targetF0 * m.harmRatio[k] * sqrt(1 + m.inharmB*n1*n1) * pitchMul;
    if (f >= sr*0.5f) continue;                  // ナイキスト超は飛ばす（エイリアス防止）
    phase[k] += TWO_PI * f / sr;
    if (phase[k] >= TWO_PI) phase[k] -= TWO_PI;
    s += amp * harmEnvAt(k, tSec) * sin(phase[k]);
  }
  s *= m.harmNorm;                                // 倍音総和の正規化

  // ④ ノイズ加算
  if (m.noiseLevel > 0 && m.noiseTable.length > 1){
    float relMul = releasing ? max(0, 1-(tSec-releaseStartT)/relSec()) : 1;
    float ne = noiseEnvAt(tSec) * m.noiseLevel * relMul;
    s += m.noiseTable[(int)noisePos] * ne;
    noisePos += 1;
    if (noisePos >= m.noiseTable.length) noisePos -= m.noiseTable.length;
  }

  // ⑤ トレモロ
  if (m.tremDepth > 0.001f && m.tremRateHz > 0.001f){
    s *= 1.0f - m.tremDepth*0.5f + m.tremDepth*0.5f*sin(tremPhase);
    tremPhase += TWO_PI * m.tremRateHz / sr;
    if (tremPhase >= TWO_PI) tremPhase -= TWO_PI;
  }

  // ⑥ 全体振幅・ゲイン・headroom
  s *= a * gain * 0.9f;

  // ⑦ 各チャンネルに同じ値を書く（モノラル→ステレオ）
  for (int i=0;i<channels.length;i++) channels[i] = s;

  // ⑧ 時間と終了判定を進める
  tSec += 1.0f/sr;
  if (releasing && (tSec - releaseStartT) >= relSec()) done = true;
  else if (!done && a <= 1e-4f && tSec > 0.15f) done = true;  // 減衰音の自然死
}
```

各段の解説:

### ① 振幅エンベロープ `ampAt(t)`

```java
float ampAt(float t){
  if (!releasing) return sustainBodyLevel(t);
  float u = (t - releaseStartT) / relSec();
  if (u >= 1) return 0;
  float k = 1 - u;
  return releaseStartLevel * k * k;          // 二次のフェード（耳に自然）
}
```

`releasing = false` のときは本体エンベロープ（次節）、`true` のときは
**release 開始時の振幅から (1-u)² で 0 へ** 落ちる。線形ではなく二次にしているのは、
線形だと急に切れた印象になるため。

### `sustainBodyLevel(t)` — 持続中の振幅

```java
float sustainBodyLevel(float t){
  if (simpleADSR){
    float a=m.attackSec, d=m.decaySec, s=m.sustainLevel;
    if (t < a) return t/max(a,1e-4f);                 // attack: 0→1 線形
    if (!m.sustaining){                                // 減衰音 (sustaining=false)
      if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, 0.02f, u); }
      return 0.02f;
    }
    if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, s, u); }
    return s;                                          // sustain 一定
  }
  return sampleCurve(m.envValues, m.envRate, warpBody(t));
}
```

- **`simpleADSR = true`**（productionのデフォルト）: ADSR 4 値だけで動かす簡易モード
- **`simpleADSR = false`**（キー `a` で切替）: JSON の `envelope.values[]` を時間軸で
  サンプリングし、倍音包絡・noise・ビブラート・トレモロも有効にする

### `warpBody(t)` — 持続音のループ参照

```java
float warpBody(float t){
  if (!m.sustaining) return min(t, origDur);
  if (t < headT) return t;
  float u = (t - headT) % loopLen;
  return m.loopStartSec + u;
}
```

- **減衰音 (`sustaining=false`)**: 単純に `min(t, origDur)`。元の長さで切る
- **持続音 (`sustaining=true`)**: `headT` まではそのまま、それ以降は
  `[loopStartSec, loopEndSec]` をループ参照

この `warpBody(t)` の戻り値が **`envValues[]` のどこを読むか** を決める。
要求された durationMs が原音より長いとき、ループ区間をぐるぐる回して音を伸ばす。

### ② ビブラート — ピッチ揺れ

```java
pitchMul = pow(2, (m.vibDepthCents * 0.5f * vg * sin(vibPhase)) / 1200.0f);
```

- `vibDepthCents` は **全幅セント**（解析側が出す値）
- 半振幅は `vibDepthCents · 0.5`
- セント → 比率は `2^(cents/1200)`
- `vg = min(1, tSec/vibOnsetSec)` で立ち上がりにフェード（音の頭でいきなり揺らさない）

LFO 位相 `vibPhase` は **サンプルごとに `2π·rate/sr` 進める**。`fmod` ではなく `if (>= TWO_PI) -= TWO_PI`
で巻き戻すのは、`fmod` より速いから。

### ③ 倍音加算 — このスケッチの心臓部

```java
float f = targetF0 * m.harmRatio[k] * sqrt(1 + m.inharmB * n1 * n1) * pitchMul;
```

**非調和性** `f_n = n · f_0 · √(1 + B · n²)` は弦楽器の高次倍音に必須。`B=0` で完全調和、
ピアノは `B ≈ 0.0001〜0.0005` 程度。これを入れないとピアノが「電子ピアノ的」に聞こえる。

`m.harmRatio[k]` は解析時に放物線補間で求めた **実周波数 ÷ f0**。整数からわずかにずれる
（典型 `2.003`, `2.998` 等）。**整数 n でなく実測 ratio を使う** のがリアル感の決め手。

`f >= sr*0.5f` (ナイキスト超) は **スキップ**。エイリアシングを避けるための定石。

### ④ スペクトル整形ノイズ

```java
float relMul = releasing ? max(0, 1-(tSec-releaseStartT)/relSec()) : 1;
float ne = noiseEnvAt(tSec) * m.noiseLevel * relMul;
s += m.noiseTable[(int)noisePos] * ne;
```

`m.noiseTable` は **InstrModel が一度だけ生成した固定バッファ**（16384 サンプル）。
FFT で帯域ゲインを掛けて作る（[InstrModel ページ](/pc-audio/instr-model/) 参照）。

`noisePos` は単調に進めて、テーブルの長さで巻き戻す（リングバッファ）。
**位相のずれが Voice 間で違う** ように初期値はそのまま使う（同期させない）。

### ⑤ トレモロ — 振幅揺れ

```java
s *= 1.0f - m.tremDepth * 0.5f + m.tremDepth * 0.5f * sin(tremPhase);
```

これは `s · (1 + tremDepth/2 · (sin - 1))` を展開した形。`tremDepth=1` のとき
振幅は `0..1` の往復、`tremDepth=0` で揺れなし。

### ⑥ ヘッドルーム `*0.9f`

倍音総和を `harmNorm = 1/Σamp` で正規化しているが、それでも瞬間ピークが 1.0 を超える
ことがあるので `0.9` で更に余裕を持たせている。クリッピング防止。

### ⑦ ステレオ書き出し

```java
for (int i=0;i<channels.length;i++) channels[i] = s;
```

モノラル合成 → 全チャンネルに同値。**パンニングを入れたい** ときはここで partId に
応じて `channels[0]` と `channels[1]` のゲインを変える。

### ⑧ 終了判定

- `releasing && (tSec - releaseStartT) >= relSec()` → release 完了
- `!done && a <= 1e-4f && tSec > 0.15f` → 減衰音が自然消滅（実エンベロープが
  ほぼ 0 に達した）。`tSec > 0.15f` の条件は **attack の頭で誤判定しない** ため

## noteOff() の流れ

```java
void noteOff(){
  if (releasing) return;
  releaseStartLevel = sustainBodyLevel(tSec);   // 今の振幅を起点に記録
  releaseHoldWarpT  = warpBody(tSec);           // 倍音 env の参照位置を固定
  releaseStartT     = tSec;
  releasing = true;
}
```

`releaseHoldWarpT` を固定するのは、release 中に `warpBody(t)` のループが進んで音色が
変わるのを防ぐため。release は **release 開始時点の音色のまま** フェードする。

## 倍音ごとの時間エンベロープ `harmEnvAt(k, t)`

```java
float harmEnvAt(int k, float t){
  float[] he = m.harmEnv[k];
  float rate = (he.length-1)/max(origDur, 1e-3f);
  float warpT = releasing ? releaseHoldWarpT : warpBody(t);
  return sampleCurve(he, rate, warpT);
}
```

- 各倍音は 32 点（`HARM_ENV_POINTS` で固定）の時間エンベロープを持つ
- `rate = (点数-1)/origDur` で**実時間を点数にマップ**
- ループ中なら `warpBody(t)` で参照位置を 1 周回す
- release 中なら **その時点の `warpT` で固定**

`sampleCurve()` は 2 点線形補間:

```java
float sampleCurve(float[] c, float rate, float sec){
  if (c.length==1) return c[0];
  float idx = sec*rate;
  if (idx <= 0) return c[0];
  if (idx >= c.length-1) return c[c.length-1];
  int i0=(int)idx, i1=i0+1; float f=idx-i0;
  return c[i0] + (c[i1] - c[i0]) * f;
}
```

## CPU 負荷の見積もり

44.1 kHz で 1 サンプルあたり:

| 段 | 大きさ |
|---|---|
| 倍音ループ | N(40) × (sqrt + sin + 線形補間 ≈ 50 flop) ≈ 2000 flop |
| ノイズ | 1 read + 1 add |
| トレモロ | 1 sin + 1 mul |
| ビブラート | 1 sin + 1 pow |

**1 Voice あたり ≈ 2000 flop/sample × 44100 sample/s ≈ 90 Mflop/s**。
同時 24 voice で 2.2 Gflop/s。M1 Mac の 1 コアで余裕。

倍音数を 40 → 20 に減らせば負荷は半分。**スペック厳しい PC** で動かすなら
`MAX_HARMONICS` を analyzer 側で絞るか、`harmAmp[k] < 0.005` を間引く処理を入れる。

## どこを書き換えるか（別合成方式への移行）

| やりたいこと | 触る場所 |
|---|---|
| FM 合成にする | `uGenerate` の倍音ループを `sin(carrier + I·sin(modulator))` に置換、`InstrModel` に carrier/modulator/I のフィールドを追加 |
| サンプル再生にする | `InstrModel` に波形バッファ、`uGenerate` でピッチシフト読み出し |
| 物理モデリング | Voice を完全に別クラス、`triggerNote` で switch |
| ピッチを連続変更（グライド） | `targetF0` を `setTargetF0(midi)` で更新できるよう変える、`uGenerate` で `currentF0` を EMA で追従させる |
| ステレオ定位 | partId に応じて L/R ゲインを変えて `channels[0,1]` に書き分け |

## 次のページ

- 上流の `InstrModel` の中身 → [音色定義モデルと JSON](/pc-audio/instr-model/)
- 解析側がどう数値を作っているか → [倍音抽出・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/)
