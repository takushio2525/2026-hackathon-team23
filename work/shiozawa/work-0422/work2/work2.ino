#define LED_ID 12      // LEDのポート
int on = 1000;         // 点灯時間（ミリ秒）
int off = 500;         // 消灯時間（ミリ秒）
bool ledState = false; // LEDの状態
void setup() {
  // 出⼒設定
  pinMode(LED_ID, OUTPUT);
  // シリアルポートを開く
  Serial.begin(115200);
}

void loop() {
  ledState = !ledState;           // 状態を反転
  digitalWrite(LED_ID, ledState); // LED制御
  // LEDがHIGHならば
  if (ledState) {
    Serial.write(255); // ⾚⾊情報送信
    delay(on);         // on秒待つ
  } else {
    Serial.write((byte)0); // ⿊⾊情報送信
    delay(off);            // off秒待つ
  }
}
