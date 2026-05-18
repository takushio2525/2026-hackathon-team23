---
title: 音声解析パイプライン全体
description: sound_lab/analyzer/analyzer.py が WAV から JSON を作るまでの 9 段の処理段を俯瞰する
sidebar:
  order: 7
---

実体:
- `sound_lab/analyzer/analyzer.py`（670 行）— 解析コア
- `sound_lab/analyzer/app.py`（96 行）— Flask バックエンド
- `sound_lab/analyzer/static/`（HTML/JS）— ブラウザ UI

このページは **「analyzer.py が WAV をもらってから JSON を返すまで、どんな順でどの数学を
通っているか」** の俯瞰。各段の詳細は次の 2 ページに分かれている:

- [倍音抽出・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/) — FFT/STFT で何をしているか
- [基音検出・ADSR・ビブラート](/pc-audio/analyzer-modulation/) — pyin・自己相関・ADSR フィット・周期性検出

## 入出力契約

```python
result = analyze_file(path_to_wav: str, name: str | None) -> dict
# 返り値:
#   { "instrument": {...},  # JSON 化して pc_app/test_v2/orchestra_resynth/data/ に置く（ファイル名昇順で index 化）
#     "preview":    {...} }  # 描画用の生データ（保存はしない）
```

- 入力: 単音の WAV / FLAC / OGG / MP3 / AIFF / M4A（librosa が読めるもの全部）
- 出力: JSON フォーマット `sound_lab.instrument/1` ([仕様](/pc-audio/instr-model/))
- エラー: `AnalysisError`（ユーザー向け）/ その他例外（サーバー側のバグ）

## なぜ Python (librosa) なのか

| 必要な処理 | あるツール |
|---|---|
| WAV ロード（任意 sr 統一） | `librosa.load` |
| 基音検出 (pyin) | `librosa.pyin` |
| STFT | `librosa.stft` |
| FFT | `numpy.fft` |
| 振幅 RMS | `librosa.feature.rms` |
| スペクトル特徴量 | `librosa.feature.spectral_*` |

これを Processing / C++ で 1 から書くと半年以上。**オフライン処理にリアルタイム制約は無い**
ので最も書きやすい Python を選ぶのが妥当。

## パイプライン全体図

```
 入力 WAV (任意 sr)
    │
    │ ① librosa.load(path, sr=44100, mono=True)
    ▼
 波形 y[]  (44.1 kHz, mono, -1..1)
    │
    │ ② _trim_silence(y)
    │     先頭 -20dB / 末尾 -50dB 以下を無音判定してカット
    ▼
 波形 y[] (トリム後)
    │
    │ ③ librosa.feature.rms(y, frame_length=2048, hop_length=220)
    │     env_hz=200 でサンプリング
    ▼
 全体エンベロープ env[] (200 Hz)
    │
    │ ④ _detect_fundamental(y)
    │     pyin → 失敗時 自己相関
    ▼
 fundamental_hz, f0_track[]
    │
    │ ⑤ _detect_modulation(f0_track, env, 200)
    │     ビブラート (f0 揺れ) と トレモロ (env 揺れ) を別々に検出
    ▼
 modulation (vibrato + tremolo)
    │
    │ ⑥ _fit_adsr(env, 200)
    │     立ち上がり点 → 中盤 → 末尾でフィッティング
    ▼
 attack/decay/sustain/release + loop_start/end
    │
    │ ⑦ _analyze_harmonics(y, steady, f0, n_env)
    │    定常部の長尺 FFT で倍音検出 + STFT で倍音ごとの時間 env
    │    + 非調和性 B のフィット
    ▼
 harmonics[] + inharmonicity_b
    │
    │ ⑧ _analyze_noise(y, f0, harmonics, n_env)
    │     STFT で倍音マスク → 残差 → 帯域別レベル
    ▼
 noise (level, envelope, bands)
    │
    │ ⑨ _extract_one_cycle(steady, f0, sr)
    │     定常部の中央でゼロクロス基準に 1 周期切り出し
    ▼
 waveform.one_cycle[1024]
    │
    │ ⑩ _spectral_features(y, steady)
    │     centroid / rolloff / bandwidth / ZCR / flatness
    ▼
 features (表示用)
    │
    ▼
 instrument dict + preview dict
```

## 解析パラメータ（モジュール冒頭の定数）

`analyzer.py` の 32〜52 行に集中して書いてある:

