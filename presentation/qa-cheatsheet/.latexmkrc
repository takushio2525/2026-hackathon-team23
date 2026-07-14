$latex = 'uplatex -synctex=1 -halt-on-error %O %S';
$bibtex = 'upbibtex %O %B';
$dvipdf = 'dvipdfmx %O -o %D %S';
$pdf_mode = 3;  # latex -> dvipdfmx
$max_repeat = 5;
