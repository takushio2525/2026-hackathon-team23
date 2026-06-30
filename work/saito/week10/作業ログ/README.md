# 作業ログ

今回の作業ログを作成するためのフォルダです。

- `作業ログ_25G1053.tex`: 今回の作業内容を記載したLaTeXファイルです。
- `作業ログ_25G1053.pdf`: 提出・確認用に生成したPDFです。
- `Figs/`: 作業ログに掲載する図を置くフォルダです。
- PDFを生成する場合は、作業ログフォルダで `latexmk 作業ログ_25G1053.tex` を実行します。`.latexmkrc` により、uplatexとdvipdfmxが自動的に使われます。
- 以前の作業ログと同じ体裁を保つため、`geometry`、`array`、`tabularx`、`booktabs`、`enumitem`、`graphicx`、`titlesec` を使用しています。

不要になった場合は削除して構いません。
