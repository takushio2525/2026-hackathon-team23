#!/usr/bin/env perl
# uplatex + dvipdfmx でビルド（jsarticle 日本語）
$latex = 'uplatex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$bibtex = 'upbibtex %O %B';
$dvipdf = 'dvipdfmx %O -o %D %S';
$makeindex = 'mendex %O -o %D %S';
$pdf_mode = 3;
