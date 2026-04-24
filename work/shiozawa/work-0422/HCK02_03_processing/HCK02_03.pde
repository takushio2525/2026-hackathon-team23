// 発展課題：Arduino (HCK02_03.ino) から届くマイク ADC 値を Processing で FFT して
// スペクトルアナライザ（周波数ごとの強度を示すバーグラフ）を描画する。
//  - 上段：生波形（時間領域：右端が最新、左へスクロール）
//  - 下段：スペクトル（周波数領域：FFT_SIZE 点 / Hamming 窓 / dB 表示）
//
// 前回課題の楽曲再生 ('p' で再生 / '1'〜'6' で音色切替) はそのまま残してあるので、
// PC スピーカから楽曲を流してマイクに入れ、スペクトルがどう立ち上がるかを比較できる。

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.FFT;

// --- シリアル設定 -----------------------------------------------------------
// 接続先ポート名は実行環境ごとに書き換える（Arduino IDE の「ツール > ポート」で確認）
final String SERIAL_PORT = "/dev/cu.usbmodem34B7DA64482C2";
final int    SERIAL_BAUD = 921600;   // HCK02_03.ino の BAUD と揃える
final int    ADC_MAX     = 1023;     // 10bit ADC の最大値

Serial port;

// --- FFT 設定 ---------------------------------------------------------------
// Arduino 側の SAMPLE_US = 150 µs → 6666.67 Hz。両者を揃えないと周波数軸がずれる。
final float SAMPLE_RATE_HZ = 1000000.0f / 150.0f;
// 2 のべき乗を指定する。大きくすると周波数分解能は上がるが、1 回の FFT に必要な
// サンプル収集時間が長くなる（1024 / 6667 Hz ≒ 154 ms）。
final int   FFT_SIZE       = 1024;
// 表示する最高周波数。ナイキスト周波数（SAMPLE_RATE_HZ / 2 ≒ 3333 Hz）が上限。
final float DISPLAY_MAX_HZ = 3000.0f;
// スペクトルの縦軸 [dB] 表示範囲（下限〜上限）。
final float SPECTRUM_DB_MIN = -60.0f;
final float SPECTRUM_DB_MAX =   0.0f;

// FFT 入力バッファ（[-1, +1] 正規化した最新 FFT_SIZE サンプルを循環保持）
float[] fftInput;
int     fftWriteIdx = 0;
FFT     fft;

// --- 時間領域（生波形）表示用バッファ --------------------------------------
// 横軸=時間、右端=最新、左端=過去。ウィンドウ幅と同じサンプル数だけ保持する。
int[] waveBuf;
int   waveIdx = 0;

// --- 楽曲再生（HCK01_03 / HCK02_02 と同じ構成） ----------------------------
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
  size(900, 540);

  // 楽曲再生の初期化
  minim = new Minim(this);
  out   = minim.getLineOut();
  out.setTempo(120);
  currentWaveform = Waves.SINE;

  // FFT 初期化：Hamming 窓でスペクトル漏れを抑える
  fft = new FFT(FFT_SIZE, SAMPLE_RATE_HZ);
  fft.window(FFT.HAMMING);
  fftInput = new float[FFT_SIZE];

  // 時間波形バッファを中央（振幅 0 相当）で初期化
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

  // 最新サンプルに対して FFT をかける
  // （serialEvent で fftInput が書き換わるので、draw の 1 フレーム内では 1 回だけ）
  fft.forward(fftInput);

  drawTimeDomain();
  drawSpectrum();
  drawLabels();
}

// --- 上段：時間領域波形 -----------------------------------------------------
void drawTimeDomain() {
  final float baseY = 100;     // 0 振幅基準線
  final float amp   = 70;      // 縦方向スケール
  final float half  = ADC_MAX / 2.0f;

  stroke(255, 220, 120);
  noFill();
  for (int x = 0; x < width - 1; x++) {
    // waveIdx が次に書き込む位置＝最古のサンプル位置
    int i1 = (waveIdx + x)     % waveBuf.length;
    int i2 = (waveIdx + x + 1) % waveBuf.length;
    float y1 = baseY - ((waveBuf[i1] - half) / half) * amp;
    float y2 = baseY - ((waveBuf[i2] - half) / half) * amp;
    line(x, y1, x + 1, y2);
  }

  // 区切り線
  stroke(80);
  line(0, 200, width, 200);
}

