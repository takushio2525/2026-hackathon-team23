// ============================================================
//  HCK02_01.ino — マイク入力波形のシリアルプロッタ表示
//
//  例題2 (work3.ino) からの主な変更点:
//    - ボーレートを 921600 → 115200 に変更（プロッタの取りこぼし回避）
//    - 実測値 (0-1023) の出力を廃止（Y軸が整数側に潰されない）
//    - DC オフセット除去を固定値 (1.65V) → EWMA による動的追従に変更
//    - サンプリング間隔を delayMicroseconds(500) で 2 kHz に固定
//    - シリアルプロッタ用ラベルを英字化（環境依存の文字化け対策）
//    - 参照電圧を #define VREF で一元管理し基板差に対応
// ============================================================

#define BAUD       115200  // Arduino IDE のプロッタが安定して受けられるレート
#define PIN        0       // A0 アナログ入力
#define RESOLUTION 10      // 量子化 10bit (0-1023)
#define SAMPLE_US  500     // サンプリング間隔 [us] → 2 kHz で固定

// 基板ごとの参照電圧（UNO=5.0, XIAO / ESP32 等 3.3V系=3.3）
#define VREF       3.3f

// EWMA 係数（0〜1）: 小さいほど強くスムージング
#define ALPHA_DC   0.001f  // DC オフセットをゆっくり追従（低周波成分の保持と追従速度のトレードオフ）
#define ALPHA_LP   0.2f    // 高周波ノイズを除くローパスフィルタ

static float dc = 512.0f;  // DC オフセット推定値（中点付近を初期値に）
static float lp = 0.0f;    // DC 除去後をローパスした振幅値

void setup() {
  pinMode(PIN, INPUT);
  Serial.begin(BAUD);
  analogReadResolution(RESOLUTION);
}

void loop() {
  int raw = analogRead(PIN);

  // DC 成分を EWMA で動的追跡（固定値を引いていた例題2 の偏り問題を解消）
  dc = ALPHA_DC * raw + (1.0f - ALPHA_DC) * dc;

  // DC 除去 → EWMA ローパスでノイズ平滑化
  float centered = (float)raw - dc;
  lp = ALPHA_LP * centered + (1.0f - ALPHA_LP) * lp;

  // RAW カウントを電圧に換算
  float maxCount = (float)((1 << RESOLUTION) - 1);
  float volt     = lp / maxCount * VREF;

  // シリアルプロッタ用出力（3 トレースに絞り Y 軸が ±VREF/2 に張り付くようにする）
  //   signal : DC 除去 + ローパス後の振幅 [V]
  //   ref_hi : Y 軸上限の参考線
  //   ref_lo : Y 軸下限の参考線
  Serial.print("signal:");
  Serial.print(volt, 4);
  Serial.print(",ref_hi:");
  Serial.print(VREF / 2.0f, 4);
  Serial.print(",ref_lo:");
  Serial.println(-VREF / 2.0f, 4);

  delayMicroseconds(SAMPLE_US);
}
