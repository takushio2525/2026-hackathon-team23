// 提出課題2: マイクの値を Processing に送る
// サンプリング周期は busy-wait で 150µs（約 6.6kHz）に固定する。
// この解像度を確保しないと Processing 側で再生中のサイン波がガビガビになる。

#define BAUD       921600
#define PIN        0       // A0
#define RESOLUTION 10      // 10bit (0-1023)
#define SAMPLE_US  150     // サンプリング周期 [µs] → 約 6.6 kHz

static uint32_t nextSampleUs = 0;

void setup() {
  pinMode(PIN, INPUT);
  Serial.begin(BAUD);
  analogReadResolution(RESOLUTION);
  nextSampleUs = micros();
}

void loop() {
  // 目標時刻まで待機。符号付き比較で micros() の 32bit ラップアラウンドに耐える。
  while ((int32_t)(micros() - nextSampleUs) < 0) {
    // 待機
  }
  nextSampleUs += SAMPLE_US;

  int d = analogRead(PIN);
  Serial.println(d);  // 1 行 1 サンプル
}
