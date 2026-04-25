// 発展課題: マイクの値を Processing に送る (HCK02_02.ino と同じ)
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
  Serial.println(d);
  delay(1);
}
