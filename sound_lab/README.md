# sound_lab — 楽器音の解析 → 編集 → 再現合成 実験場

楽器の音源ファイル（`.wav` / `.flac` / `.ogg` / `.mp3` など）を渡すと、

1. **Python で徹底解析**（基音・ADSR・倍音列・倍音ごとの時間変化・残差ノイズ・非調和性・ビブラート/トレモロ・単一周期波形 …）
2. **ブラウザのスタジオで鳴らしながら編集**（ビブラートを足す/消す・倍音バランス・息っぽいノイズ・響き・ドライブ/コーラス/フィルタ/EQ …）
3. その結果を **インストゥルメント定義（JSON）** や **WAV** として書き出し、
4. **Processing でその JSON を読み込み**、音程と長さを外から与えると「限りなく元に近い（あるいは作り込んだ）音」を鳴らす、

という一連の流れを試すためのディレクトリ。ここで作った音色定義（`*.instrument.json`）は
`pc_app/test_v2/orchestra_resynth`（きらきら星 輪唱の PC 側）で実際に使われている
（`data/*.json` に置き、Arduino が送る楽器番号で選んで合成する）。`pc_app/test_v1/orchestra_player`
はまだサイン波で鳴らしている。

> このフォルダはあくまで実験・検証用。本番に組み込まないなら丸ごと削除して構わない。

## 構成

| パス | 内容 |
|---|---|
| [`analyzer/`](analyzer/) | 解析ツール + 編集スタジオ。バックエンド = Python（`librosa` で解析）、フロント = ブラウザ（アップロード → 可視化 → **鳴らしながら音色編集** → 調整後 JSON / WAV を書き出し。原音 A/B 付き） |
| [`processing/instrument_player/`](processing/instrument_player/) | `data/` に入れた JSON を全部読み込み、一覧から音色を切り替えながら加算合成 + 整形ノイズ + ADSR + ビブラート/トレモロ で鳴らす Processing スケッチ（Minim 使用。鍵盤は押している間 鳴る／きらきら星 再生ボタン付き） |
| [`library_format.md`](library_format.md) | インストゥルメント定義 JSON のフォーマット仕様（`modulation` / `fx` 含む） |

## クイックスタート

```bash
# 1) 解析ツール + 編集スタジオを起動（macOS は sound_lab/analyzer/start.command をダブルクリックでも可）
cd sound_lab/analyzer
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py
#   → ブラウザが自動で http://127.0.0.1:5005 を開く
#   → 楽器の単音ファイルをドロップ → 自動で解析 → 波形/スペクトル/ADSR/ピッチ揺れ を確認
#   → スタジオで「🔁 鳴らしっぱなし」にして各スライダーをいじる（即反映） → 「調整後 JSON / WAV」を書き出し

# 2) 書き出した JSON を Processing の data/ に放り込む（複数 OK・名前は任意）
cp ~/Downloads/*.instrument.json sound_lab/processing/instrument_player/data/
#   → Processing IDE で instrument_player/instrument_player.pde を開いて Run
#   → 画面下の一覧をクリック（または [ / ] キー）で音色を切替。鍵盤は押している間 鳴る（離すとリリース）。
#      ▶ きらきら星 ボタンや 'p' キーでデモ演奏。 JSON を足したら 'r' で再スキャン
```

詳しい手順は各サブディレクトリの README を参照。

## 解析の入力について

- **1 音だけ**を録った（または切り出した）ファイルを渡すこと。和音やフレーズだと基音検出が破綻する
- 余分な無音は自動でトリムするが、アタック頭が削れない程度に録っておくと精度が上がる
- サンプルレートは内部で 44.1 kHz に統一される
