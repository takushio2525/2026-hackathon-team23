---
title: 加算合成エンジン
description: Processing 側の音作り — 基音×倍音の合成式、非調和性、ADSR、ボイスプール、スペクトル整形ノイズ、ビブラート/トレモロ
sidebar:
  order: 6
---

:::note[この章で分かること]
- 「加算合成」が何で、なぜサイン波を足すだけで楽器音になるか
- 倍音ごとの振幅 / 周波数比 / エンベロープが音色を決める仕組み
- ピアノやベルが持つ「非調和性」をどう近似するか
- ADSR エンベロープと、その上位互換として用意してある「実測エンベロープ」
- 複数音同時発音（ポリフォニー）を `Voice` プールで管理する方法
- スペクトル整形ノイズ・ビブラート・トレモロで音をリアルに寄せる方法
:::

:::tip[読了目安]
**約 15 分**。前提: 三角関数、サンプリング（44.1 kHz とは何か）、Processing/Java の基本構文。
:::

実装本体: `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde`
音色定義: `pc_app/test_v2/orchestra_resynth/data/*.json`（実体は `sound_lab/` で生成）

## 加算合成（Additive Synthesis）とは

フーリエ級数の発想：**どんな周期波形も、サイン波の重ね合わせで表現できる**。
これを使って音を「設計」するのが加算合成。

合成式の基本形：

$$
s(t) = \sum_{k=1}^{N} A_k \sin(2\pi f_k t + \phi_k)
$$

- $f_k$ : k 番目の倍音の周波数（基音 $f_0$ の整数倍）
- $A_k$ : k 番目の倍音の振幅
- $\phi_k$ : k 番目の倍音の位相

たとえば $f_0 = 440$ Hz の A4 の波形を作るなら：

- 第 1 倍音: 440 Hz、強い
- 第 2 倍音: 880 Hz、中くらい
- 第 3 倍音: 1320 Hz、弱い
- ...

これだけで「A4 の音」になる。実際の楽器音（オルガン、フルート、弦）は、
**どの倍音がどれくらい強いか**（スペクトル）が楽器ごとに違うだけ。

## 倍音定義の JSON フォーマット

`data/0_organ.json` の抜粋：

```json
{
  "fundamental_hz": 261.626,
  "midi_note": 60,
  "note_name": "C4",
  "sustaining": true,
  "harmonics": [
    { "n": 1, "ratio": 1.0, "amp": 1.00, "phase": 0.0, "env": [1.0, 1.0] },
    { "n": 2, "ratio": 2.0, "amp": 0.60, "phase": 0.0, "env": [1.0, 1.0] },
    { "n": 3, "ratio": 3.0, "amp": 0.40, "phase": 0.0, "env": [1.0, 1.0] },
    ...
  ],
  "envelope": { "values": [...], "rate_hz": 200, "attack_sec": 0.015, ... },
  "noise":      { "level": 0.018, "bands_hz": [...], ... },
  "modulation": { "vibrato": {...}, "tremolo": {...} },
  "inharmonicity_b": 0.0
}
```

| 項目 | 意味 |
|---|---|
| `fundamental_hz` | このサンプルが録音された / 解析された基準周波数。本物の C4 = 261.626 Hz |
| `harmonics[]` | 倍音テーブル。`n` は倍数（1, 2, 3, ...）、`ratio` は厳密な周波数比、`amp` は振幅 |
| `envelope` | 全体のレベル時間変化（後述） |
| `noise` | スペクトル整形ノイズの定義 |
| `modulation` | ビブラート / トレモロのパラメータ |
| `inharmonicity_b` | 非調和性係数（後述） |

`sound_lab/` 配下の Python スクリプトが、本物の楽器音をスペクトル解析してこの JSON を
吐く。手書きでも作れる。

## 楽器番号と JSON の対応

楽器ノードは `NoteSenderConfig.instrumentId` で送る楽器番号を決める。
Processing 側は `data/` 内のファイル名昇順で 0, 1, 2, 3 ... の楽器番号を割り当てる：

```java
void rescanInstruments(){
    instrumentFiles.clear();
    File[] fs = new File(dataPath("")).listFiles();
    for (File f : fs)
        if (f.getName().toLowerCase().endsWith(".json"))
            instrumentFiles.add(f);
    java.util.Collections.sort(instrumentFiles, /* ファイル名昇順 */);
    // index 0, 1, 2, ... が楽器番号になる
}
```

