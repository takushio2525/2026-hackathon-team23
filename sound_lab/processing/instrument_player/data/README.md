# data/ — インストゥルメント定義の置き場

Processing スケッチが起動時に読み込む JSON をここに置く。

- `instrument.json` … スケッチが最優先で読む名前。`sound_lab/analyzer` で解析して
  ダウンロードした `<名前>.instrument.json` を、このファイル名にリネームしてコピーする。
- `example_organ.json` … `instrument.json` が無いときに読まれるサンプル（手書き。解析結果ではない）。
  起動確認用なので消しても構わない。

スケッチ実行中に `o` キーを押せば、ここ以外の場所にある JSON も選び直せる。

フォーマット仕様: [`../../../library_format.md`](../../../library_format.md)