```python
SR = 44100                       # 内部サンプルレート
ENV_HZ = 200                     # 振幅エンベロープのサンプルレート
ENV_HOP = SR // ENV_HZ           # = 220 サンプル
MAX_HARMONICS = 40               # 取り出す倍音の最大数
HARM_ENV_POINTS = 32             # 倍音ごとの時間エンベロープの点数
ENV_MAX_POINTS = 1200            # 全体エンベロープの最大点数 (≒ 6 秒)
ONE_CYCLE_POINTS = 1024          # 単一周期波形の点数
NOISE_BANDS_HZ = [0, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, SR // 2]
FMIN = 50.0                      # 基音探索の下限
FMAX = 2200.0                    # 基音探索の上限
PYIN_FRAME = 2048                # pyin フレーム長
PYIN_HOP = PYIN_FRAME // 4       # = 512
VIBRATO_BAND_HZ = (3.0, 9.0)     # ビブラート/トレモロの周波数帯
TRIM_LEAD_DB = 20.0              # 先頭の無音閾値 (-20dB)
TRIM_TRAIL_DB = 50.0             # 末尾の無音閾値 (-50dB)
```

各定数の妥当性:

| 定数 | 値 | なぜそれか |
|---|---|---|
| `SR=44100` | 44.1 kHz | Minim / Processing のデフォルトと一致 |
| `ENV_HZ=200` | 200 Hz | エンベロープに 5 ms 解像度。アタックを十分捉える |
| `MAX_HARMONICS=40` | 40 倍音 | 4 kHz 基音まで 16 kHz をカバー (40×400=16000) |
| `HARM_ENV_POINTS=32` | 32 点 | 倍音の時間変化の主要な特徴を捉える |
| `FMIN=50 / FMAX=2200` | 50 Hz〜2.2 kHz | ピアノ A0(27.5) は対象外、ベース〜ソプラノを想定 |
| `VIBRATO_BAND_HZ=(3,9)` | 3〜9 Hz | 人間がビブラートと感じる帯域。研究で言う 4〜8 Hz より広め |

## 各段の役割（リンクと一行サマリ）

