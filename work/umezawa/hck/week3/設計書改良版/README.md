# 設計書改良版

`orchestra_processing_final` の実装内容に合わせて更新した Processing 音源サブシステムの設計書です。

## 旧設計書からの主な変更

- Serial ポート選択を番号キー方式からクリック方式へ更新
- `serialEvent()` で直接発音せず、受信キューに積んで `draw()` 側で処理する方式を追加
- `seq` を partId ごとに管理する設計へ更新
- 実装済みフォルダ `orchestra_processing_final` のファイル構成に合わせて更新
- 金管3パート + リズム1パートとして音色設計を整理
- ルーブリック5項目への対応表を明確化

## 成果物

- `plan_25G1021_improved.tex`: LaTeX ソース
- `plan_25G1021_improved.pdf`: 提出確認用 PDF
