# instrument_player — 音色定義 JSON を読んで演奏する Processing スケッチ

`data/instrument.json`（無ければ `data/example_organ.json`）を読み込み、鍵盤や PC キーボードで
音程と発音長を与えると、加算合成 + 非調和性 + 整形ノイズ + 時間ワープした振幅エンベロープで鳴らす。

操作・合成方式の詳細は親ディレクトリの [`../README.md`](../README.md) を参照。

## 構成

| パス | 内容 |
|---|---|
| `instrument_player.pde` | スケッチ本体（`InstrModel` = JSON → 配列、`ResynthVoice extends UGen` = 1 音ぶんのボイス） |
| `data/instrument.json` | 読み込む音色定義（`analyzer` でダウンロードしたものをこの名前で置く） |
| `data/example_organ.json` | 起動確認用サンプル（手書き。解析結果ではない。消してよい） |
| `sketch.properties` | Processing のモード設定（Java） |

## 実行

1. Processing IDE で Minim ライブラリを入れる
2. `instrument_player.pde` を開いて Run
3. 何も置いていなくても `example_organ.json` で音が出る。`sound_lab/analyzer` で作った JSON を
   `data/instrument.json` に置き直し（または実行中に `o` キーで選択）、`r` キーで再読込

## トラブルシュート

- 音が出ない → Minim が入っているか、`スケッチ → ライブラリをインポート` に Minim があるか確認
- `data/ に … がありません` と出る → `o` キーで JSON を選ぶか、`data/instrument.json` を置く
- 音が割れる → 画面下の発音長スライダーを短くする / 同時押し数を減らす（ボイスごとに振幅は
  `1/Σ倍音振幅` で正規化しているが、多重和音では合算で歪むことがある）
- 音が「のっぺり」する → `a` キーで実エンベロープ側になっているか確認（ADSR 4 値モードだと簡略化される）