`data/` に置かれているファイル例：

```
0_organ.json           ← 楽器番号 0
1_flute.json           ← 楽器番号 1
2_bell.json            ← 楽器番号 2
3_flute_tweaked.json   ← 楽器番号 3（予備）
```

ファイル名の頭の数字は **人間が見やすくする目印** で、実際の番号は配列の index。
楽器番号 1 が「フルート」になるようにファイル名を揃えてある。

## 基音周波数の決定

`triggerNote(partId, instrumentId, midi, velocity, durationMs)` で発音指示を受けたとき、
`midi` から実際に出すべき周波数を計算する：

$$
f_0 = 440 \times 2^{(midi - 69) / 12}
$$

```java
this.targetF0 = 440f * pow(2, (midi - 69)/12.0f);
```

- 69 = MIDI ノート番号で A4（440 Hz の基準）
- 12 = 1 オクターブ = 12 半音
- 1 半音 = $2^{1/12} \approx 1.05946$ 倍

この `targetF0` が、JSON の `fundamental_hz` に **置き換わる**。
つまり JSON で「C4 で解析された倍音テーブル」が、別のノートに転調されて鳴る。

例: C4 で録音されたオルガン定義を G4（MIDI=67）で鳴らす場合
- C4 = 261.626 Hz、G4 = 391.995 Hz
- 1.5 倍速で再生したような効果（ただし倍音構造は維持）

## 倍音ごとの合成

各 `Voice` の毎サンプル処理（`ResynthVoice::uGenerate()` 内）：

```java
float s = 0;
for (int k = 0; k < m.N; k++){
    float amp = m.harmAmp[k]; if (amp <= 0) continue;
    int n1 = m.harmN[k];
    float f = targetF0 * m.harmRatio[k] * sqrt(1 + m.inharmB * n1 * n1) * pitchMul;
    if (f >= sr * 0.5f) continue;   // ナイキスト超は捨てる
    phase[k] += TWO_PI * f / sr;
    if (phase[k] >= TWO_PI) phase[k] -= TWO_PI;
    s += amp * harmEnvAt(k, tSec) * sin(phase[k]);
}
s *= m.harmNorm;
```

ポイント：

### 位相の累積

毎サンプル `phase[k]` に `2πf/sr` を足す。`sr = 44100` Hz、`f = 440` Hz なら：

$$
\Delta\phi = \frac{2\pi \times 440}{44100} \approx 0.0627 \text{ rad/sample}
$$

100 サンプル（≒ 2.27 ms）で約 6.27 rad ≒ 1 周期分。位相を累積して `sin()` を取れば、
連続したサイン波になる。`phase >= 2π` で `2π` 引くのは数値オーバーフロー防止。

### `TWO_PI` のラップ

`phase` が `2π` を超えたら引く。これにより `phase` は常に [0, 2π) の範囲にあり、
`sin()` の引数として精度を保つ。`sin()` 自体は引数が大きくても動くが、
float の精度が落ちる（10 分鳴らし続けると位相が累積してジッタが出る）。

### ナイキスト周波数のチェック

サンプリングレート `sr` に対して `sr/2 = 22050 Hz` を超える成分はエイリアシングして
低周波に化ける。チェックして捨てる：

```java
if (f >= sr * 0.5f) continue;
```

第 50 倍音以上は大抵この範囲を超えるので、自動的に省かれる。

### 振幅正規化

`harmNorm = 1 / max(sum(harmAmp), 1)` で、倍音の合計振幅を正規化する：

```java
harmNorm = 1.0f / max(sumAmp, 1.0f);
```

これがないと、倍音 10 個の楽器は単音 10 倍の音量になってしまう。
正規化で音量を揃え、楽器間の音量差を `velocity` だけでコントロールできる。

## 非調和性（Inharmonicity）

弦楽器（特にピアノ）は、本来「整数倍の倍音」のはずが、実際には少しずつ高い方にずれる。
これを **非調和性（inharmonicity）** と呼び、近似式は：

$$
f_n = n \times f_0 \times \sqrt{1 + B \times n^2}
$$

ここで $B$ が非調和性係数（小さい正数。フルートは 0、ピアノは 0.0001〜0.0005 程度）。
$n^2$ が掛かっているので、**高い倍音ほど大きくずれる**。

実装：

