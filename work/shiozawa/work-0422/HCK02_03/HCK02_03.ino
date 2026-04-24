// 発展課題：マイク ADC 値を Processing のスペクトルアナライザへ送る。
// HCK02_02.ino と同じ等間隔サンプリングを行い、1 サンプル 1 行で送信する。
// Processing 側 (HCK02_03.pde) で FFT に入力するため、サンプリング周期を
// 厳密に守る必要がある。ジッタが増えると周波数軸のスケールが狂う。

#define BAUD       921600  // ボーレート（HCK02_01/02 と共通）
#define PIN        0       // A0 アナログ入力
#define RESOLUTION 10      // 量子化 10bit（0〜1023）
#define SAMPLE_US  150     // サンプリング周期 [µs] → 6666.67 Hz（Processing 側と一致させる）

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
  // スペアナの横軸 Hz は Processing 側が SAMPLE_US から算出するため、
  // 送信量を抑えるために値そのものだけを送る。
  Serial.println(d);
}
