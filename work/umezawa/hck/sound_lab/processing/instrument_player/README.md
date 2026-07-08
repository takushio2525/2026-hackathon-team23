# instrument_player — 音色定義 JSON を読んで演奏する Processing スケッチ

`data/` フォルダにある `*.json` をすべて読み込み、画面下の一覧（クリック or `[` / `]` キー）で
音色を切り替えながら、鍵盤や PC キーボードを **押している間** 鳴らす（離すとリリース）。
起動時は `example_organ.json` を除く、最後に更新されたJSONを自動選択する。
`▶ きらきら星` ボタン（または `p` キー）で「ド ド ソ ソ ラ ラ ソ」のデモ演奏もできる。
`sound_lab.instrument/1` の音響仕様に対応し、ADSR／実包絡、動的倍音、非調和性、整形ノイズ、
埋め込み原音サンプル、変調と `fx`（EQ、管共鳴、drive、filter、chorus、reverb、glide）を再生する。
古い JSON に新項目が無い場合は既定値で素通しになる。
画面の「旧test_multiで聞く」ボタン（または `l` キー）で、同じJSONを現行 `pc_app/test_multi` 相当の
固定倍音 + 線形ADSRだけでも再生できる。

操作・発音モデル・合成方式の詳細は親ディレクトリの [`../README.md`](../README.md) を参照。

## 構成

| パス | 内容 |
|---|---|
| `instrument_player.pde` | スケッチ本体（`InstrModel` = JSON → 配列、`ResynthVoice extends UGen` = 1 音ぶんのボイス、`data/*.json` 一覧 UI） |
| `data/` | 音色定義 JSON 置き場。ここに入れた `*.json` を起動時に全部スキャンする |
| `data/example_organ.json` | 起動確認用サンプル（手書き。解析結果ではない。消してよい） |
| `sketch.properties` | Processing のモード設定（Java） |

## 実行

1. Processing IDE で Minim ライブラリを入れる（`スケッチ → ライブラリをインポート → ライブラリを追加`）
2. `sound_lab/analyzer` で作った `*.instrument.json` を `data/` フォルダに放り込む（複数 OK・名前は任意）
3. `instrument_player.pde` を開いて Run
4. 鍵盤を押している間 鳴る（離すとリリース）。`▶ きらきら星` ボタンや `p` でデモ。画面下の一覧をクリック
   （または `[` / `]`）で音色を切替。何も置かなくても `example_organ.json` で音は出る。
   解析し直して上書きしたら `r` で再スキャン＋再読込。`data/` 以外の場所にある JSON は `o` で選択

## 改善版との聴き比べ

既定では改善版と同じADSR4値モードで鳴る。次のキーで要素ごとにON/OFFして差を確認できる。

| キー | 内容 |
|---|---|
| `l` | 改善版 / 旧test_multi互換（固定倍音 + 線形ADSR）を一括切替 |
| `a` | ADSR4値 / 解析した実エンベロープ |
| `Shift+H` | 倍音ごとの立ち上がり |
| `Shift+N` | 残差ノイズ |
| `Shift+E` | ボディEQ・管共鳴 |
| `r` | data再スキャン・現在のJSON再読込 |
| `Space` | 全停止 |

## トラブルシュート

- 音が出ない → Minim が入っているか、`スケッチ → ライブラリをインポート` に Minim があるか確認
- 音が止まらない（鍵が押しっぱなしのまま）→ Space で全停止。オクターブ変更（↑↓）は押している鍵を自動で離す
- 一覧に出ない → 拡張子が `.json` か確認 → `r` キーで再スキャン（ファイル追加直後に押す）
- `data/ に .json がありません` と出る → `data/` に JSON を置いて `r`、または `o` キーで選ぶ
- 音が割れる → 同時に押す数を減らす（ボイスごとに振幅は `1/Σ倍音振幅` で正規化しているが、多重和音では
  合算で歪むことがある）
- 改善版と音が違う → 上部表示が `包絡 ADSR4値 / H:ON N:ON E:ON` か確認
- 現行 `pc_app/test_multi` と比べたい → 「旧test_multiで聞く」または `l` を押し、上部の `再生 旧test_multi` を確認
