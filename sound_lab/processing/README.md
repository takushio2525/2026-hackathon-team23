# processing — 解析結果を読み込んで再合成する Processing スケッチ

[`../analyzer`](../analyzer) が出力したインストゥルメント定義 JSON（→ [`../library_format.md`](../library_format.md)）を
読み込み、音程と長さを与えると「限りなく元に近い音」を鳴らす。

| サブディレクトリ | 内容 |
|---|---|
| `instrument_player/` | 1 つの音色定義を読み込んで演奏するスケッチ（Minim 使用、鍵盤 UI 付き） |

## 必要なもの

- [Processing IDE](https://processing.org/download)（最新版）
- Minim ライブラリ（Processing IDE の `スケッチ → ライブラリをインポート → ライブラリを追加` で `Minim` を入れる）

## 使い方

1. `sound_lab/analyzer` で楽器音を解析し、`<名前>.instrument.json` をダウンロード
2. それを `instrument_player/data/instrument.json` という名前でコピー
   （`instrument.json` が無ければサンプルの `example_organ.json` が読まれる）
3. Processing IDE で `instrument_player/instrument_player.pde` を開いて Run
4. 画面の鍵盤をクリック、または PC キーボードで演奏する

### キーボード操作

| キー | 動作 |
|---|---|
| `z s x d c v g b h n j m` | 下段の鍵盤（左端オクターブ） |
| `q 2 w 3 e r 5 t 6 y 7 u i` | 上段の鍵盤（その 1 オクターブ上） |
| ↑ / ↓ | オクターブを上下に移動 |
| ← / → | 発音長を ±0.1 秒 |
| `o` | 別のインストゥルメント JSON を選び直す |
| `r` | 現在の JSON を再読込（解析し直したものを反映） |
| `a` | 振幅包絡の方式切替（実エンベロープ ↔ ADSR 4 値） |
| Space | 鳴っている音を全部止める |

## 合成方式（`instrument_player.pde`）

- **加算合成**: 倍音ごとに `振幅 × 時間エンベロープ` を持つサイン波を合成。周波数は
  `f_n = n·f0·√(1 + B·n²)`（非調和性 B を反映）。総和は `1/Σ振幅` で正規化。
- **全体振幅エンベロープ**: JSON の `envelope.values[]` をそのまま使い、要求された発音長に合わせて
  `[0, loop_start]` → `[loop_start, loop_end]` をループ → 末尾 `release` 区間、と**時間ワープ**する。
  減衰音（`sustaining=false`）はループせず、原音より長ければ鳴らし切り、短ければ末尾フェード。
- **ノイズ**: 白色ノイズを `noise.band_levels` の形に FFT 整形したループバッファを起動時に 1 本作り、
  `noise.level × noise.envelope(t)` を掛けて加算合成に足す（アタックのノイズバースト等）。
- 画面上部には読み込んだ定義の振幅エンベロープと倍音バーを表示するので、`r` で解析し直しながら詰められる。

## 本番システムへの組み込み

チームの本番（`pc_app/test/orchestra_player`）は今サイン波で鳴らしている。`ResynthVoice` と
`InstrModel` をそちらに移植し、受信した `noteNumber` / `durationMs` を `playNote()` に渡せば、
楽器ノードごとに本物の音色で鳴らせる。`InstrModel` は Minim 非依存の素の配列なので移植は容易。