```java
float f = targetF0 * m.harmRatio[k] * sqrt(1 + m.inharmB * n1 * n1) * pitchMul;
```

- フルート: `inharmonicity_b = 0` → 普通の整数倍音
- ピアノ風: `inharmonicity_b = 0.0005` → 弦らしい「うねり」が出る
- ベル: 数 % 程度の非整数比を持つので、`harmRatio` 自体に非整数を入れる方が自然

## 倍音ごとのエンベロープ

`harmEnv[k]` は **倍音 k のレベルが時間とともにどう変わるか** を配列で持つ：

```json
"harmonics": [
    { "n": 1, "ratio": 1.0, "amp": 1.0, "env": [1.0, 1.0, 0.95, 0.90, 0.80, ...] }
]
```

`env = [1.0, 1.0]` だけなら定常（時間変化なし）。たとえばピアノなら、
高い倍音ほど早く減衰するので：

- 第 1 倍音 env: `[1.0, 1.0, 1.0, ...]`（持続）
- 第 8 倍音 env: `[1.0, 0.6, 0.3, 0.1, 0]`（急速減衰）

`harmEnvAt(k, t)` で時刻 `t` における倍音 k のレベルを補間する。
これで「アタックは派手、減衰でだんだん丸くなる」みたいな自然な音作りができる。

## 全体エンベロープ（ADSR と「実測エンベロープ」）

音の **全体の音量** が時間とともにどう変わるかは、JSON の `envelope` で定義する。

### 方式 1: 実測エンベロープ（`values` 配列）

```json
"envelope": {
    "rate_hz": 200,
    "values": [0.0, 0.33, 0.67, 1.0, 0.99, 0.97, 0.95, ...],
    "loop_start_sec": 0.08,
    "loop_end_sec": 0.22
}
```

- `values` は 200 Hz サンプリングのレベル時系列
- `loop_start_sec` / `loop_end_sec` の区間が「持続部」として無限に繰り返される

これは本物の楽器音を `sound_lab` でアタック検出 → ループ検出して得た「実測の包絡」。
ADSR の 4 値より細かい表現ができる。

### 方式 2: ADSR 4 値（フォールバック）

```json
"envelope": {
    "attack_sec": 0.015,
    "decay_sec":  0.035,
    "sustain_level": 0.92,
    "release_sec": 0.04
}
```

伝統的なシンセサイザーの ADSR。実装：

```java
if (t < a) return t / max(a, 1e-4f);                                   // Attack
if (t < a + d) {                                                       // Decay
    float u = (t - a) / max(d, 1e-4f);
    return lerp(1, s, u);
}
return s;                                                              // Sustain
```

「t」変数の進み方は `tSec += 1.0f/sr` で毎サンプル更新。
release は noteOff 時点から別計算（次節）。

### 切替

ユーザーは 'a' キーで `useSimpleADSR` を切り替えられる：

```java
if (c == 'a') { useSimpleADSR = !useSimpleADSR; }
```

実測エンベロープが本物の楽器音に近いが、ADSR の方が「シンセらしい」音になる。

## Release の処理

`noteOff()` が呼ばれた瞬間の音量を起点に、`releaseSec` で 0 まで減衰させる：

```java
void noteOff(){
    releaseStartLevel = sustainBodyLevel(tSec);
    releaseStartT     = tSec;
    releasing = true;
}

float ampAt(float t){
    if (!releasing) return sustainBodyLevel(t);
    float u = (t - releaseStartT) / relSec();
    if (u >= 1) return 0;
    float k = 1 - u;
    return releaseStartLevel * k * k;   // (1-u)^2 で滑らかに 0 へ
}
```

`(1-u)^2` で 2 次曲線フェードアウト。線形より自然に消える。

### noteOff のトリガー

NOTE パケットの `durationMs` から自動 noteOff される：

```java
void triggerNote(...){
    Voice v = new Voice(...);
    v.scheduledOffMs = millis() + max(40, durationMs);
    activeVoices.add(v);
}

void draw(){
    int now = millis();
    for (Voice v : activeVoices)
        if (!v.releasing && now >= v.scheduledOffMs)
            v.noteOff();
    // ...
}
```

`durationMs` が小さすぎると無音になるので、最低 40 ms を保証する `max(40, ...)`。

## ボイスプール（ポリフォニー）

複数の音を同時に鳴らすには **ボイスプール** を用意する。

