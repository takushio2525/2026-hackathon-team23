// 提出課題2: 楽曲を再生しつつ、Arduino から届くマイク波形をウィンドウに描画する。

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;

// 自分の環境のポート名に書き換える
final String PORT_NAME = "/dev/cu.usbmodem34B7DA64482C2";
final int    BAUD      = 921600;
final int    ADC_MAX   = 1023;

// 画面に表示する直近サンプル数
final int DISPLAY_SAMPLES = 60;

Serial port;
int[]  samples;
int    writeIdx = 0;

Minim       minim;
AudioOutput out;
Waveform    waveform;

// きらきら星
String[] melody    = { "C4", "C4", "G4", "G4", "A4", "A4", "G4" };
float[]  duration  = { 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9 };
float[]  startTime = { 0,   1,   2,   3,   4,   5,   6   };

class SimpleInstrument implements Instrument {
  Oscil osc;
  Line  env;

  SimpleInstrument(float freq, Waveform wf) {
    osc = new Oscil(freq, 0, wf);
    env = new Line();
    env.patch(osc.amplitude);
  }

  void noteOn(float dur) {
    env.activate(dur, 1.0, 0);
    osc.patch(out);
  }

  void noteOff() {
    osc.unpatch(out);
  }
}

void setup() {
  size(800, 400);
  minim    = new Minim(this);
  out      = minim.getLineOut();
  out.setTempo(120);
  waveform = Waves.SINE;

  samples = new int[width];
  for (int i = 0; i < samples.length; i++) samples[i] = ADC_MAX / 2;

  port = new Serial(this, PORT_NAME, BAUD);
  port.bufferUntil('\n');
}

void draw() {
  background(0);

  stroke(255);
  noFill();
  int start = (writeIdx - DISPLAY_SAMPLES + samples.length) % samples.length;
  for (int i = 0; i < DISPLAY_SAMPLES - 1; i++) {
    int i1 = (start + i)     % samples.length;
    int i2 = (start + i + 1) % samples.length;
    float x1 = map(i,     0, DISPLAY_SAMPLES - 1, 0, width);
    float x2 = map(i + 1, 0, DISPLAY_SAMPLES - 1, 0, width);
    float y1 = map(samples[i1], 0, ADC_MAX, height, 0);
    float y2 = map(samples[i2], 0, ADC_MAX, height, 0);
    line(x1, y1, x2, y2);
  }

  fill(200);
  noStroke();
  textSize(12);
  text("p: 再生 / 1-4: 音色切替", 10, height - 10);
}

void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  try {
    samples[writeIdx] = constrain(Integer.parseInt(line), 0, ADC_MAX);
    writeIdx = (writeIdx + 1) % samples.length;
  } catch (NumberFormatException e) {
  }
}

void playSong() {
  out.pauseNotes();
  for (int i = 0; i < melody.length; i++) {
    out.playNote(startTime[i], duration[i],
      new SimpleInstrument(Frequency.ofPitch(melody[i]).asHz(), waveform));
  }
  out.resumeNotes();
}

void keyPressed() {
  switch (key) {
    case '1': waveform = Waves.SINE;     break;
    case '2': waveform = Waves.TRIANGLE; break;
    case '3': waveform = Waves.SAW;      break;
    case '4': waveform = Waves.SQUARE;   break;
    case 'p': playSong(); break;
  }
}
