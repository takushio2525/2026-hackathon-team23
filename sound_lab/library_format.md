# インストゥルメント定義 JSON フォーマット仕様

`sound_lab/analyzer` が出力し、`sound_lab/processing/instrument_player` が読み込む音色定義の形式。
バージョン識別子は `format` フィールドに入れる（現行 `sound_lab.instrument/1`）。

すべての時間は秒、周波数は Hz。配列の数値は JSON サイズを抑えるため丸めてある（振幅は概ね 4〜5 桁）。

## トップレベル

```jsonc
{
  "format": "sound_lab.instrument/1",
  "name": "piano_C4",            // 表示名（元ファイル名から）
  "source_file": "piano_C4.wav", // 解析元ファイル名
  "instrument_profile": "auto",  // 解析時の楽器プロファイル（auto / trumpet / drum など）
  "instrument_profile_label": "自動",
  "created_at": "2026-05-10T12:34:56Z",
  "sample_rate": 44100,          // 解析時の内部サンプルレート

  "fundamental_hz": 261.63,      // 検出した基音
  "midi_note": 60,               // 最も近い MIDI ノート番号
  "note_name": "C4",
  "duration_sec": 2.31,          // トリム後の音の長さ
  "sustaining": true,            // 持続音(オルガン/弦/管)=true / 減衰音(ピアノ/撥弦/打)=false

  "envelope":  { ... },          // 全体振幅エンベロープ + ADSR 近似（下記）
  "inharmonicity_b": 0.00021,    // 非調和性係数 B: f_n ≈ n·f0·√(1 + B·n²)。0=完全調和
  "modulation": { ... },         // ビブラート / トレモロ（周期的なピッチ・音量の揺れ。下記）
  "harmonics": [ { ... }, ... ], // 倍音ごとの定義（下記）
  "noise":     { ... },          // 残差ノイズ成分（下記）
  "waveform":  { ... },          // 単一周期波形（任意・ウェーブテーブル用）
  "attack_sample": { ... },       // 任意。トランペット / ドラム指定時の原音アタック波形（下記）
  "sustain_sample": { ... },      // 任意。トランペット指定時の原音定常ループ（下記）
  "drum_sample": { ... },         // 任意。ドラム指定時の原音1打サンプル（下記）
  "features":  { ... },          // 表示用の特徴量（合成には使わない）
  "fx":        { ... }           // 任意。ブラウザ編集スタジオで足したエフェクト設定（下記）
}
```

`fx` は解析器は出力せず、ブラウザの編集スタジオで「調整後の JSON」を書き出したときだけ付く。
本体の再合成（倍音 + エンベロープ + ノイズ + 非調和性 + `modulation`）には不要で、Processing 現行版は無視する。

## `envelope` — 全体振幅エンベロープ

```jsonc
"envelope": {
  "rate_hz": 200,            // values[] のサンプルレート
  "values": [0.0, 0.31, ...],// 全体振幅(0..1, ピーク=1)。長さ = duration_sec * rate_hz（上限あり）

  // 以下は values[] から当てはめた ADSR 近似（簡易合成用 / 表示用）
  "attack_sec": 0.006,
  "decay_sec": 0.18,
  "sustain_level": 0.42,     // ピーク基準(0..1)
  "release_sec": 0.45,

  // 持続音を要求長まで伸ばすときに values[] のどの区間をループするか
  "loop_start_sec": 0.9,
  "loop_end_sec": 1.7
}
```

**Processing 側の使い方（推奨）**: `values[]` を直接マスター振幅として使う。要求された発音長 `D` に対し、

- `sustaining == true`: `[0, loop_start_sec]` をそのまま再生 → `[loop_start_sec, loop_end_sec]` を
  `D - loop_start_sec - release_sec` 秒ぶんループ → 末尾 `release_sec` 秒（`values[]` の最後の区間）を再生。
- `sustaining == false`: ループせず先頭から再生。`D` が原音より長ければそのまま鳴らし切り、短ければ `D` 秒で
  リリース（`release_sec` でフェード）。

`attack/decay/sustain/release` の 4 値だけで鳴らす簡易モードも可（Processing スケッチに切替あり）。

## `modulation` — ビブラート / トレモロ

解析器が「周期的なピッチの揺れ（ビブラート）」「周期的な音量の揺れ（トレモロ）」を検出して入れる。
検出できなければ各値 0・`detected: false`（キーは常に存在する）。基音は単一値（`fundamental_hz`）として
持つので、揺れは合成時にこの定義から **掛け直す**（再合成は元の揺れを再現せず、ここの値で付け直す）。

