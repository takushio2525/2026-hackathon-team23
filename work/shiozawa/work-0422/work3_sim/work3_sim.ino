// work3_sim - work3.ino の擬似シミュレーション版
//
// 目的:
//   work3.ino はマイク（A0）から analogRead した値を漢字ラベル付きで
//   Serial.print する構成。このスケッチはマイクが壊れている状態でも
//   同じフォーマットで「波形が崩れて見える」状況を再現できるよう、
//   analogRead を内部タイマー基準の sin 波生成に置き換えたもの。
//
// 仕様:
//   - analogRead(PIN) を呼び出す代わりに、micros() から時刻 t を取り、
//     SIM_FREQ [Hz] の sin 波を 0〜1023 の整数値に量子化して d とする
//   - 以降の処理（電圧換算・中心化・漢字ラベル付きシリアル出力）は
//     work3.ino と完全同一
//
// ※ サンプリング時刻は「Serial 出力が呼ばれた瞬間の micros()」になる。
//   漢字ラベル送信が支配的に時間を食うため、t がガタつく → 本来の
//   サイン波が Serial Plotter 上で正しく見えない、という状況を再現する。

#define BAUD 921600    // ボーレート（速め）
#define PIN 0          // A0 アナログ⼊⼒（互換のため定義のみ・本スケッチでは未使用）
#define RESOLUTION 10  // 量⼦化10bit

// シミュレーションする波形の周波数
const float SIM_FREQ = 440.0;

// 10bit 量子化の最大値・中央値（事前計算）
const int SIM_ADC_MAX = 1023;
const int SIM_ADC_MID = SIM_ADC_MAX / 2;

void setup() {
  // マイクのポートを指定（シミュレーションでは未使用だが互換のため残す）
  pinMode(PIN, INPUT);
  // シリアル通信の速度を設定(bit per second)
  Serial.begin(BAUD);
  // アナログ読み込みの量⼦化精度
  analogReadResolution(RESOLUTION);
}

void loop() {
  // ------ analogRead(PIN) の代わりに内部タイマー基準で sin 波を生成 ------
  // 「シリアル出力が行われる瞬間のマイコン起動時間」を t とする
  float t = (float)micros() / 1000000.0;
  float s = sin(2.0 * PI * SIM_FREQ * t);          // -1.0 〜 +1.0
  int d = (int)(SIM_ADC_MID + s * SIM_ADC_MID);    // 0 〜 1023
  if (d < 0)            d = 0;
  if (d > SIM_ADC_MAX)  d = SIM_ADC_MAX;
  // ----------------------------------------------------------------------

  // 読み込んだ値を量⼦化精度で規格化し，電圧を取得
  float a = (float)d / (pow(2, RESOLUTION) - 1) * 5.0;
  float maxa = 3.3 / 2.0; // 振幅最⼤値
  a = a - maxa;           // 中⼼を0にする
  float mina = -maxa;     // 振幅最⼩値
  // シリアルモニタに出⼒
  //Serial.print("実測値:");
  Serial.println(d);
  // //Serial.print(",振幅:");
  // Serial.print(a);
  // //Serial.print(",最⼤振幅:");
  // Serial.print(maxa);
  // //Serial.print(",最⼩振幅:");
  // Serial.println(mina);
}
