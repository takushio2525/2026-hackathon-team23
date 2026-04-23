import processing.serial.*;
Serial port; // シリアルポート
int col; // x座標⽤
void setup(){
// ウィンドウサイズ
size(400, 400);
// ポートを初期化
port = new Serial(this, "/dev/cu.usbmodem34B7DA64482C2", 115200);
// シリアルポートの初期化
port.clear();
}


void draw() {
background(0); // 背景は⿊
fill(col, 0, 0); // ⾚を指定
ellipse(width/2, height/2, 100, 100);
//円を描く
}
// データが送信されてきたら呼び出される関数
void serialEvent(Serial p) {
// ポートからデータを取得
col = p.read();
// 確認のために書き出し
println(col);
}
