# sound_lab — 楽器音の解析 → 再現合成 実験場

楽器の音源ファイル（`.wav` / `.flac` / `.ogg` / `.mp3` など）を渡すと、

1. **Python で徹底解析**（基音・ADSR・倍音列・倍音ごとの時間変化・残差ノイズ・非調和性・単一周期波形 …）
2. その結果を **インストゥルメント定義（JSON）** として書き出し、
3. **Processing でその JSON を読み込み**、音程と長さを外から与えると「限りなく元に近い音」を鳴らす、

という一連の流れを試すためのディレクトリ。チームの本番システム（`pc_app/test/orchestra_player`）が
今はサイン波で鳴らしているのを、ここで作った音色定義に差し替えるための土台でもある。

> このフォルダはあくまで実験・検証用。本番に組み込まないなら丸ごと削除して構わない。

## 構成

| パス | 内容 |
|---|---|
| [`analyzer/`](analyzer/) | 解析ツール本体。バックエンド = Python（`librosa` で解析）、フロント = HTML（ブラウザでアップロード → 可視化 → JSON ダウンロード） |
| [`processing/instrument_player/`](processing/instrument_player/) | 生成した JSON を読み込んで加算合成 + ADSR + 整形ノイズで鳴らす Processing スケッチ（Minim 使用、鍵盤 UI 付き） |
| [`library_format.md`](library_format.md) | インストゥルメント定義 JSON のフォーマット仕様 |

## クイックスタート

```bash
# 1) 解析ツールを起動（初回のみ依存インストール）
cd sound_lab/analyzer
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py
#   → ブラウザで http://127.0.0.1:5005 を開く
#   → 楽器の単音ファイルをドロップ → 「解析」→ 波形/スペクトル/ADSR を確認 → 「JSON をダウンロード」

# 2) ダウンロードした JSON を Processing に渡す
cp ~/Downloads/piano_C4.instrument.json sound_lab/processing/instrument_player/data/instrument.json
#   → Processing IDE で instrument_player/instrument_player.pde を開いて Run
#   → 画面の鍵盤をクリック or PC キーボードで演奏。'o' キーで別の JSON を選び直せる
```

詳しい手順は各サブディレクトリの README を参照。

## 解析の入力について

- **1 音だけ**を録った（または切り出した）ファイルを渡すこと。和音やフレーズだと基音検出が破綻する
- 余分な無音は自動でトリムするが、アタック頭が削れない程度に録っておくと精度が上がる
- サンプルレートは内部で 44.1 kHz に統一される