| # | 関数 | 役割 | 詳細ページ |
|---|---|---|---|
| ① | `librosa.load` | 任意フォーマット → 44.1 kHz mono float | — |
| ② | `_trim_silence` | 先頭・末尾の無音とルームトーンを除去 | [基音検出ページ](/pc-audio/analyzer-modulation/#トリム) |
| ③ | `librosa.feature.rms` | 振幅エンベロープを 200 Hz で取る | [基音検出ページ](/pc-audio/analyzer-modulation/#全体振幅エンベロープ) |
| ④ | `_detect_fundamental` | pyin → 自己相関の 2 段で基音検出 | [基音検出ページ](/pc-audio/analyzer-modulation/#基音検出) |
| ⑤ | `_detect_modulation` | f0 と env の周期成分から揺れを判定 | [基音検出ページ](/pc-audio/analyzer-modulation/#ビブラートトレモロ) |
| ⑥ | `_fit_adsr` | 振幅エンベロープに ADSR + ループ点を当てはめ | [基音検出ページ](/pc-audio/analyzer-modulation/#adsr-当てはめ) |
| ⑦ | `_analyze_harmonics` | 倍音 + 倍音 env + 非調和性 B | [倍音ページ](/pc-audio/analyzer-harmonics/#倍音抽出) |
| ⑧ | `_analyze_noise` | 倍音マスク後の残差からノイズ抽出 | [倍音ページ](/pc-audio/analyzer-harmonics/#残差ノイズ) |
| ⑨ | `_extract_one_cycle` | 定常部から 1 周期を取り出す | このページ末尾 |
| ⑩ | `_spectral_features` | 表示用の特徴量 | このページ末尾 |

## 解析の順序が決まる理由

順序を入れ替えると壊れる:

1. **トリム → エンベロープ**: トリム前にエンベロープを取ると無音区間が ADSR フィットを
   歪める
2. **エンベロープ → 基音**: 基音検出には全長の信号が必要（pyin は短すぎると失敗）
3. **基音 → ADSR**: 基音検出は ADSR には依存しないので順序自由だが、ADSR の `loop_start_sec`
   を倍音解析の窓に使うのでこの順
4. **ADSR → 倍音**: `loop_start_sec` 〜 `loop_end_sec` を **定常部** として倍音解析に使う
5. **倍音 → ノイズ**: ノイズは「倍音以外」なので倍音マスクが先に要る

## 定常部の切り出し

倍音解析で **どこを「楽器の本体の音色」とみなすか** が重要。アタック中は倍音バランスが
不安定なので、サステインっぽい区間を使う:

```python
a_idx = int(round(adsr["loop_start_sec"] * ENV_HZ))
b_idx = int(round(adsr["loop_end_sec"] * ENV_HZ))
a_samp = max(0, a_idx * ENV_HOP)
b_samp = min(y.size, max(a_samp + 4096, b_idx * ENV_HOP))
steady = y[a_samp:b_samp]
if steady.size < 4096:                # 短ければアタック直後を使う
    peak_samp = int(np.argmax(np.abs(y)))
    steady = y[peak_samp:peak_samp + max(4096, int(0.3 * SR))]
if steady.size < 2048:
    steady = y                        # 最終フォールバック
```

ロジック:

1. 第一候補は **ADSR の loop 区間**（中盤の 0.30〜0.70 のサステイン窓）
2. それが短すぎたら **ピーク直後 0.3 秒**
3. それでも短ければ **全長**

これで打楽器のような短い音から弦楽器の長いサステインまで自動対応する。

## 単一周期波形（任意）

`waveform.one_cycle` は **将来ウェーブテーブル方式に切替えたい時** のための予備データ。
Processing 現行版は使っていない（加算合成だけで合成）。

```python
def _extract_one_cycle(steady, f0, sr):
    period = sr / f0          # 1 周期のサンプル数
    mid = steady.size // 2
    # 中央付近で上昇ゼロクロスを探す
    for i in range(mid - period, mid + period):
        if steady[i] <= 0 < steady[i+1]:
            zc = i
            break
    seg = steady[zc:zc + int(round(period))]
    cyc = _resample_curve(seg, ONE_CYCLE_POINTS)   # 1024 点に揃える
    return cyc / max(abs(cyc))                     # -1..1 に正規化
```

**1024 点に揃える** ことで、ピッチが違う音同士でも同じテーブルで補間読み出しできる。

## 表示用特徴量

合成には使わないが、解析結果の品質を見るための数値:

```python
features = {
    "spectral_centroid_hz":  ...,   # スペクトル重心
    "spectral_rolloff_hz":   ...,   # 85% エネルギーがある周波数
    "spectral_bandwidth_hz": ...,   # スペクトルの広がり
    "zero_crossing_rate":    ...,   # 零交差率（ノイジーさの目安）
    "spectral_flatness":     ...,   # 周波数分布の平坦さ（白色ノイズ＝1）
    "rms_peak":              ...,
    "harmonic_count":        ...,   # amp>0 の倍音の個数
    "source_duration_sec":   ...,   # トリム前の長さ
    "trimmed_lead_sec":      ...,
    "trimmed_trail_sec":     ...,
}
```

これらは **ブラウザ UI に表示** されて、解析結果の妥当性を視覚的に確認するため。

## サーバー側 (app.py)

`analyze_file` を Flask で包んだだけ。

```
GET  /                  → static/index.html
GET  /static/<path>     → static/<path>
GET  /samples/<f>       → analyzer/samples/<f>   (動作確認用)
POST /analyze           → multipart/form-data: file=<wav> → JSON
```

- アップロード上限 32 MB
- 対応拡張子: wav / flac / ogg / mp3 / aiff / aif / m4a
- 5005 番ポート、起動時にブラウザを自動で開く

これで **ローカル Web アプリ** として完結。チームメンバーが Python を知らなくても
ブラウザでドラッグ＆ドロップして解析できる。

## 解析にかかる時間

M1 Mac 標準環境での実測（2 秒の単音 WAV）:

| 段 | 所要時間 |
|---|---|
| librosa.load | ≈ 30 ms |
| pyin | ≈ 600 ms |
| RMS / ADSR | ≈ 10 ms |
| 倍音解析 (FFT + STFT) | ≈ 200 ms |
| ノイズ | ≈ 150 ms |
| 周期切り出し / 特徴量 | ≈ 50 ms |
| **合計** | **≈ 1 秒** |

リアルタイムには遠いが、**1 ファイル 1 秒** ならブラウザ UI で十分快適。

## どこを書き換えるか

| やりたいこと | 触る場所 |
|---|---|
| 別言語に移植したい | パイプライン全体を **同じ順** で書き直し、JSON フォーマットを揃える。FFT/STFT は scipy / FFTW / KissFFT 等で代替 |
| pyin の代わりに別の基音検出 | `_detect_fundamental` の中身を差し替え（CREPE、YIN、SWIPE 等） |
| 倍音数を増やす | `MAX_HARMONICS` を上げる。FFT のビン幅が足りなければ `nfft` も上げる |
| ノイズの帯域分割を細かく | `NOISE_BANDS_HZ` を増やす。`InstrModel` 側のロードは変更不要（配列で持つので） |
| MIDI 化したい（音符列） | 全長を pyin で追って音符切り出し → 別フォーマット。`analyzer.py` とは別ツールに |

## 次のページ

- 倍音まわりの数学を詳しく → [倍音抽出・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/)
- 基音検出と揺れ検出を詳しく → [基音検出・ADSR・ビブラート](/pc-audio/analyzer-modulation/)
- 解析の JSON を使う側 → [音色定義モデル（InstrModel）と JSON](/pc-audio/instr-model/)
