// 提出課題2: マイクの値を Processing に送る
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
  Serial.println(d);  // 1 行 1 サンプル
  delay(1);
}
