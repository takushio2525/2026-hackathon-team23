# lualatex でのビルド設定
$pdf_mode = 4;          # 4 = lualatex
$lualatex = 'lualatex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$max_repeat = 5;
$clean_ext = 'synctex.gz synctex.gz(busy) run.xml tex.bak bbl bcf fdb_latexmk run.tdo';