```jsonc
"modulation": {
  "vibrato": {
    "rate_hz": 5.6,        // 揺れの速さ
    "depth_cents": 24.0,   // 揺れの全幅(セント)。実際の偏差は ±depth_cents/2
    "depth": 0.24,         // depth_cents / 100（半音=1.0 換算。あれば使ってよい）
    "onset_sec": 0.35,     // 音の頭から これだけ後に揺れが立ち上がる(おおよそ)
    "shape": "sine",       // 任意。波形(sine/triangle/sawtooth/square)。無ければ sine
    "regularity": 0.7,     // 0..1 周期性の強さ(表示用の目安)
    "detected": true
  },
  "tremolo": {
    "rate_hz": 5.2, "depth": 0.08,   // depth = 全幅(平均レベルに対する比)。1-depth..1 で変調
    "depth_cents": 0.0, "onset_sec": 0.0, "shape": "sine", "regularity": 0.6, "detected": true
  }
}
```

**合成側の使い方**: `vibrato` … 各倍音の周波数に `2^((depth_cents/2)·gate(t)·sin(2π·rate·t)/1200)` を掛ける
（`gate(t)` は `min(1, t/onset_sec)`）。`tremolo` … 最終振幅に `1 - depth/2 + (depth/2)·sin(2π·rate·t)` を掛ける。
Processing 版（`instrument_player.pde`）はこの 2 つを実装済み。

## `harmonics[]` — 倍音

`n = 1` が基音。配列は `n` 昇順。検出できなかった倍音は `amp = 0` で席だけ残す場合がある。

```jsonc
{
  "n": 2,                 // 倍音次数
  "ratio": 2.003,         // 実測周波数 / 基音（非調和性で整数からわずかにずれる）
  "amp": 0.51,            // 静的振幅。倍音中の最大が 1.0 になるよう正規化
  "amp_db": -5.84,        // 20·log10(amp)
  "phase": -1.42,         // 解析窓先頭での位相 [rad]（位相を合わせたい場合に使う。通常は無視可）
  "env": [1.0, 0.92, ...] // この倍音の時間エンベロープ(0..1, 自分の最大=1)。
  // env の長さは固定 env_points 点で、時間軸は envelope.values[] 全体（0〜duration_sec）に対応する。
  // ループ再生時はマスターと同じ loop_start/loop_end の位置をループする。
}
```

最終的な倍音 `n` の瞬時振幅 ≒ `voiceGain × ampEnv(t) × amp × harmEnv_n(t)`、
周波数 ≒ `targetF0 × ratio_n × √(1 + B·n²)`（`targetF0` は再生したい音程）。

加算後の総和は倍音数ぶん大きくなり得るので、Processing 側で `1 / Σamp` 程度の正規化を掛ける。

## `noise` — 残差ノイズ

調和成分をスペクトル上で差し引いた残り（アタックのノイズバースト、息・弓・打撃ノイズなど）。

```jsonc
"noise": {
  "level": 0.06,             // ノイズのピーク振幅 / 信号のピーク振幅
  "rate_hz": 200,
  "envelope": [0.0, 1.0, ...],// ノイズ振幅の時間形状(0..1, 自分の最大=1)。多くの楽器でアタックに山
  "bands_hz":   [0,125,250,500,1000,2000,4000,8000,16000,22050], // 帯域の境界
  "band_levels":[0.12, 0.31, 0.5, ...]  // 各帯域のノイズ強度(0..1, 最大=1)。長さ = bands_hz の要素数 - 1
}
```

**Processing 側の使い方**: 白色ノイズを `band_levels` の形に整形（FFT 整形 or 簡易フィルタバンク）した
ループバッファを作り、`level × envelope(t) × voiceGain` を掛けて加算合成に足す。

## `waveform` — 単一周期波形（任意）

```jsonc
"waveform": {
  "one_cycle_points": 1024,
  "one_cycle": [0.0, 0.02, ...]  // 定常部から取り出した 1 周期分（-1..1 正規化）
}
```

加算合成の代わりに、この 1 周期をウェーブテーブルとして読み出して鳴らす簡易モード用。倍音の時間変化は表現できない。

## `attack_sample` — 原音アタック波形（任意）

