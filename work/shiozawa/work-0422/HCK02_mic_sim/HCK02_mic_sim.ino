// HCK02 用 マイク入力 擬似シリアル出力テストプログラム
//
// 目的:
//   HCK02_02.pde / HCK02_03.pde が想定する Arduino 側マイク入力
//   (Serial 921600 baud, 0〜1023 の整数を改行区切り, おおよそ 5 kHz サンプリング)
//   を、マイクが壊れている状態でも擬似的に再現する。
//
//   HCK02_02.pde / HCK02_03.pde の playSong() と同じメロディ
//     (C4, C4, G4, G4, A4, A4, G4 / 各 0.9s / maxAmp = 2,1,5,0.4,0.6,0.8,1)
//   を Arduino 内部でサイン波合成し、シリアル出力する。
//
// 使い方:
//   1. このスケッチを HCK02_03.ino の代わりに Arduino へ書き込む。
//   2. HCK02_03.pde (または HCK02_02.pde) の PORT_NAME を実機の usbmodem に合わせる。
//   3. .pde を実行する。マイクが付いていなくても波形と FFT が表示される。
//
// 注意:
//   - 内部時刻はサンプル番号を SAMPLE_RATE で割って算出している。
//     Serial 出力速度に影響されず、生成する波形の周波数が FFT 上で正しいビンに乗る。
//   - Processing 側の playSong() はこのスケッチとは独立に音を鳴らすため、
//     スピーカーから聞こえる音と画面に出る波形は同期しない（あくまでデモ用）。
//   - マイクが直ったら HCK02_03.ino に戻すこと。

#define BAUD     921600
#define ADC_MAX  1023
#define ADC_MID  (ADC_MAX / 2)

// Processing 側 HCK02_03.pde の SAMPLE_RATE と一致させる
const float SAMPLE_RATE = 5000.0;

// メロディ（HCK02_02.pde / HCK02_03.pde の playSong() と同じ）
const int   NOTE_COUNT                = 7;
const float NOTE_FREQ[NOTE_COUNT]     = { 261.63, 261.63, 392.00, 392.00, 440.00, 440.00, 392.00 };
const float NOTE_DURATION[NOTE_COUNT] = { 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9 };
const float NOTE_START[NOTE_COUNT]    = { 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
const float NOTE_MAX_AMP[NOTE_COUNT]  = { 2.0, 1.0, 5.0, 0.4, 0.6, 0.8, 1.0 };

// 1 ループ分の長さ。最後のノート終了 + 0.5s の余白。
const float         LOOP_DURATION = 7.5;
const unsigned long LOOP_SAMPLES  = (unsigned long)(LOOP_DURATION * SAMPLE_RATE);

// 振幅正規化用。NOTE_MAX_AMP の最大値で割って ±1 に収める。
const float AMP_NORM = 5.0;

// ADC 値の中央からの最大振幅（端をわずかに残してクリップ視認性を確保）
const int ADC_AMP = ADC_MID - 32;  // 480

unsigned long sampleIdx = 0;

void setup() {
  Serial.begin(BAUD);
}

void loop() {
  // ループ内サンプル番号 → 経過時間 t [秒]
  unsigned long s = sampleIdx % LOOP_SAMPLES;
  float t = (float)s / SAMPLE_RATE;

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

  Serial.println(v);
  sampleIdx++;

  // HCK02_03.ino と同じ間隔。実効サンプリングレートは Serial 出力時間に支配される
  // （5〜10 kHz 程度）が、t は SAMPLE_RATE 基準なので波形の周波数は正しい。
  delayMicroseconds(100);
}
