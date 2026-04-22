#!/usr/bin/env perl
# jex.cls は pLaTeX 用のため platex を使う（uplatex だと JY1 エンコーディングエラーになる）
$latex = 'platex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$bibtex = 'pbibtex %O %B';
$dvipdf = 'dvipdfmx %O -o %D %S';
$makeindex = 'mendex %O -o %D %S';
$pdf_mode = 3;
