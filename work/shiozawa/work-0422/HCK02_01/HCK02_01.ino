// マイク波形を 3 系列（生値・上限・下限）で出力。
// Serial 出力を整数に圧縮し、等間隔サンプリングで sin 波の表示密度を確保する。

#define BAUD       921600  // ボーレート
#define PIN        0       // A0 アナログ入力
#define RESOLUTION 10      // 量子化 10bit
#define SAMPLE_US  150     // サンプリング周期 [µs] → 約 6.6 kHz

static uint32_t nextSampleUs = 0;

void setup() {
  pinMode(PIN, INPUT);
  Serial.begin(BAUD);
  analogReadResolution(RESOLUTION);
  nextSampleUs = micros();
}

void loop() {
  // 等間隔サンプリング：目標時刻まで busy wait。
  // 符号付き比較で micros() の 32bit ラップアラウンドに耐える
  while ((int32_t)(micros() - nextSampleUs) < 0) {
    // 待機
  }
  nextSampleUs += SAMPLE_US;

  int d = analogRead(PIN);

  // ラベルなし・整数 3 系列（生値、上限ガイド、下限ガイド）
  // プロッタ Y 軸を 0〜1023 に固定するためにガイド線を毎回出力
  Serial.print(d);
  Serial.print(',');
  Serial.print((1 << RESOLUTION) - 1);
  Serial.print(',');
  Serial.println(0);
}
