// work3_sim - スペクトラムアナライザ検証用シミュレータ
//
// 2秒ごとにド→レ→ミ→ファ→ソ→ラ→シ→ド（C4〜C5）を
// 順番に切り替えて sin 波を生成する。
// スペクトラム表示側でピーク周波数が階段状に上がっていけば正常。

#define BAUD 921600
#define PIN 0
#define RESOLUTION 10

// ド レ ミ ファ ソ ラ シ ド（C4〜C5, 平均律）
const float SCALE[] = {
  261.63,  // C4  ド
  293.66,  // D4  レ
  329.63,  // E4  ミ
  349.23,  // F4  ファ
  392.00,  // G4  ソ
  440.00,  // A4  ラ
  493.88,  // B4  シ
  523.25   // C5  ド
};
const int SCALE_LEN = sizeof(SCALE) / sizeof(SCALE[0]);

// 各音の持続時間 [ms]
const unsigned long NOTE_DURATION_MS = 2000;

const int SIM_ADC_MAX = 1023;
const int SIM_ADC_MID = SIM_ADC_MAX / 2;

void setup() {
  pinMode(PIN, INPUT);
  Serial.begin(BAUD);
  analogReadResolution(RESOLUTION);
}

void loop() {
  // 現在の音階インデックスを経過時間から決定
  unsigned long now = millis();
  int noteIndex = (now / NOTE_DURATION_MS) % SCALE_LEN;
  float freq = SCALE[noteIndex];

  // sin 波生成
  float t = (float)micros() / 1000000.0;
  float s = sin(2.0 * PI * freq * t);
  int d = (int)(SIM_ADC_MID + s * SIM_ADC_MID);
  if (d < 0)            d = 0;
  if (d > SIM_ADC_MAX)  d = SIM_ADC_MAX;

  Serial.println(d);
}
