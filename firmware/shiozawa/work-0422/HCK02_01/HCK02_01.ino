#define BAUD       921600  // ボーレート
#define PIN        0       // A0 アナログ入力
#define RESOLUTION 10      // 量子化 10bit
#define SAMPLE_US  500     // サンプリング間隔 [µs] → 2 kHz

// EWMA係数（0〜1）: 小さいほど強くスムージング
#define ALPHA_DC   0.001f  // DCオフセット追跡（ゆっくり追従）
#define ALPHA_LP   0.2f    // ローパスフィルタ（ノイズ除去）

static float dc  = 512.0f; // DCオフセット推定値（RAWカウント基準）
static float lp  = 0.0f;   // ローパス後の振幅値

void setup() {
  pinMode(PIN, INPUT);
  Serial.begin(BAUD);
  analogReadResolution(RESOLUTION);
}

void loop() {
  int raw = analogRead(PIN);

  // DCオフセットをEWMAで動的追跡
  dc = ALPHA_DC * raw + (1.0f - ALPHA_DC) * dc;

  // DC除去 → EWMAローパスフィルタでノイズ平滑化
  float centered = (float)raw - dc;
  lp = ALPHA_LP * centered + (1.0f - ALPHA_LP) * lp;

  // RAWカウントを電圧に変換（参照電圧 3.3V）
  float maxCount = (float)((1 << RESOLUTION) - 1);
  float volt     = lp / maxCount * 3.3f;

  // シリアルプロッタ用出力
  Serial.print("振幅:");
  Serial.print(volt, 4);
  Serial.print(",最大振幅:");
  Serial.print(1.65f, 4);
  Serial.print(",最小振幅:");
  Serial.println(-1.65f, 4);

  delayMicroseconds(SAMPLE_US);
}
