// 提出課題2: 楽曲を再生しつつ、Arduino から届くマイク波形をウィンドウに描画する。

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;

// 自分の環境のポート名に書き換える
final String PORT_NAME = "/dev/cu.usbmodem34B7DA64482C2";
final int    BAUD      = 921600;
final int    ADC_MAX   = 1023;

// 画面に表示する直近サンプル数（少ないほど波がゆったり見える。
// 800 → 約30周期、160 → 約6周期）
final int    DISPLAY_SAMPLES = 60;

Serial port;
int[]  samples;
int    writeIdx = 0;

// --- 楽曲再生（前回課題と同じ構成） ---
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
  size(800, 400);

  minim = new Minim(this);
  out   = minim.getLineOut();
  out.setTempo(120);
  currentWaveform = Waves.SINE;

  samples = new int[width];
  for (int i = 0; i < samples.length; i++) samples[i] = ADC_MAX / 2;

  port = new Serial(this, PORT_NAME, BAUD);
  port.bufferUntil('\n');
}

void draw() {
  background(0);

  // 直近 DISPLAY_SAMPLES 個のサンプルだけを画面幅いっぱいに引き伸ばして描画
  stroke(255);
  noFill();
  int startIdx = (writeIdx - DISPLAY_SAMPLES + samples.length) % samples.length;
  for (int i = 0; i < DISPLAY_SAMPLES - 1; i++) {
    int i1 = (startIdx + i)     % samples.length;
    int i2 = (startIdx + i + 1) % samples.length;
    float x1 = map(i,     0, DISPLAY_SAMPLES - 1, 0, width);
    float x2 = map(i + 1, 0, DISPLAY_SAMPLES - 1, 0, width);
    float y1 = map(samples[i1], 0, ADC_MAX, height, 0);
    float y2 = map(samples[i2], 0, ADC_MAX, height, 0);
    line(x1, y1, x2, y2);
  }

  fill(200);
  noStroke();
  textSize(12);
  text("p: 再生 / 1-6: 音色", 10, height - 10);
}

void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  try {
    int v = Integer.parseInt(line);
    samples[writeIdx] = constrain(v, 0, ADC_MAX);
    writeIdx = (writeIdx + 1) % samples.length;
  } catch (NumberFormatException e) {
    // 起動直後に文字化けが混ざることがあるので無視
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