トランペット / ドラム指定で解析したときだけ入る。サイン波の倍音加算では再現しにくい、タンギング直後の息圧・
唇のバズ感、打面のクリック、胴鳴りの出だし、高域の立ち上がりを補うため、トリム後の原音先頭を短く正規化して保存する。
通常の安定した再合成に、この波形を先頭だけ重ねることで、砂嵐のような白色ノイズを増やさず輪郭を足す。

```jsonc
"attack_sample": {
  "sample_rate": 22050,
  "duration_sec": 0.18,
  "root_midi_note": 69,       // このアタック波形の元音程。移調時は playbackRate で追従
  "source_peak": 0.42,        // 正規化前のピーク値（表示・確認用）
  "values": [0.0, 0.012, ...] // -1..1 正規化済みの短い波形
}
```

トランペットでは通常 0.18 秒、ドラム / 打楽器では通常 0.45 秒を保存する。
ブラウザスタジオでは `fx.attack_sample_mix` と「原音アタックを重ねる」スライダーで量を調整できる。
Processing 現行版は未対応なので、この欄があっても無視して従来どおり鳴る。

## `sustain_sample` — トランペット原音定常ループ（任意）

`トランペット` プロファイルで解析したときだけ入る。サイン波の倍音加算では再現しにくい、伸びている音の中にある
唇の細かいバズ、管鳴り、倍音同士の干渉感を補うため、定常部から基音周期の整数倍に近い短い波形を切り出して保存する。
ブラウザスタジオでは通常の倍音合成の下に薄くループ再生する。

```jsonc
"sustain_sample": {
  "sample_rate": 44100,
  "duration_sec": 0.22,
  "root_midi_note": 69,       // この定常ループの元音程。移調時は playbackRate で追従
  "loop_start_sec": 0.0,
  "loop_end_sec": 0.22,
  "source_rms": 0.08,         // 正規化前の RMS（表示・確認用）
  "values": [0.0, 0.018, ...] // -1..1 に収めた短い波形
}
```

ブラウザスタジオでは `fx.sustain_sample_mix` と「原音の伸びを重ねる」スライダーで量を調整できる。
Processing 現行版は未対応なので、この欄があっても無視して従来どおり鳴る。

## `drum_sample` — ドラム原音1打サンプル（任意）

`ドラム / 打楽器` プロファイルで解析したときだけ入る。キック・スネア・ハイハット・クラッシュのような音は、
基音と倍音だけで再合成すると、打面のクリック、スナッピー、金属ノイズ、シンバルの複雑な散り方が崩れやすい。
そのためドラムモードでは、トリム後の原音1打を最大 3 秒だけ 44.1 kHz で保存し、ブラウザスタジオでは
これを主音として鳴らす。倍音・ノイズ解析は表示や軽い補助として残す。

```jsonc
"drum_sample": {
  "sample_rate": 44100,
  "duration_sec": 0.84,
  "root_midi_note": 54,
  "source_peak": 0.86,
  "values": [0.0, -0.021, ...]
}
```

ブラウザスタジオでは `fx.drum_sample_mix` と「原音1打を主音にする」スライダーで量を調整できる。
`fx.drum_pitch_follow` が `true` の場合だけ鍵盤の音程に合わせてピッチを変える。既定ではドラムらしく、どの鍵盤でも
元の1打のピッチで鳴る。

## `features` — 表示用特徴量（合成非依存）

`source_duration_sec` / `trimmed_lead_sec` / `trimmed_trail_sec` は、解析の先頭で行う**無音トリム**の結果。
解析器は元ファイルの先頭・末尾の無音（デジタル無音や、ピーク RMS から `-20dB`／`-50dB` 未満の暗騒音・準備音）を
自動でカットしてから解析する。`fundamental_hz` 以降の値や `envelope.values[]` は **トリム後の音**に対するもの。

```jsonc
"features": {
  "spectral_centroid_hz": 1820.4,
  "spectral_rolloff_hz": 4100.0,
  "spectral_bandwidth_hz": 2200.0,
  "zero_crossing_rate": 0.043,
  "spectral_flatness": 0.0021,
  "rms_peak": 0.31,
  "harmonic_count": 24,
  "drum_type_guess": "snare",       // ドラムモード時のみ。kick / snare / hihat / crash / drum
  "drum_type_label": "スネア / タム系",
  "drum_low_energy": 0.12,          // ドラムモード時のみ。低域エネルギー比
  "drum_mid_energy": 0.42,          // ドラムモード時のみ。中域エネルギー比
  "drum_high_energy": 0.46,         // ドラムモード時のみ。高域エネルギー比
  "drum_transient_strength": 8.3,   // ドラムモード時のみ。立ち上がりの鋭さの目安
  "drum_decay_sec": 0.34,           // ドラムモード時のみ。ピーク後の減衰時間の目安
  "source_duration_sec": 8.0,    // トリム前の元ファイルの長さ
  "trimmed_lead_sec": 2.13,      // 先頭で削った無音の長さ
  "trimmed_trail_sec": 0.0       // 末尾で削った無音の長さ
}
```

