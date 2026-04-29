// HCK02 用 マイク入力 擬似シリアル出力テストプログラム（漢字ラベル付き・内部タイマー基準）
//
// 目的:
//   HCK02_mic_sim.ino の派生バージョン。
//   「シリアル出力に漢字を含めると 1 行あたりの送信バイト数が大きく増え、
//    Serial.println にかかる時間がループ周期を支配する」という仮説を、
//    Processing 側の波形プロットや FFT で確認するためのテストスケッチ。
//
//   オリジナル (HCK02_mic_sim.ino) はサンプル番号 sampleIdx を SAMPLE_RATE で割って
//   t を求めていた（＝出力ごとに t が等間隔に進む）。
//   このスケッチでは t を内部タイマー micros() から直接取るため、
//   Serial.println の所要時間がそのまま t の刻み幅になる。
//   漢字ラベルで送信バイト数を増やすと t がガタつき・飛びを起こし、
//   FFT 上の本来の周波数に乗らず波形が崩れる様子を観察できる。
//
// 使い方:
//   - シリアルモニタ / シリアルプロッタで出力を確認する
//   - 数値だけを期待している HCK02_03.pde とは互換性がない（パース崩れに注意）
//
// 注意:
//   - ループは LOOP_DURATION_US で剰余をとってメロディを繰り返す
//   - delayMicroseconds による意図的な間引きは行わない（Serial 送信時間に律速させる）

#define BAUD     921600
#define ADC_MAX  1023
#define ADC_MID  (ADC_MAX / 2)

// メロディ（HCK02_02.pde / HCK02_03.pde の playSong() と同じ）
const int   NOTE_COUNT                = 7;
const float NOTE_FREQ[NOTE_COUNT]     = { 261.63, 261.63, 392.00, 392.00, 440.00, 440.00, 392.00 };
const float NOTE_DURATION[NOTE_COUNT] = { 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9 };
const float NOTE_START[NOTE_COUNT]    = { 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
const float NOTE_MAX_AMP[NOTE_COUNT]  = { 2.0, 1.0, 5.0, 0.4, 0.6, 0.8, 1.0 };

// 1 ループ分の長さ（秒）。最後のノート終了 + 0.5s の余白。
const float         LOOP_DURATION    = 7.5;
const unsigned long LOOP_DURATION_US = (unsigned long)(LOOP_DURATION * 1000000.0);

// 振幅正規化用。NOTE_MAX_AMP の最大値で割って ±1 に収める。
const float AMP_NORM = 5.0;

// ADC 値の中央からの最大振幅（端をわずかに残してクリップ視認性を確保）
const int ADC_AMP = ADC_MID - 32;  // 480

void setup() {
  Serial.begin(BAUD);
}

void loop() {
  // 内部タイマーから現在時刻 t [秒] を取得する（＝シリアル出力が行われる
  // 瞬間のマイコン起動時間そのもの）。LOOP_DURATION で剰余をとり繰り返し再生。
  unsigned long us = micros() % LOOP_DURATION_US;
  float t = (float)us / 1000000.0;

  // すべてのノートを合成（実際には同時発音は 1 音だけだが汎用的に書く）
  float sample = 0.0;
  for (int i = 0; i < NOTE_COUNT; i++) {
    float dt = t - NOTE_START[i];
    if (dt < 0.0 || dt >= NOTE_DURATION[i]) continue;

    // Minim の Line と同じ線形エンベロープ（maxAmp → 0）
    float env = NOTE_MAX_AMP[i] * (1.0 - dt / NOTE_DURATION[i]);
    sample += env * sin(2.0 * PI * NOTE_FREQ[i] * t);
  }

  // ±1 に正規化 → ADC スケールへ
  sample = sample / AMP_NORM;
  if (sample >  1.0) sample =  1.0;
  if (sample < -1.0) sample = -1.0;
  int v = ADC_MID + (int)(sample * ADC_AMP);
  if (v < 0)       v = 0;
  if (v > ADC_MAX) v = ADC_MAX;

  // 漢字ラベル付きでシリアル出力（work3.ino と同じスタイル）。
  // この行が支配的に時間を食い、micros() ベースの t を粗くサンプリングさせる。
  Serial.print("時刻:");
  Serial.print(t, 4);
  Serial.print(",出力値:");
  Serial.println(v);
}
