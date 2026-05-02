# pc_app — PC 側サブシステムの置き場（例）

このディレクトリは「**PC 側で動くサブシステムをリポジトリに同梱したいとき**」の例。
サンプルとして [Processing](https://processing.org/) のスケッチを置いているが、
中身は自分たちの技術スタックに合わせて自由に差し替えてよい。

ディレクトリ名も用途に合わせてリネーム可能
（例: `viewer/`, `desktop_app/`, `web/`, `frontend/` など）。

## こんなときに使う

- マイコンから PC へシリアルでデータを送って可視化したい
- PC 側で音・映像を生成したい
- 操作用の GUI を作りたい
- Web フロントエンドやデスクトップアプリを同梱したい

## 構成

| ディレクトリ | 内容 |
|---|---|
| `example_sketch/` | 最小の Processing スケッチ（書き方のサンプル） |

## サンプルの実行方法（Processing の場合）

1. [Processing IDE](https://processing.org/download) をインストールする
2. `example_sketch/example_sketch.pde` を Processing IDE で開く
3. 「Run」ボタンを押す

> Processing 以外（Python / Unity / Electron 等）を使う場合は、
> `example_sketch/` を削除して自分たちのプロジェクトを配置する。

## スケッチを追加する（Processing 固有）

Processing のお約束として、スケッチのフォルダ名と `.pde` のファイル名は
**同じ名前**にする必要がある。

```
pc_app/
└── my_sketch/
    └── my_sketch.pde   # フォルダと同じ名前
```

## 不要な班は

`pc_app/` ディレクトリを丸ごと削除してよい。
