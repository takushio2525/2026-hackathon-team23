import processing.serial.*;
Serial port; // シリアルポート

int buffersize = 800;
float[] waveData = new float[buffersize];

void setup() {
  // ウィンドウサイズ
  size(800, 400);
  
  // ポートを初期化
  port = new Serial(this, "/dev/tty.usbmodem34B7DA6375842", 921600);
  
  for(int i = 0; i < waveData.length; i++){
    waveData[i] = 0.0;
  }
}

void draw() {
  background(0); // 背景は⿊
  stroke(255, 255, 255);
  strokeWeight(2);
  
  translate(0, height / 2);
  
  for (int i = 1; i < waveData.length; i++) {
    // 1つ前の点の座標
    float x1 = i - 1;
    float y1 =(waveData[i - 1] -180 ) * 2; 
    
    // 今の点の座標
    float x2 = i;
    float y2 = (waveData[i] -180) * 2; 
    
    // 2つの点を線で結ぶ
    line(x1, y1, x2, y2);
  }
}

// データが送信されてきたら呼び出される関数
void serialEvent(Serial p) {
  // ポートからデータを取得
  int newData = p.read(); 
  println(newData);

  for (int i = 0; i < waveData.length - 1; i++) {
    waveData[i] = waveData[i + 1];
  }
  waveData[waveData.length - 1] = newData;
}
