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
  "created_at": "2026-05-10T12:34:56Z",
  "sample_rate": 44100,          // 解析時の内部サンプルレート

  "fundamental_hz": 261.63,      // 検出した基音
  "midi_note": 60,               // 最も近い MIDI ノート番号
  "note_name": "C4",
  "duration_sec": 2.31,          // トリム後の音の長さ
  "sustaining": true,            // 持続音(オルガン/弦/管)=true / 減衰音(ピアノ/撥弦/打)=false

  "envelope":  { ... },          // 全体振幅エンベロープ + ADSR 近似（下記）
  "inharmonicity_b": 0.00021,    // 非調和性係数 B: f_n ≈ n·f0·√(1 + B·n²)。0=完全調和
  "harmonics": [ { ... }, ... ], // 倍音ごとの定義（下記）
  "noise":     { ... },          // 残差ノイズ成分（下記）
  "waveform":  { ... },          // 単一周期波形（任意・ウェーブテーブル用）
  "features":  { ... }           // 表示用の特徴量（合成には使わない）
}
```

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

## `features` — 表示用特徴量（合成非依存）

```jsonc
"features": {
  "spectral_centroid_hz": 1820.4,
  "spectral_rolloff_hz": 4100.0,
  "spectral_bandwidth_hz": 2200.0,
  "zero_crossing_rate": 0.043,
  "spectral_flatness": 0.0021,
  "rms_peak": 0.31,
  "harmonic_count": 24
}
```

## API レスポンス（`POST /analyze`）

解析ツールのバックエンドは、上記 `instrument` に加えて描画用の生データを返す（JSON には保存しない）。

```jsonc
{
  "instrument": { ... },           // 上記フォーマット。これがダウンロード対象
  "preview": {
    "waveform": [ [min,max], ... ],// 波形を ~2000 区間に間引いた min/max ペア
    "spectrum_freq": [ ... ],      // スペクトル描画用の周波数軸
    "spectrum_db":   [ ... ]       // 同 振幅(dB)
  }
}
```
