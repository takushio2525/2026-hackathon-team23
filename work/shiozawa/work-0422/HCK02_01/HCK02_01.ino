// 提出課題1: マイク入力をシリアルプロッタに表示する
#define BAUD       921600
#define PIN        0    // A0
#define RESOLUTION 10   // 10bit (0-1023)

void setup() {
  pinMode(PIN, INPUT);
  Serial.begin(BAUD);
  analogReadResolution(RESOLUTION);
}

void loop() {
  int d = analogRead(PIN);

  // 生値と、プロッタの Y 軸を固定するための上下ガイド
  Serial.print(d);
  Serial.print(',');
  Serial.print(0);
  Serial.print(',');
  Serial.println(1023);

  delayMicroseconds(100);
}
