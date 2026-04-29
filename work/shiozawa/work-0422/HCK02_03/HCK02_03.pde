// 発展課題: マイク入力を FFT して周波数スペクトルを表示する。

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.FFT;

// 自分の環境のポート名に書き換える
final String PORT_NAME   = "/dev/cu.usbmodem34B7DA64482C2";
final int    BAUD        = 921600;
final int    ADC_MAX     = 1023;
final float  SAMPLE_RATE = 5000.0;
final int    FFT_SIZE    = 512;

Serial  port;
int[]   samples;
int     sampleIdx = 0;
float[] fftInput;
FFT     fft;

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
  size(900, 500);
  minim    = new Minim(this);
  out      = minim.getLineOut();
  out.setTempo(120);
  waveform = Waves.SINE;

  samples  = new int[width];
  for (int i = 0; i < samples.length; i++) samples[i] = ADC_MAX / 2;

  fft      = new FFT(FFT_SIZE, SAMPLE_RATE);
  fftInput = new float[FFT_SIZE];

  port = new Serial(this, PORT_NAME, BAUD);
  port.bufferUntil('\n');
}

void draw() {
  background(0);

  // FFT 用にサンプルを正規化
  for (int i = 0; i < FFT_SIZE; i++) {
    int idx = (sampleIdx - FFT_SIZE + i + samples.length) % samples.length;
    fftInput[i] = (samples[idx] - ADC_MAX / 2.0) / (ADC_MAX / 2.0);
  }
  fft.forward(fftInput);

  drawSpectrum();

  
}

void drawSpectrum() {
  float top    = 20;
  float bottom = height - 30;
  int   bins   = fft.specSize();
  float barW   = (float) width / bins;

  noStroke();
  fill(120, 200, 255);
  for (int i = 0; i < bins; i++) {
    float h = constrain(fft.getBand(i) / 30.0, 0, 1) * (bottom - top);
    rect(i * barW, bottom - h, barW - 1, h);
  }
}

void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  try {
    samples[sampleIdx] = constrain(Integer.parseInt(line), 0, ADC_MAX);
    sampleIdx = (sampleIdx + 1) % samples.length;
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