```java
final int MAX_POLYPHONY = 24;
ArrayList<ResynthVoice> activeVoices = new ArrayList<>();

void triggerNote(...){
    // 上限超過なら最古を強制 release
    int guard = 0;
    while (countNonReleasing() >= MAX_POLYPHONY && guard++ < MAX_POLYPHONY){
        for (ResynthVoice v : activeVoices){
            if (!v.releasing){ v.noteOff(); break; }
        }
    }
    ResynthVoice v = new ResynthVoice(m, midi, gain, useSimpleADSR);
    v.patch(out);   // Minim の音声出力ラインに接続
    activeVoices.add(v);
}
```

24 ボイス。3 声輪唱 × 各音の release 余韻でも余裕。

### release 完了の検知

`uGenerate()` の末尾：

```java
if (releasing && (tSec - releaseStartT) >= relSec()) done = true;
else if (!done && a <= 1e-4f && tSec > 0.15f) done = true;
```

release 時間が過ぎたら `done = true`。`draw()` が done のボイスを `unpatch()` で
切り離して活性リストから除去する。これによりリソースが回収される。

## スペクトル整形ノイズ

純粋なサイン波の和だけだと「アナログシンセ」っぽい無機質な音になる。
本物の楽器音には **息や弓のかすれ** に由来するノイズ成分がある。

JSON の `noise`：

```json
"noise": {
    "level": 0.018,
    "bands_hz":    [0, 250, 1000, 4000, 16000, 22050],
    "band_levels": [0.2, 0.4, 0.7, 1.0, 0.6, 0.2]
}
```

実装は **白色ノイズを生成 → FFT → 各帯域に重み付け → 逆 FFT** で、好きなスペクトルの
ノイズを 1 回作っておく：

```java
float[] makeShapedNoise(float sr, float[] bandsHz, float[] bandLevs){
    int Nfft = 16384;
    float[] buf = new float[Nfft];
    for (int i = 0; i < Nfft; i++) buf[i] = random(-1, 1);
    FFT fft = new FFT(Nfft, sr);
    fft.forward(buf);
    for (int b = 0; b < fft.specSize(); b++){
        float fc = b * sr / Nfft;
        fft.setBand(b, fft.getBand(b) * bandGain(fc, bandsHz, bandLevs));
    }
    fft.inverse(buf);
    // 正規化
    return buf;
}
```

16384 サンプル = 約 0.37 秒のループ。これをノイズテーブルとして循環再生する：

```java
s += m.noiseTable[(int)noisePos] * ne;
noisePos += 1; if (noisePos >= m.noiseTable.length) noisePos -= m.noiseTable.length;
```

`ne = noiseEnvAt(t) * noiseLevel` で時間変化を加える。

## ビブラート / トレモロ

`modulation` セクションで指定する：

```json
"modulation": {
    "vibrato": { "detected": true, "rate_hz": 5.0, "depth_cents": 30.0, "onset_sec": 0.3 },
    "tremolo": { "detected": true, "rate_hz": 5.0, "depth": 0.15 }
}
```

### ビブラート（周波数変調）

```java
if (m.vibDepthCents > 0 && m.vibRateHz > 0){
    float vg = (tSec / m.vibOnsetSec).clamp(0, 1);   // onset で徐々に効かせる
    pitchMul = pow(2, (m.vibDepthCents * 0.5f * vg * sin(vibPhase)) / 1200.0f);
    vibPhase += TWO_PI * m.vibRateHz / sr;
}
```

- `depth_cents = 30`: ±15 セント（≒ 1% ピッチ揺れ）
- `rate_hz = 5`: 1 秒に 5 周期の周期的揺れ
- `onset_sec = 0.3`: 発音 0.3 秒後から徐々に効く（自然な印象）

ピッチが揺れることで、ベタ打ちの音に「人間味」が加わる。

### トレモロ（振幅変調）

```java
if (m.tremDepth > 0 && m.tremRateHz > 0){
    s *= 1.0f - m.tremDepth * 0.5f + m.tremDepth * 0.5f * sin(tremPhase);
    tremPhase += TWO_PI * m.tremRateHz / sr;
}
```

振幅を周期的に変調する。弦楽器の弓返しや、コーラスのフェイクに使える。

## オーディオ出力（Minim ライブラリ）

Processing で音を出すライブラリは複数あるが、本プロジェクトは **Minim** を使う：

