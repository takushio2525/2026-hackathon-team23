# processing — 解析結果を読み込んで再合成する Processing スケッチ

[`../analyzer`](../analyzer) が出力したインストゥルメント定義 JSON（→ [`../library_format.md`](../library_format.md)）を
読み込み、音程を与えると「限りなく元に近い音」を鳴らす。鍵盤は **押している間ずっと鳴り、離すとリリース**。

| サブディレクトリ | 内容 |
|---|---|
| `instrument_player/` | 1 つの音色定義を読み込んで演奏するスケッチ（Minim 使用、鍵盤 UI・きらきら星再生ボタン付き） |
| `frog_song_player/` | 改善版test_multiのトランペット＋ホルンで「かえるのうた」を演奏するスケッチ |

## 必要なもの

- [Processing IDE](https://processing.org/download)（最新版）
- Minim ライブラリ（Processing IDE の `スケッチ → ライブラリをインポート → ライブラリを追加` で `Minim` を入れる）

## 使い方

1. `sound_lab/analyzer` で楽器音を解析し、`<名前>.instrument.json` をダウンロード（複数 OK）
2. それらを **`instrument_player/data/` フォルダにそのまま放り込む**
   （ファイル名は何でもよい。`*.json` を全部自動で見つけ、起動時は最後に更新された実音色JSONを選ぶ）
3. Processing IDE で `instrument_player/instrument_player.pde` を開いて Run
4. 画面下の **インストゥルメント一覧をクリック**（または `[` / `]` キー）で音色を切り替えながら、鍵盤を
   クリック / PC キーボードで **押している間** 鳴らす。`▶ きらきら星` ボタン（または `p` キー）でデモ演奏。
   解析し直して上書きしたら `r` で再スキャン＋再読込

### キーボード操作

| キー | 動作 |
|---|---|
| `z s x d c v g b h n j m` | 下段の鍵盤（左端オクターブ）。**押している間 鳴り、離すとリリース** |
| `q 2 w 3 e r 5 t 6 y 7 u i` | 上段の鍵盤（その 1 オクターブ上）。複数同時押し可 |
| `p` | きらきら星（ド ド ソ ソ ラ ラ ソ）を再生（画面のボタンと同じ） |
| `[` / `]` | インストゥルメントを前 / 次へ切替（一覧クリックでも切替可） |
| ↑ / ↓ | 鍵盤のオクターブを上下に移動（押しっぱなしの鍵はいったん離される） |
| `o` | `data/` 以外の場所にある JSON を選ぶ |
| `r` | `data/` を再スキャンして現在の JSON を再読込（解析し直したものを反映） |
| `l` | 改善版 / 旧test_multi互換（固定倍音 + 線形ADSR）を切替 |
| `a` | 振幅包絡の方式切替（ADSR 4 値 ↔ 実エンベロープ） |
| `Shift+H` / `Shift+N` / `Shift+E` | 倍音ごとの立ち上がり / 残差ノイズ / ボディEQ・管共鳴を切替 |
| Space | 鳴っている音を全部止める |

マウスでも鍵盤をクリックしている間 鳴り、ボタンを離すとリリースする。

## 発音モデルと合成方式（`instrument_player.pde`）

- **ゲート方式**: 既定では改善版と同じ `attack_sec / decay_sec / sustain_level / release_sec` の線形ADSR。
  `a` キーで解析した `envelope.values[]` のループ再生とも比較できる。途中で離せばその時点からリリースする。
- **加算合成**: 倍音ごとに `振幅 × 立ち上がりenv` を持つサイン波を合成し、立ち上がり後はループ域平均で安定させる。周波数は
  `f_n = n·f0·√(1 + B·n²)`（非調和性 B を反映）。総和は `1/Σ振幅` で正規化。
- **ノイズ**: 白色ノイズを `noise.band_levels` の形に FFT 整形したループバッファを音色読み込み時に作り、
  `noise.level × noise.envelope(t)` を掛けて加算合成に足す。`fx.noise_mode`、HP/LP、アタック強調、連続息も反映する。
- **原音レイヤー**: `attack_sample`、`sustain_sample`、`drum_sample` を各 `sample_rate` / `root_midi_note` と
  `fx.*_sample_mix` に従って再生する。ドラムの鍵盤追従は `fx.drum_pitch_follow` で切り替える。
- **FX**: `fx.body_eq`、管共鳴、drive、filter、chorus、reverb を適用。移調・fine tune・humanize・glide も反映する。
- **ビブラート / トレモロ**: JSON に `modulation`（解析器が検出 or ブラウザ編集スタジオで設定）があれば、各倍音の周波数に
  指定した sine / triangle / sawtooth / square 波形でピッチと振幅を変調する。
  `modulation` が無い古い JSON は従来どおり（揺れなし）。
- 画面上部には読み込んだ定義の振幅エンベロープ（ループ区間／リリース尾も色分け）と倍音バーを表示するので、
  `r` で解析し直しながら詰められる。`data/` 内の `*.json` は起動時に全部スキャンして一覧表示、`[` / `]` で即切替。
- きらきら星シーケンサ: `SONG_NOTES` / `SONG_BEATS` / `songBeatMs` を書き換えれば任意のメロディに変えられる。

## 他システムへの組み込み

`pc_app/test_v2/orchestra_resynth`（きらきら星 輪唱の PC 側）は、ここの `ResynthVoice` /
`InstrModel` を移植して、NOTE パケット受信時に音色定義（`data/*.json`、Arduino が送る楽器番号で選択）
で発音 → `durationMs` 経過で自動 release、という形で実際に使っている。`pc_app/test_v1/orchestra_player`
はまだサイン波。`InstrModel` は Minim 非依存の素の配列なので移植は容易。