// --- 下段：周波数領域スペクトル --------------------------------------------
void drawSpectrum() {
  final float top     = 230;               // スペクトル描画領域の上端 y
  final float bottom  = height - 40;       // スペクトル描画領域の下端 y
  final float usableH = bottom - top;

  // 表示するビン範囲：0 Hz 〜 DISPLAY_MAX_HZ
  // FFT の i 番目ビンは i * SAMPLE_RATE_HZ / FFT_SIZE [Hz]
  float binHz     = SAMPLE_RATE_HZ / FFT_SIZE;
  int   maxBinIdx = min(fft.specSize() - 1, (int) (DISPLAY_MAX_HZ / binHz));
  int   numBins   = maxBinIdx + 1;
  float barW      = (float) width / numBins;

  // 縦軸（dB）の目盛り
  stroke(60);
  for (float db = SPECTRUM_DB_MIN; db <= SPECTRUM_DB_MAX; db += 10) {
    float y = map(db, SPECTRUM_DB_MIN, SPECTRUM_DB_MAX, bottom, top);
    line(0, y, width, y);
    noStroke();
    fill(120);
    textSize(10);
    textAlign(LEFT, CENTER);
    text((int) db + " dB", 4, y);
    stroke(60);
  }

  // バーの描画（ビンごとに 1 本。強度を dB に変換）
  noStroke();
  for (int i = 0; i < numBins; i++) {
    float magnitude = fft.getBand(i);
    // dB 変換：0 対策で下限値をかませる
    float db = 20 * (float) Math.log10(Math.max(magnitude, 1e-6f));
    float y  = map(constrain(db, SPECTRUM_DB_MIN, SPECTRUM_DB_MAX),
                   SPECTRUM_DB_MIN, SPECTRUM_DB_MAX, bottom, top);
    // 周波数が上がるにつれて色を変える（視認性向上）
    float hueRatio = (float) i / numBins;
    fill(120 + hueRatio * 135, 180 - hueRatio * 60, 255 - hueRatio * 200);
    float x = i * barW;
    rect(x, y, max(barW - 1, 1), bottom - y);
  }

  // 横軸（Hz）の目盛り
  stroke(100);
  fill(160);
  textAlign(CENTER, TOP);
  textSize(10);
  for (float hz = 0; hz <= DISPLAY_MAX_HZ; hz += 500) {
    float x = map(hz, 0, DISPLAY_MAX_HZ, 0, width);
    line(x, bottom, x, bottom + 4);
    noStroke();
    text((int) hz + " Hz", x, bottom + 6);
    stroke(100);
  }
}

// --- ラベル -----------------------------------------------------------------
void drawLabels() {
  noStroke();
  fill(200);
  textAlign(LEFT, TOP);
  textSize(12);
  text("Time domain: Mic input (A0, via Serial)",   10,  10);
  text("Frequency domain: FFT (" + FFT_SIZE + " pts, "
       + nf(SAMPLE_RATE_HZ, 0, 1) + " Hz, Hamming)", 10, 215);
  text("p: play song   1-6: waveform", 10, height - 16);
}

// --- シリアル受信：1 行 = 1 サンプル ----------------------------------------
void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  if (line.length() == 0) return;
  try {
    int v = Integer.parseInt(line);
    v = constrain(v, 0, ADC_MAX);

    // 時間波形バッファへ書き込み
    waveBuf[waveIdx] = v;
    waveIdx = (waveIdx + 1) % waveBuf.length;

    // FFT 入力バッファへ書き込み（[-1, +1] に正規化して直流成分を抜く）
    float half = ADC_MAX / 2.0f;
    fftInput[fftWriteIdx] = (v - half) / half;
    fftWriteIdx = (fftWriteIdx + 1) % FFT_SIZE;
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