```java
import ddf.minim.*;
import ddf.minim.ugens.*;

Minim minim;
AudioOutput out;

void setup(){
    minim = new Minim(this);
    out = minim.getLineOut(Minim.STEREO, 1024, 44100);
}
```

- バッファサイズ 1024 サンプル = 約 23 ms（44.1 kHz）
- ステレオ出力（本プロジェクトはモノ → 両チャンネル同じ）

`ResynthVoice` は `UGen`（Unit Generator）を継承していて、Minim の音声グラフに
`patch(out)` で組み込む。`uGenerate(float[] channels)` メソッドが Minim から
自動的に呼ばれて、サンプルを生成する。

## シリアル受信スレッドと描画スレッドの分離

Processing では `serialEvent()` は **シリアルスレッド** で呼ばれる。
ここで `Voice` 操作（`triggerNote()` 等）をすると、`draw()` スレッドと競合する。

そこで、シリアルスレッドは **20 B 揃ったパケットをキューに積むだけ**：

```java
void serialEvent(Serial p){
    // ... 20 B 揃ったら
    packetQueue.offer(copy);
}
```

`draw()` スレッドが毎フレームキューから取り出して処理：

```java
void draw(){
    drainPackets();   // ここで triggerNote() / noteOff() を呼ぶ
    // ... UI 描画
}
```

`ConcurrentLinkedQueue` を使うことで、ロックなしでスレッド間データ受け渡しができる。
これにより `Voice` の操作は draw スレッドだけで行われ、競合が起きない。

## 全体のデータフロー

```
NOTE バイナリ (USB Serial)
   │
   │ serialEvent (Serial スレッド)
   │   - magic でフレーム同期
   │   - 20 B 揃ったら packetQueue へ
   ▼
ConcurrentLinkedQueue
   │
   │ drainPackets (draw スレッド、毎フレーム)
   │   - type==NOTE のみ抽出
   │   - partId/noteNumber/velocity/duration/instrumentId をパース
   ▼
triggerNote(partId, instrumentId, midi, velocity, durationMs)
   │
   │ - MAX_POLYPHONY 超過なら最古を release
   │ - ResynthVoice 生成
   │ - patch(out) で出力ラインに接続
   ▼
activeVoices (ArrayList<ResynthVoice>)
   │
   │ Minim が 44.1 kHz × 1024 サンプル単位で uGenerate を呼ぶ
   │
   ▼ 各 Voice の uGenerate(channels)
       - 倍音ループ s += amp * env * sin(phase)
       - ノイズ加算
       - ビブラート / トレモロ
       - 全体エンベロープ × velocity × masterVolume
   │
   ▼
スピーカ
```

## デバッグの観点

UI 上に表示される情報：

- **発音中ボイス数 / MAX_POLYPHONY**: 24 に張り付いていたら同時発音オーバー
- **マスター音量**: クリップしていたら下げる
- **声部ごとの直近イベント**: どの partId から音が来ているか
- **シリアルポート受信カウント**: 楽器から本当にパケットが来ているか
- **波形スコープ**: 出力波形がクリッピングしていないか目視確認

キーボード操作：

| キー | 動作 |
|---|---|
| `t` | テスト和音（C・E・G を楽器 0/1/2 で同時発音）— Arduino なしで動作確認 |
| `0`〜`3` | その番号の楽器で C4 を 1 発鳴らす（楽器試聴） |
| `r` | シリアルポート再列挙 |
| `i` | data/ の楽器定義再スキャン |
| `a` | ADSR ↔ 実測エンベロープ切替 |
| `+` / `-` | マスター音量 |
| Space | 全音停止 |

## 拡張のアイデア

- **エフェクト**: Minim の `Delay` / `Reverb` を `out` 手前に挟む
- **可視化強化**: FFT して周波数スペクトルを画面表示
- **波形録音**: `Minim.AudioRecorder` で `.wav` 出力
- **MIDI 入力**: キーボードからの MIDI を受けて発音（楽器番号は固定 0）

## 次に読むべきページ

- 楽器番号がどう送られるか → [バイナリパケット](/deep-dive/binary-packet/)
- 楽譜進行（NOTE が来る前の話） → [楽譜進行ロジック](/deep-dive/score-progression/)
- 音色 JSON 自体の作り方 → `sound_lab/library_format.md`（リポジトリ内）
