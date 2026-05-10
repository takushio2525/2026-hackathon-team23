# analyzer — 音源解析ツール(Python バックエンド + HTML フロント)

楽器の **単音** 音源を 1 ファイル渡すと、Python (`librosa`) で徹底的に解析し、
[`../library_format.md`](../library_format.md) のインストゥルメント定義 JSON を出力する。
フロントはブラウザ 1 枚（`static/index.html`）。アップロード → 波形 / スペクトル / ADSR / 倍音を可視化
→ ブラウザ内で試聴 → JSON をダウンロード、までできる。

> 解析ロジック本体は [`analyzer.py`](analyzer.py)。サーバを介さず単体でも使える
> （`from analyzer import analyze_file` → `analyze_file("note.wav")` が dict を返す）。

## セットアップ & 起動

### いちばん簡単（macOS）

`sound_lab/analyzer/start.command` を **Finder でダブルクリック**。初回だけ仮想環境の作成と依存
インストール（librosa を含むため数分）が走り、起動後はブラウザが自動で `http://127.0.0.1:5005`
を開く。止めるときはそのターミナルウィンドウで `Ctrl+C`。

> 「開発元を確認できません」と出たら、ファイルを右クリック →「開く」→「開く」で一度許可すればよい。

### 手動（macOS / Linux / Windows 共通）

```bash
cd sound_lab/analyzer
python3 -m venv .venv
source .venv/bin/activate           # Windows: .venv\Scripts\activate
pip install -r requirements.txt     # librosa を含むため初回は数分かかる
python app.py                       # 起動するとブラウザが自動で開く
# 開かなければ http://127.0.0.1:5005 を手で開く
```

`mp3` / `m4a` を読むには ffmpeg が必要（`brew install ffmpeg`）。`wav` / `flac` なら追加不要。

> **「通信エラー: Failed to fetch」と出るとき** … サーバ（`python app.py` または `start.command`）が
> 起動していない、もしくは HTML ファイルを直接ダブルクリックして `file://` で開いている。必ず
> `http://127.0.0.1:5005` から開くこと。HTML 側にも同じ案内が出る。

## 使い方

1. ブラウザで `http://127.0.0.1:5005`
2. 楽器の単音ファイル（`.wav` 推奨。`.flac/.ogg/.mp3/.aiff/.m4a` も可、〜32 MB）をドロップ
3. 「解析」を押す → 検出した基音・MIDI ノート・ADSR・倍音数などが表示され、
   波形・対数スペクトル（倍音マーカー付き）・振幅エンベロープ・倍音バーが描画される
4. 「ブラウザで試聴」で、解析結果をその場で加算合成して鳴らせる（音程・長さスライダー付き）。
   元音と聴き比べて納得したら…
5. 「インストゥルメント JSON をダウンロード」→ `<名前>.instrument.json` が落ちる
6. その JSON を `../processing/instrument_player/data/instrument.json` に置けば Processing で鳴る

## 解析でやっていること（`analyzer.py`）

| 項目 | 手法 |
|---|---|
| 基音検出 | `librosa.pyin`（有声フレームの中央値）。失敗時は振幅最大付近の自己相関にフォールバック |
| 振幅エンベロープ | フレーム RMS（200 Hz 解像度）をピーク 1.0 で正規化 |
| ADSR + ループ点 | エンベロープのピーク位置・10%/5% 交差・中盤レベルから A/D/S/R とループ区間を当てはめ |
| 倍音列 | 定常部の長尺ゼロ詰め FFT で `n·f0` 近傍（±3.5%）のピークを抽出（放物線補間で周波数微修正）。振幅・位相・実周波数比 |
| 倍音ごとの時間変化 | STFT（n\_fft=8192）で各倍音ビンのマグニチュード推移を 32 点に圧縮 |
| 非調和性 B | 検出倍音の実周波数を `f_n ≈ n·f0·√(1+B·n²)` に振幅重み付き最小二乗フィット |
| 残差ノイズ | STFT 上で倍音まわりのビンをマスク → 残差の RMS から レベル・時間包絡、平均スペクトルを 9 帯域に集約して色（息/弓/打撃ノイズなど） |
| 単一周期波形 | 定常部の立ち上がりゼロクロスから 1 周期を切り出し 1024 点にリサンプル（ウェーブテーブル用） |
| 特徴量（表示用） | スペクトル重心・ロールオフ・帯域幅・ゼロ交差率・スペクトル平坦度 |

## 入力のコツ

- **必ず 1 音だけ**。和音・フレーズ・残響まみれの録音は基音検出が破綻する
- アタックの頭が切れていないファイルを渡す（前後の無音は自動トリムする）
- サンプルレートは内部で 44.1 kHz に統一されるので元は何でもよい
- うまく基音が取れないときは、`analyzer.py` の `FMIN` / `FMAX` を楽器の音域に合わせて狭める

## ディレクトリ

| パス | 内容 |
|---|---|
| `start.command` | macOS 用ワンクリック起動（venv 自動作成 → サーバ起動 → ブラウザを開く） |
| `app.py` | Flask サーバ（`/`, `/analyze`, `/samples/<f>`。起動時にブラウザを自動で開く） |
| `analyzer.py` | 解析ロジック本体（サーバ非依存） |
| `static/index.html` | フロント（単一 HTML、外部依存なし） |
| `samples/` | 動作確認用の音源置き場（中身は任意。`/samples/<ファイル名>` で配信） |
| `requirements.txt` | Python 依存 |

不要になったら `sound_lab/` ごと削除して構わない。
