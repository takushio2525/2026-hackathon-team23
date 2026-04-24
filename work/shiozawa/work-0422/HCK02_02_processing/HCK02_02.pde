// 前回課題 (HCK01_03) の楽曲を Processing で再生しつつ、
// Arduino (HCK02_02.ino) から届くマイク波形をウィンドウに描画する。
//  - 上段：minim が出力している楽曲バッファ（左右チャンネル）
//  - 下段：シリアルから届くマイク ADC 値（右端が最新、左にスクロール）

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;

// --- シリアル設定 -----------------------------------------------------------
// 接続先ポート名は実行環境ごとに書き換える（Arduino IDE の「ツール > ポート」で確認）
final String SERIAL_PORT = "/dev/cu.usbmodem34B7DA64482C2";
final int    SERIAL_BAUD = 921600;   // HCK02_02.ino の BAUD と揃える
final int    ADC_MAX     = 1023;     // 10bit ADC の最大値

Serial port;

// マイク波形の循環バッファ（描画時にウィンドウ幅と同じサンプル数を保持）
int[] waveBuf;
int   waveIdx = 0;

// --- 楽曲再生（HCK01_03 と同じ構成） ---------------------------------------
Minim        minim;
AudioOutput  out;
Waveform     currentWaveform;

// 各音の高さ
String[] melody = {
  "C4", "C4", "G4", "G4", "A4", "A4", "G4"
};

// 各音の長さ（拍）
float[] duration = {
  0.9f, 0.9f, 0.9f, 0.9f, 0.9f, 0.9f, 0.9f
};

// 各音の開始位置
float[] startTime = {
  0.0f, 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f
};

// 各音の大きさ
float[] maxAmp = {
  2.0f, 1.0f, 5.0f, 0.4f, 0.6f, 0.8f, 1.0f
};

// 音色を変更するために Instrument インタフェースを実装する
class HackInstrument implements Instrument {
  Oscil wave;
  Line  ampEnv;
  float maxAmp;

  HackInstrument(float frequency, float maxAmp, Waveform wf) {
    wave = new Oscil(frequency, 0, wf);
    this.maxAmp = maxAmp;
    ampEnv = new Line();
    ampEnv.patch(wave.amplitude);
  }

  // コールバック関数：再生開始
  void noteOn(float duration) {
    ampEnv.activate(duration, this.maxAmp, 0);
    wave.patch(out);
  }

  // コールバック関数：再生停止
  void noteOff() {
    wave.unpatch(out);
  }
}

// --- Processing エントリ ----------------------------------------------------
void setup() {
  size(800, 500);

  // 楽曲再生の初期化
  minim = new Minim(this);
  out   = minim.getLineOut();
  out.setTempo(120);
  currentWaveform = Waves.SINE;

  // マイク波形バッファを中央値（振幅ゼロ相当）で初期化
  waveBuf = new int[width];
  for (int i = 0; i < waveBuf.length; i++) {
    waveBuf[i] = ADC_MAX / 2;
  }

  // シリアルポート接続（改行区切りで serialEvent() を呼ぶ）
  port = new Serial(this, SERIAL_PORT, SERIAL_BAUD);
  port.clear();
  port.bufferUntil('\n');
}

void draw() {
  background(0);

  // --- 上段：楽曲の左チャンネル ------------------------------------------
  stroke(120, 180, 255);
  noFill();
  float leftBase  = 80;
  float rightBase = 170;
  float chanAmp   = 50;
  for (int i = 0; i < out.bufferSize() - 1; i++) {
    // 横幅 width に対して minim のバッファ長を間引いて描画
    float x1 = map(i,     0, out.bufferSize() - 1, 0, width);
    float x2 = map(i + 1, 0, out.bufferSize() - 1, 0, width);
    line(x1, leftBase  + out.left.get(i)      * chanAmp,
         x2, leftBase  + out.left.get(i + 1)  * chanAmp);
    line(x1, rightBase + out.right.get(i)     * chanAmp,
         x2, rightBase + out.right.get(i + 1) * chanAmp);
  }

  // --- 区切り線 -------------------------------------------------------------
  stroke(80);
  line(0, 250, width, 250);

  // --- 下段：マイク入力波形（左 → 右の時間軸） ---------------------------
  stroke(255, 220, 120);
  noFill();
  float micBase = 375;   // 0 振幅基準線
  float micAmp  = 100;   // 振幅の縦方向スケール
  float half    = ADC_MAX / 2.0;
  for (int x = 0; x < width - 1; x++) {
    // waveIdx が次に書き込む位置＝最古のサンプル位置
    int i1 = (waveIdx + x)     % waveBuf.length;
    int i2 = (waveIdx + x + 1) % waveBuf.length;
    // ADC 値を [-1, 1] に正規化して、中心 micBase から上下に振る
    float y1 = micBase - ((waveBuf[i1] - half) / half) * micAmp;
    float y2 = micBase - ((waveBuf[i2] - half) / half) * micAmp;
    line(x, y1, x + 1, y2);
  }

  // --- ラベル ---------------------------------------------------------------
  fill(200);
  noStroke();
  textSize(12);
  text("Song L (minim buffer)",        10, 20);
  text("Song R (minim buffer)",        10, 120);
  text("Mic input (A0, via Serial)",   10, 270);
  text("p: play song   1-6: waveform", 10, height - 10);
}

// シリアル受信：1 行 = 1 サンプル
void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  if (line.length() == 0) return;
  try {
    int v = Integer.parseInt(line);
    v = constrain(v, 0, ADC_MAX);
    waveBuf[waveIdx] = v;
    waveIdx = (waveIdx + 1) % waveBuf.length;
  } catch (NumberFormatException e) {
    // 起動直後の半端な行（例：改行だけ、数字でない文字が混ざる）は無視
  }
}

void playSong() {
  // 再生を停止
  out.pauseNotes();
  // 繰り返し処理を使って異なる音を追加
  for (int i = 0; i < melody.length; i++) {
    out.playNote(startTime[i], duration[i],
      new HackInstrument(Frequency.ofPitch(melody[i]).asHz(),
      maxAmp[i], currentWaveform));
  }
  // 再生
  out.resumeNotes();
}

void keyPressed() {
  switch (key) {
    case '1':
      // 正弦波
      currentWaveform = Waves.SINE;
      break;
    case '2':
      // 三角波
      currentWaveform = Waves.TRIANGLE;
      break;
    case '3':
      // のこぎり波
      currentWaveform = Waves.SAW;
      break;
    case '4':
      // 矩形波
      currentWaveform = Waves.SQUARE;
      break;
    case '5':
      // 16 個の奇数倍音からなる音。振幅値はランダム。
      currentWaveform = Waves.randomNOddHarms(16);
      break;
    case '6':
      // 倍音の振幅値を指定した自作の音色
      currentWaveform = WavetableGenerator.gen10(
        4096, // サンプルサイズ（2 の倍数で）
        new float[] { 1.0f, 0.45f, 0.20f, 0.10f, 0.05f } // 各倍音の振幅値
      );
      break;
    case 'p':
      // 作成した信号を出力
      playSong();
      break;
    default:
      break;
  }
}