## `fx` — ブラウザ編集スタジオで足したエフェクト（任意）

`sound_lab/analyzer/static`（ブラウザの編集スタジオ）で「調整後の JSON」を書き出したときだけ付く付加情報。
リバーブ・ドライブ・コーラス・マスターフィルタ・ボディ EQ・移調・グライド・ノイズの出し方など、
**本体の再合成（倍音 / エンベロープ / ノイズ / 非調和性 / `modulation`）には含まれない演出**をまとめてある。
Processing 現行版は読まずに無視する（=これが付いていても従来どおり鳴る）。スタジオ側はこの欄を読み戻して
編集状態を復元する。キー名は `reverb.{mix,size_sec,damping,pre_ms,width}` / `drive.{amount,tone_hz}` /
`chorus.{mix,rate_hz,depth,width}` / `filter.{mode,cutoff_hz,q,lfo_rate_hz,lfo_depth}` /
`body_eq.{low_gain,mid_freq,mid_gain,mid_q,presence_gain,high_gain}` ほか。
`attack_sample_mix` は、`attack_sample` を合成音の先頭へ重ねる量。トランペット指定時のブラウザスタジオ初期値は
少し高めで、0 にすると従来の倍音合成のみになる。
`trumpet_wave_mix` は、解析した `waveform.one_cycle` を安定した主波形として混ぜる量。トランペット指定時に、
サイン波の倍音加算だけでは出にくい原音波形の芯を補う。
`sustain_sample_mix` は、`sustain_sample` を合成音の下に薄くループで重ねる量。0 にすると従来の倍音合成 + アタック補助だけになる。
`brass_layer.{mix,detune_cents}` は、トランペット指定時に使う薄い倍音レイヤーの量とピッチ差。単純なコーラスではなく、
各倍音に少しずれた補助発振を重ねて、唇のバズや管内反射で音が重なって聞こえる質感を補う。
`trumpet_resonance` は、トランペット指定時の管鳴り / ベルの抜けを補う専用ピーク EQ の強さ。
`drum_sample_mix` は、`drum_sample` を主音として重ねる量。ドラム指定時のブラウザスタジオ初期値は 1.0。
`drum_pitch_follow` は、ドラムサンプルを鍵盤音程に追従させるかどうか。
`modulation.{vibrato_depth_cents,vibrato_rate_hz,vibrato_onset_sec,vibrato_shape,tremolo_depth,tremolo_rate_hz,tremolo_shape}` は、
スタジオで意図的に付けた揺れを JSON 再読み込み時に復元するための設定。解析直後の初期再生では、音を安定させるため
検出ビブラート/トレモロは自動適用しない。
4音源バランス調整モードで ZIP 書き出しした JSON には、`fx.balance_master_volume`（書き出し時の音量倍率）と
`fx.balance_export_note`（WAV 化した音名）が追加される。

なお、スタジオで `brightness`（高次倍音の傾き）・倍音ごとの手動ゲイン・`oddEvenBal`・倍音数制限・
非調和性ミックスをいじった場合、その結果は **`harmonics[]` 本体に畳み込んで** 書き出される
（`ratio` / `amp` / `amp_db` が更新される）ので、`fx` を読めない環境でもその音色で鳴る。
ADSR スライダーの値も `envelope.attack_sec` 等に反映される（`envelope.values[]` 自体は変えない）。

## API レスポンス（`POST /analyze`）

解析ツールのバックエンドは、上記 `instrument` に加えて描画用の生データを返す（JSON には保存しない）。

```jsonc
{
  "instrument": { ... },           // 上記フォーマット。これがダウンロード対象
  "preview": {
    "waveform": [ [min,max], ... ],// 波形を ~2000 区間に間引いた min/max ペア
    "spectrum_freq": [ ... ],      // スペクトル描画用の周波数軸
    "spectrum_db":   [ ... ],      // 同 振幅(dB)
    "f0_cents":      [ ... ],      // ピッチトラック（中央値からのセント差）。ビブラート可視化用。取れなければ []
    "f0_rate_hz":    86.13         // f0_cents[] のサンプルレート
  }
}
```
