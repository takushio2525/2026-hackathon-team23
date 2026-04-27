// 発展課題: マイク波形を FFT してスペクトルアナライザとして表示する。
// 上段: 生波形 / 下段: 周波数バー

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.FFT;

// 自分の環境のポート名に書き換える
final String PORT_NAME   = "/dev/cu.usbmodem34B7DA64482C2";
final int    BAUD        = 921600;
final int    ADC_MAX     = 1023;
// Arduino は delayMicroseconds(100) なのでサンプリング周波数は約 5 kHz（実機に合わせて要調整）
final float  SAMPLE_RATE = 5000.0;
final int    FFT_SIZE    = 512;

Serial  port;
int[]   samples;
int     sampleIdx = 0;
float[] fftInput;
FFT     fft;

// --- 楽曲再生 ---
Minim       minim;
AudioOutput out;
Waveform    currentWaveform;

String[] melody    = { "C4", "C4", "G4", "G4", "A4", "A4", "G4" };
float[]  duration  = { 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9 };
float[]  startTime = { 0,   1,   2,   3,   4,   5,   6   };
float[]  maxAmp    = { 2.0, 1.0, 5.0, 0.4, 0.6, 0.8, 1.0 };

class HackInstrument implements Instrument {
  Oscil osc;
  Line  ampEnv;
  float maxAmp;

  HackInstrument(float freq, float maxAmp, Waveform wf) {
    osc = new Oscil(freq, 0, wf);
    this.maxAmp = maxAmp;
    ampEnv = new Line();
    ampEnv.patch(osc.amplitude);
  }

  void noteOn(float duration) {
    ampEnv.activate(duration, this.maxAmp, 0);
    osc.patch(out);
  }

  void noteOff() {
    osc.unpatch(out);
  }
}

void setup() {
  size(900, 500);

  minim = new Minim(this);
  out   = minim.getLineOut();
  out.setTempo(120);
  currentWaveform = Waves.SINE;

  samples  = new int[width];
  for (int i = 0; i < samples.length; i++) samples[i] = ADC_MAX / 2;

  fft      = new FFT(FFT_SIZE, SAMPLE_RATE);
  fftInput = new float[FFT_SIZE];

  port = new Serial(this, PORT_NAME, BAUD);
  port.bufferUntil('\n');
}

void draw() {
  background(0);

  // samples の最新 FFT_SIZE 個を時系列順に並べて [-1, +1] に正規化してから FFT
  for (int i = 0; i < FFT_SIZE; i++) {
    int idx = (sampleIdx - FFT_SIZE + i + samples.length) % samples.length;
    fftInput[i] = (samples[idx] - ADC_MAX / 2.0) / (ADC_MAX / 2.0);
  }
  fft.forward(fftInput);

  drawWave();
  drawSpectrum();
  fill(200);
  noStroke();
  textSize(12);
  text("p: 再生 / 1-6: 音色", 10, height - 10);
}

void drawWave() {
  // 上半分をゆったり使う
  final float midY = height * 0.25;
  final float amp  = height * 0.20;

  stroke(255);
  noFill();
  // 1サンプル=1ピクセルで描画（バッファ全体 = width 個）
  // → 1フレームあたりの更新が全体の ~9% で滑らかにスクロールする
  for (int x = 0; x < width - 1; x++) {
    int i1 = (sampleIdx + x)     % samples.length;
    int i2 = (sampleIdx + x + 1) % samples.length;
    float y1 = midY - (samples[i1] - ADC_MAX / 2.0) / (ADC_MAX / 2.0) * amp;
    float y2 = midY - (samples[i2] - ADC_MAX / 2.0) / (ADC_MAX / 2.0) * amp;
    line(x, y1, x + 1, y2);
  }
  stroke(80);
  line(0, height * 0.5, width, height * 0.5);
}

void drawSpectrum() {
  final float top    = height * 0.55;
  final float bottom = height - 30;
  final float maxMag = 30;  // バーの表示上限の目安

  int   bins = fft.specSize();
  float barW = (float) width / bins;

  noStroke();
  fill(120, 200, 255);
  for (int i = 0; i < bins; i++) {
    float h = constrain(fft.getBand(i) / maxMag, 0, 1) * (bottom - top);
    rect(i * barW, bottom - h, barW - 1, h);
  }

  // 周波数の目盛り（100 Hz ごと、ナイキストの 500 Hz まで）
  fill(160);
  textAlign(CENTER, TOP);
  textSize(10);
  for (int hz = 0; hz <= 500; hz += 100) {
    float x = map(hz, 0, SAMPLE_RATE / 2, 0, width);
    text(hz + " Hz", x, bottom + 4);
  }
}

void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  try {
    int v = constrain(Integer.parseInt(line), 0, ADC_MAX);
    samples[sampleIdx] = v;
    sampleIdx = (sampleIdx + 1) % samples.length;
  } catch (NumberFormatException e) {
    // 文字化けは無視
  }
}

void playSong() {
  out.pauseNotes();
  for (int i = 0; i < melody.length; i++) {
    out.playNote(startTime[i], duration[i],
      new HackInstrument(Frequency.ofPitch(melody[i]).asHz(),
                         maxAmp[i], currentWaveform));
  }
  out.resumeNotes();
}

void keyPressed() {
  switch (key) {
    case '1': currentWaveform = Waves.SINE;     break;
    case '2': currentWaveform = Waves.TRIANGLE; break;
    case '3': currentWaveform = Waves.SAW;      break;
    case '4': currentWaveform = Waves.SQUARE;   break;
    case '5': currentWaveform = Waves.randomNOddHarms(16); break;
    case '6': currentWaveform = WavetableGenerator.gen10(
                4096, new float[] { 1.0, 0.45, 0.20, 0.10, 0.05 });
              break;
    case 'p': playSong(); break;
  }
}
