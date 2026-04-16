# lectures — 授業資料の置き場

授業で配布された資料（PDF・スライド・補足プリント等）をここに置く。

## 命名規則

日付・回次・トピックが分かるファイル名にする。

```
YYYY-MM-DD_lecNN_<topic>.pdf
```

例：

```
2026-04-10_lec01_intro.pdf
2026-04-17_lec02_arduino_basics.pdf
2026-04-24_lec03_wifi_comm.pdf
```

補助資料（サンプルコード・配布データ）はトピックごとにサブフォルダを切ってもよい：

```
lectures/
├── 2026-04-10_lec01_intro.pdf
└── 2026-04-17_lec02_arduino_basics/
    ├── slides.pdf
    └── sample_code.ino
```

## 著作権の扱い

**授業資料は教員・大学の著作物**である可能性が高い。

- **Public リポジトリには絶対に push しない**
- Public 運用なら、ルートの `.gitignore` に次を追記して除外する：

  ```
  references/lectures/*
  !references/lectures/README.md
  !references/lectures/.gitkeep
  ```

- 資料本体は、チーム内の別手段（Google Drive・Slack 等）で共有する

Private リポジトリで、かつチーム内利用に限定する場合のみコミットしてよい。
判断に迷ったら、**コミットする前に**チームで相談すること。

## 不要な班は

このディレクトリごと削除してよい。
