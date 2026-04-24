// マイク ADC 値を Processing に 1 サンプル 1 行で送る。
// サンプリング設定・ボーレートは HCK02_01.ino と共通にし、
// 出力フォーマットだけ Processing が受け取りやすい単一整数 + 改行に変更している。

#define BAUD       921600  // ボーレート（HCK02_01 と共通）
#define PIN        0       // A0 アナログ入力
#define RESOLUTION 10      // 量子化 10bit（0〜1023）
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
  // 符号付き比較で micros() の 32bit ラップアラウンドに耐える。
  while ((int32_t)(micros() - nextSampleUs) < 0) {
    // 待機
  }
  nextSampleUs += SAMPLE_US;

  int d = analogRead(PIN);

  // Processing 向け：ADC 値を 1 行 1 サンプルで送る。
  // Y 軸ガイドは Processing 側で描画するため、送信量を減らして送信 1 本に絞る。
  Serial.println(d);
}
