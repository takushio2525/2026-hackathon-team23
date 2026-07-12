#!/usr/bin/env perl
# 最終報告書テンプレート (jlreq) は uplatex + dvipdfmx でコンパイルする
$latex = 'uplatex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$bibtex = 'upbibtex %O %B';
$dvipdf = 'dvipdfmx %O -o %D %S';
$makeindex = 'mendex %O -o %D %S';
$pdf_mode = 3;
