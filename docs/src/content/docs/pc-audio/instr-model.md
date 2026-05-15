---
title: 音色定義モデル（InstrModel）と JSON
description: data/*.json を加算合成用の配列に展開する InstrModel クラスと、JSON フォーマット仕様
sidebar:
  order: 5
---

実体: `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` 485〜585 行（`class InstrModel`）。
JSON 仕様の SSOT: `sound_lab/library_format.md`。

`InstrModel` は **JSON を 1 度パースして、Voice が使う配列の形にしておく前処理クラス**。
複数の `ResynthVoice` が同じ `InstrModel` を共有するので、ここで一度作っておけば
新規発音のたびにパースし直さずに済む。

## ライフサイクル

```
data/*.json (Path)
    │  rescanInstruments() がディレクトリ走査
    │  ファイル名昇順でソート → 楽器番号 0,1,2,...
    ▼
loadJSONObject(path)       Processing 標準
    │
    ▼
new InstrModel(root, sr)   ← このページの解説
    │  内部で配列を作って保持
    ▼
models.add(m)              ← グローバル ArrayList<InstrModel>
    │
    ▼  triggerNote() のときに modelForId(instrumentId)
    ▼
new ResynthVoice(m, ...)   ← 複数 Voice が m を共有
```

`models` は **読み取り専用** に扱う。Voice からの参照中に書き換えるとレースが起こる。

## フィールド一覧

```java
class InstrModel {
  float fundamentalHz;            // 元の解析音の基音 (Hz) — 表示用
  int   midiNote;                 // 元の MIDI ノート — 表示用
  String noteName;                // "C4" 等 — 表示用
  boolean sustaining;             // 持続音か (true) / 減衰音か (false)
  float inharmB;                  // 非調和性 B

  // 倍音
  int   N;                        // 倍音の個数（amp=0 を含む）
  int[]   harmN;                  // 倍音次数 (1,2,3,...)
  float[] harmRatio;              // 実周波数 / 基音
  float[] harmAmp;                // 振幅 (0..1, 最大=1 正規化済み)
  float[] harmPhase;              // 解析時の位相 [rad]
  float[][] harmEnv;              // 倍音ごとの時間エンベロープ (32 点)
  int   envPoints;                // 倍音 env の最大点数
  float harmNorm;                 // 1/Σamp — 倍音総和の正規化係数

  // 全体エンベロープ
  float[] envValues;              // 振幅エンベロープ（200 Hz サンプル）
  float   envRate;                // values[] のサンプルレート
  float   attackSec, decaySec, sustainLevel, releaseSec;
  float   loopStartSec, loopEndSec;

  // ノイズ
  float   noiseLevel;
  float[] noiseEnv;               // ノイズの時間エンベロープ
  float   noiseEnvRate;
  float[] noiseTable;             // 整形済み白色ノイズ (16384 点)

  // 揺れ
  float vibRateHz, vibDepthCents, vibOnsetSec;
  float tremRateHz, tremDepth;
}
```

`InstrModel` は **JSON を Voice の uGenerate がすぐ参照できる配列の形に直したもの**。
位相を進める計算は `phase[k] += 2π·f/sr` の形で書ける必要があるので、`harmN`, `harmRatio`,
`harmAmp` をバラした **同じ長さの並列配列** で持っているのがポイント。

## コンストラクタ（JSON ロード）

`InstrModel(JSONObject root, float synthSampleRate)` がやることを段ごとに見る。

### ① トップレベル — メタデータと持続音判定

```java
fundamentalHz = root.getFloat("fundamental_hz", 261.626f);
midiNote      = root.getInt("midi_note", 60);
noteName      = root.getString("note_name", "C4");
sustaining    = root.getBoolean("sustaining", true);
inharmB       = root.getFloat("inharmonicity_b", 0.0f);
```

`getFloat(key, default)` 形式でフォールバック値を必ず置く。**JSON にキーが無くても落ちない**
（古いバージョンの JSON でも読める）のがこのクラスの設計方針。

### ② エンベロープ

```java
JSONObject e = root.getJSONObject("envelope");
envValues  = toFloatArray(e.getJSONArray("values"));
envRate    = e.getFloat("rate_hz", 200);
attackSec  = e.getFloat("attack_sec", 0.01f);
decaySec   = e.getFloat("decay_sec", 0.05f);
sustainLevel = e.getFloat("sustain_level", 0.7f);
releaseSec = e.getFloat("release_sec", 0.08f);
loopStartSec = e.getFloat("loop_start_sec", (envValues.length-1)/envRate*0.4f);
loopEndSec   = e.getFloat("loop_end_sec",   (envValues.length-1)/envRate*0.7f);
if (envValues.length < 2){ envValues = new float[]{0,1,1,0}; envRate=10; }
if (loopEndSec <= loopStartSec) loopEndSec = loopStartSec + max(0.05f, 1.0f/envRate);
```

- `envValues[]` は **解析側が 200 Hz でサンプリングした全体振幅**（持続音だと数秒分の点列）
- `loop_start_sec` / `loop_end_sec` は **持続音をループするときに繰り返す区間**
- ループ点が壊れていた場合の保険ガード（`loopEndSec <= loopStartSec`）を入れてある

:::tip[なぜ ADSR 4 値も持つのか]
本体は `envValues[]` を使うが、Processing で「ADSR 4 値だけで簡易合成したい」場合用に
4 値も別途持っている。キー `a` でトグル可能。
:::

### ③ 倍音列

```java
JSONArray ha = root.getJSONArray("harmonics");
N = ha.size();
harmN=new int[N]; harmRatio=new float[N]; harmAmp=new float[N]; harmPhase=new float[N];
harmEnv=new float[N][];
float sumAmp=0;
for (int i=0;i<N;i++){
  JSONObject h = ha.getJSONObject(i);
  harmN[i]     = h.getInt("n", i+1);
  harmRatio[i] = h.getFloat("ratio", harmN[i]);
  harmAmp[i]   = h.getFloat("amp", 0);
  harmPhase[i] = h.getFloat("phase", 0);
  JSONArray ev = h.hasKey("env") ? h.getJSONArray("env") : null;
  harmEnv[i]   = (ev!=null && ev.size()>=2) ? toFloatArray(ev) : new float[]{1,1};
  if (harmAmp[i]>0) sumAmp += harmAmp[i];
}
harmNorm = 1.0f / max(sumAmp, 1.0f);
harmonicCount = 0; for (int i=0;i<N;i++) if (harmAmp[i]>0) harmonicCount++;
```

- `harmAmp` が 0 の倍音も席を残す（`harmonics[k].amp == 0` で uGenerate がスキップ）
- `harmNorm = 1/Σamp` で **加算後の総振幅が概ね 1 になる** よう前計算
- 倍音 env が無い・点数 < 2 の場合は `{1,1}` を入れて常に 1 を返すようにする

### ④ スペクトル整形ノイズ — 1 度だけ FFT

```java
JSONObject no = root.hasKey("noise") ? root.getJSONObject("noise") : null;
noiseLevel   = no!=null ? no.getFloat("level", 0) : 0;
noiseEnv     = (no!=null && no.hasKey("envelope")) ? toFloatArray(no.getJSONArray("envelope")) : new float[]{1,1};
noiseEnvRate = no!=null ? no.getFloat("rate_hz", 200) : 200;
float[] bandsHz  = (no!=null && no.hasKey("bands_hz"))    ? toFloatArray(no.getJSONArray("bands_hz"))    : new float[]{0, sr/2};
float[] bandLevs = (no!=null && no.hasKey("band_levels")) ? toFloatArray(no.getJSONArray("band_levels")) : new float[]{1};
noiseTable = makeShapedNoise(synthSampleRate, bandsHz, bandLevs);
```

`makeShapedNoise()` の中身:

```java
float[] makeShapedNoise(float sr, float[] bandsHz, float[] bandLevs){
  if (noiseLevel <= 0.0005f) return new float[]{0};
  int Nfft = 16384;
  float[] buf = new float[Nfft];
  for (int i=0;i<Nfft;i++) buf[i] = random(-1,1);    // 白色ノイズ
  FFT fft = new FFT(Nfft, sr);
  fft.forward(buf);
  int bands = fft.specSize();
  for (int b=0;b<bands;b++){
    float fc = b * sr / Nfft;
    fft.setBand(b, fft.getBand(b) * bandGain(fc, bandsHz, bandLevs));
  }
  fft.inverse(buf);
  // 正規化
  float mx=1e-9f; for (int i=0;i<Nfft;i++) mx=max(mx, abs(buf[i]));
  for (int i=0;i<Nfft;i++) buf[i] /= mx;
  return buf;
}
```

要点:

- **オフライン処理**: 楽器ごとに 1 回だけ実行（コンストラクタ内）。発音時は配列を読むだけ
- **白色ノイズ → FFT → 帯域ごとにゲイン → 逆 FFT** で「JSON が定義する色のノイズ」が完成
- 16384 サンプル ≈ 0.37 秒 ぶん。Voice がリングバッファとしてループ参照
- `bandGain()` は連続関数ではなくバンドごとの定数ゲイン（簡単で十分な精度）

:::tip[なぜ事前に FFT してテーブル化するのか]
リアルタイムで毎サンプル FIR フィルタをかけるより、**1 度だけ FFT して固定バッファ** を
作って読むほうが圧倒的に安い（テーブル参照 O(1)）。ノイズの色は楽器ごとに固定でいいので
このトレードオフは妥当。
:::

### ⑤ ビブラート / トレモロ — 検出フラグつきで読む

```java
JSONObject mod = root.hasKey("modulation") ? root.getJSONObject("modulation") : null;
JSONObject vib = (mod!=null && mod.hasKey("vibrato")) ? mod.getJSONObject("vibrato") : null;
JSONObject trem= (mod!=null && mod.hasKey("tremolo")) ? mod.getJSONObject("tremolo") : null;
vibRateHz     = (vib!=null && vib.getBoolean("detected", false)) ? vib.getFloat("rate_hz", 0) : 0;
vibDepthCents = (vib!=null && vib.getBoolean("detected", false)) ? vib.getFloat("depth_cents", 0) : 0;
vibOnsetSec   = (vib!=null) ? vib.getFloat("onset_sec", 0) : 0;
tremRateHz    = (trem!=null && trem.getBoolean("detected", false)) ? trem.getFloat("rate_hz", 0) : 0;
tremDepth     = (trem!=null && trem.getBoolean("detected", false)) ? constrain(trem.getFloat("depth", 0), 0, 0.95f) : 0;
```

**`detected: false` のときは 0 を入れる** ことで、`uGenerate` 側の
`if (m.vibDepthCents > 0.01f && m.vibRateHz > 0.001f)` で自動スキップされる。
解析が「揺れなし」と判定した楽器に揺れを乗せない、自然な設計。

## JSON フォーマット仕様（要約）

詳細は `sound_lab/library_format.md`。ここではサイトで読みやすい形に整理する。

### トップレベル

```jsonc
{
  "format": "sound_lab.instrument/1",   // バージョン文字列（必須）
  "name": "piano_C4",
  "source_file": "piano_C4.wav",
  "created_at": "2026-05-10T12:34:56Z",
  "sample_rate": 44100,

  "fundamental_hz": 261.63,
  "midi_note": 60,
  "note_name": "C4",
  "duration_sec": 2.31,
  "sustaining": true,                   // 持続音か減衰音か

  "envelope":   { ... },
  "inharmonicity_b": 0.00021,
  "modulation": { ... },
  "harmonics":  [ ... ],
  "noise":      { ... },
  "waveform":   { ... },                // 任意
  "features":   { ... },                // 表示用、合成には使わない
  "fx":         { ... }                 // 任意、編集スタジオで足したエフェクト
}
```

### `envelope`

```jsonc
"envelope": {
  "rate_hz": 200,
  "values": [0.0, 0.31, ...],           // ピーク=1 に正規化された時間振幅
  "attack_sec": 0.006,
  "decay_sec": 0.18,
  "sustain_level": 0.42,
  "release_sec": 0.45,
  "loop_start_sec": 0.9,
  "loop_end_sec": 1.7
}
```

**InstrModel の使い方**: `values[]` を主、4 値はバックアップ（簡易 ADSR モード用）。

### `harmonics[]`

```jsonc
{
  "n": 2,                  // 倍音次数
  "ratio": 2.003,          // 実周波数 / 基音
  "amp": 0.51,             // 振幅 (倍音中の最大 = 1.0)
  "amp_db": -5.84,         // 20·log10(amp) — 表示用
  "phase": -1.42,          // 解析窓先頭での位相 [rad]
  "env": [1.0, 0.92, ...]  // 倍音の時間エンベロープ (固定 32 点)
}
```

**ratio が整数からずれている** ことに注目。倍音が完全に `n·f0` ではなく
非調和性で少しずれている事実を残している。これがリアル感の源。

### `noise`

```jsonc
"noise": {
  "level": 0.06,
  "rate_hz": 200,
  "envelope": [0.0, 1.0, ...],          // ノイズ振幅の時間形状
  "bands_hz":   [0,125,250,500,1000,2000,4000,8000,16000,22050],
  "band_levels":[0.12, 0.31, 0.5, ...]  // 各帯域のノイズ強度 (最大=1)
}
```

`bands_hz` の要素数 - 1 = `band_levels` の要素数。

### `modulation`

```jsonc
"modulation": {
  "vibrato": {
    "rate_hz": 5.6,
    "depth_cents": 24.0,
    "depth": 0.24,                       // depth_cents / 100
    "onset_sec": 0.35,
    "regularity": 0.7,
    "detected": true
  },
  "tremolo": {
    "rate_hz": 5.2,
    "depth": 0.08,
    "onset_sec": 0.0,
    "regularity": 0.6,
    "detected": true
  }
}
```

**`detected: false` ならその揺れは合成に乗らない**。解析側が判定する。

## バージョン管理

JSON の `format` フィールドで世代管理する。

| バージョン | 内容 |
|---|---|
| `sound_lab.instrument/1` | 現行。倍音 + envelope + noise + modulation + (任意) waveform + fx |

将来フォーマットを変えるなら:

1. `format` を `sound_lab.instrument/2` に上げる
2. 解析側 `analyzer.py` で v2 を書き出す
3. `InstrModel` のコンストラクタ冒頭で `format` を読み、v1/v2 で分岐
4. v1 の JSON も v2 と一緒に動かす（しばらくは互換維持）

## どこを書き換えるか

| やりたいこと | 触る場所 |
|---|---|
| 別フォーマット (`sfz`, `sf2`) を読みたい | `InstrModel` のコンストラクタを **読み手別に複数用意**、`triggerNote` で振り分け |
| 倍音数の上限を増やしたい | analyzer 側の `MAX_HARMONICS` を上げ、JSON を作り直す。`InstrModel` は配列を動的にとっているので無修正 |
| ノイズテーブルのサイズを増やす | `makeShapedNoise` の `Nfft` を上げる（精度↑、メモリ↑） |
| 音色を実行時にブレンドしたい | `InstrModel` の派生クラスを作り、`harmAmp[k]` を 2 つの音色の重み付き和にする |

## 次のページ

- 合成側の数学 → [加算合成ボイス（ResynthVoice）](/pc-audio/resynth-voice/)
- これらの数値がどう作られるか → [音声解析パイプライン全体](/pc-audio/analyzer-overview/)
- マルチポート受信 → [マルチポート同時受信](/pc-audio/serial-handling/)
