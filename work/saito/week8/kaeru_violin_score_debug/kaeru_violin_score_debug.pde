import ddf.minim.*;
import ddf.minim.ugens.*;

final int BPM = 96;
final int NOTE_ON = 0x01;
final int REST = 0x04;
final int MAX_HARMONICS = 28;
final String VIOLIN_FILE = "violin.tweaked.instrument.json";
final float VIOLIN_AMPLITUDE = 0.18f;

Minim minim;
AudioOutput out;
TimbreData violin;
String currentMode = "P キーでヴァイオリン単体のかえるのうたを再生します";

class ScoreEvent {
  int beatAt;
  int noteNumber;
  int velocity;
  int durationQ8;
  int flags;
  int subNote;
  int subVelocity;
  int subOffsetQ8;
  int subDurationQ8;

  ScoreEvent(int beatAt, int noteNumber, int velocity, int durationQ8, int flags) {
    this(beatAt, noteNumber, velocity, durationQ8, flags, 0, 0, 0, 0);
  }

  ScoreEvent(int beatAt, int noteNumber, int velocity, int durationQ8, int flags,
             int subNote, int subVelocity, int subOffsetQ8, int subDurationQ8) {
    this.beatAt = beatAt;
    this.noteNumber = noteNumber;
    this.velocity = velocity;
    this.durationQ8 = durationQ8;
    this.flags = flags;
    this.subNote = subNote;
    this.subVelocity = subVelocity;
    this.subOffsetQ8 = subOffsetQ8;
    this.subDurationQ8 = subDurationQ8;
  }

  boolean isRest() {
    return noteNumber == 0 || (flags & REST) != 0;
  }
}

class TimbreData {
  String name;
  float[] harmonicRatios;
  float[] harmonicGains;
  float noiseLevel;
  float attackSec;
  float decaySec;
  float sustainLevel;
  float releaseSec;
  float vibratoRateHz;
  float vibratoDepthCents;
  float vibratoOnsetSec;
  float chorusMix;
  float chorusDepth;

  TimbreData(String filename) {
    JSONObject json = loadJSONObject(filename);
    if (json == null) {
      throw new RuntimeException("音色 JSON を読み込めません: " + filename);
    }

    name = json.getString("name");
    JSONObject sourceEnvelope = json.getJSONObject("envelope");
    attackSec = max(0.04f, sourceEnvelope.getFloat("attack_sec"));
    decaySec = max(0.05f, sourceEnvelope.getFloat("decay_sec"));
    sustainLevel = constrain(sourceEnvelope.getFloat("sustain_level"), 0.0f, 1.0f);
    releaseSec = max(0.08f, sourceEnvelope.getFloat("release_sec"));

    noiseLevel = 0;
    if (json.hasKey("noise")) {
      JSONObject sourceNoise = json.getJSONObject("noise");
      noiseLevel = sourceNoise.getFloat("level", 0);
    }

    vibratoRateHz = 5.4f;
    vibratoDepthCents = 14.0f;
    vibratoOnsetSec = 0.14f;
    if (json.hasKey("modulation")) {
      JSONObject modulation = json.getJSONObject("modulation");
      if (modulation.hasKey("vibrato")) {
        JSONObject vibrato = modulation.getJSONObject("vibrato");
        vibratoRateHz = vibrato.getFloat("rate_hz", vibratoRateHz);
        vibratoDepthCents = vibrato.getFloat("depth_cents", vibratoDepthCents);
        vibratoOnsetSec = vibrato.getFloat("onset_sec", vibratoOnsetSec);
      }
    }

    chorusMix = 0.18f;
    chorusDepth = 0.30f;
    if (json.hasKey("fx")) {
      JSONObject fx = json.getJSONObject("fx");
      if (fx.hasKey("chorus")) {
        JSONObject chorus = fx.getJSONObject("chorus");
        chorusMix = chorus.getFloat("mix", chorusMix);
        chorusDepth = chorus.getFloat("depth", chorusDepth);
      }
    }

    JSONArray sourceHarmonics = json.getJSONArray("harmonics");
    int harmonicCount = min(MAX_HARMONICS, sourceHarmonics.size());
    harmonicRatios = new float[harmonicCount];
    harmonicGains = new float[harmonicCount];

    float gainSum = 0;
    for (int i = 0; i < harmonicCount; i++) {
      JSONObject harmonic = sourceHarmonics.getJSONObject(i);
      harmonicRatios[i] = harmonic.getFloat("ratio");
      harmonicGains[i] = harmonic.getFloat("amp");
      // 高次倍音を少し抑えて、合成臭い金属感を減らす。
      harmonicGains[i] *= 1.0f / (1.0f + i * 0.035f);
      gainSum += harmonicGains[i];
    }

    if (gainSum <= 0) {
      throw new RuntimeException("倍音の振幅合計が 0 以下です: " + filename);
    }

    for (int i = 0; i < harmonicCount; i++) {
      harmonicGains[i] /= gainSum;
    }
  }
}

// 「かえるのうた」のハ長調主旋律。配列の1要素を1拍として扱う。
ScoreEvent[] VIOLIN_SCORE = {
  new ScoreEvent( 0, 60,  96, 256, NOTE_ON), // C4
  new ScoreEvent( 1, 62,  96, 256, NOTE_ON), // D4
  new ScoreEvent( 2, 64,  98, 256, NOTE_ON), // E4
  new ScoreEvent( 3, 65,  98, 256, NOTE_ON), // F4
  new ScoreEvent( 4, 64,  96, 256, NOTE_ON), // E4
  new ScoreEvent( 5, 62,  96, 256, NOTE_ON), // D4
  new ScoreEvent( 6, 60, 102, 512, NOTE_ON), // C4、2拍
  new ScoreEvent( 7,  0,   0, 256, REST),
  new ScoreEvent( 8, 64,  94, 256, NOTE_ON), // E4
  new ScoreEvent( 9, 65,  94, 256, NOTE_ON), // F4
  new ScoreEvent(10, 67,  98, 256, NOTE_ON), // G4
  new ScoreEvent(11, 69, 100, 256, NOTE_ON), // A4
  new ScoreEvent(12, 67,  96, 256, NOTE_ON), // G4
  new ScoreEvent(13, 65,  94, 256, NOTE_ON), // F4
  new ScoreEvent(14, 64, 100, 512, NOTE_ON), // E4、2拍
  new ScoreEvent(15,  0,   0, 256, REST),

  new ScoreEvent(16, 60,  88, 256, NOTE_ON), // C4
  new ScoreEvent(17,  0,   0, 256, REST),
  new ScoreEvent(18, 60,  90, 256, NOTE_ON), // C4
  new ScoreEvent(19,  0,   0, 256, REST),
  new ScoreEvent(20, 60,  92, 256, NOTE_ON), // C4
  new ScoreEvent(21,  0,   0, 256, REST),
  new ScoreEvent(22, 60,  96, 256, NOTE_ON), // C4
  new ScoreEvent(23,  0,   0, 256, REST),

  new ScoreEvent(24, 60,  96, 128, NOTE_ON, 60,  92, 128, 128), // C4 C4
  new ScoreEvent(25, 62,  96, 128, NOTE_ON, 62,  92, 128, 128), // D4 D4
  new ScoreEvent(26, 64,  98, 128, NOTE_ON, 64,  94, 128, 128), // E4 E4
  new ScoreEvent(27, 65,  98, 128, NOTE_ON, 65,  94, 128, 128), // F4 F4
  new ScoreEvent(28, 64,  96, 256, NOTE_ON), // E4
  new ScoreEvent(29, 62,  96, 256, NOTE_ON), // D4
  new ScoreEvent(30, 60, 104, 512, NOTE_ON), // C4、2拍
  new ScoreEvent(31,  0,   0, 256, REST)
};

class ViolinSynthNote implements Instrument {
  Summer mix;
  ADSR envelope;
  Oscil[] tones;
  Oscil[] vibratos;
  Oscil[] chorusTones;
  Oscil[] chorusVibratos;
  Constant[] baseFrequencies;
  Constant[] chorusBaseFrequencies;
  Summer[] frequencyControls;
  Summer[] chorusFrequencyControls;
  Noise bowNoise;

  ViolinSynthNote(float frequency, float amplitude, TimbreData timbre) {
    mix = new Summer();
    tones = new Oscil[timbre.harmonicRatios.length];
    vibratos = new Oscil[timbre.harmonicRatios.length];
    chorusTones = new Oscil[timbre.harmonicRatios.length];
    chorusVibratos = new Oscil[timbre.harmonicRatios.length];
    baseFrequencies = new Constant[timbre.harmonicRatios.length];
    chorusBaseFrequencies = new Constant[timbre.harmonicRatios.length];
    frequencyControls = new Summer[timbre.harmonicRatios.length];
    chorusFrequencyControls = new Summer[timbre.harmonicRatios.length];

    float chorusAmount = constrain(timbre.chorusMix, 0.0f, 0.35f);
    float detuneCents = 4.5f + timbre.chorusDepth * 3.0f;
    float detuneRatio = pow(2.0f, detuneCents / 1200.0f);
    float vibScale = pow(2.0f, timbre.vibratoDepthCents / 1200.0f) - 1.0f;

    for (int i = 0; i < tones.length; i++) {
      float partialFrequency = frequency * timbre.harmonicRatios[i];
      float partialAmplitude = amplitude * timbre.harmonicGains[i] * (1.0f - chorusAmount * 0.35f);
      tones[i] = new Oscil(partialFrequency, partialAmplitude, Waves.SINE);
      tones[i].setPhase((i % 4) * 0.17f);

      frequencyControls[i] = new Summer();
      baseFrequencies[i] = new Constant(partialFrequency);
      vibratos[i] = new Oscil(timbre.vibratoRateHz, partialFrequency * vibScale, Waves.SINE);
      baseFrequencies[i].patch(frequencyControls[i]);
      vibratos[i].patch(frequencyControls[i]);
      frequencyControls[i].patch(tones[i].frequency);
      tones[i].patch(mix);

      float chorusFrequency = partialFrequency * detuneRatio;
      float chorusAmplitude = amplitude * timbre.harmonicGains[i] * chorusAmount;
      chorusTones[i] = new Oscil(chorusFrequency, chorusAmplitude, Waves.SINE);
      chorusTones[i].setPhase(0.37f + (i % 5) * 0.11f);
      chorusFrequencyControls[i] = new Summer();
      chorusBaseFrequencies[i] = new Constant(chorusFrequency);
      chorusVibratos[i] = new Oscil(timbre.vibratoRateHz * 1.04f, chorusFrequency * vibScale * 0.85f, Waves.SINE);
      chorusBaseFrequencies[i].patch(chorusFrequencyControls[i]);
      chorusVibratos[i].patch(chorusFrequencyControls[i]);
      chorusFrequencyControls[i].patch(chorusTones[i].frequency);
      chorusTones[i].patch(mix);
    }

    float noiseAmplitude = amplitude * max(0.035f, timbre.noiseLevel * 2.6f);
    bowNoise = new Noise(noiseAmplitude, Noise.Tint.WHITE);
    bowNoise.patch(mix);

    envelope = new ADSR(1.0f, timbre.attackSec, timbre.decaySec,
                        timbre.sustainLevel, timbre.releaseSec);
    mix.patch(envelope);
  }

  void noteOn(float duration) {
    envelope.noteOn();
    envelope.patch(out);
  }

  void noteOff() {
    envelope.unpatchAfterRelease(out);
    envelope.noteOff();
  }
}

void setup() {
  size(860, 380);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  out.setTempo(BPM);
  violin = new TimbreData(VIOLIN_FILE);
  textFont(createFont("SansSerif", 16));
  playViolin();
}

void draw() {
  background(248, 246, 242);
  fill(34);
  textSize(26);
  text("かえるのうた ヴァイオリン単体版", 28, 42);
  textSize(15);
  text("固定テンポ: " + BPM + " BPM   音域: C4〜A4   音色: " + violin.name + " / JSON合成", 28, 72);
  text("P: 再生   再生中に押すと音が重なるため、終わってから押してください", 28, 98);

  int baseX = 28;
  int baseY = 148;
  int beatW = 22;
  for (int i = 0; i < VIOLIN_SCORE.length; i++) {
    ScoreEvent event = VIOLIN_SCORE[i];
    int x = baseX + event.beatAt * beatW;
    if (event.isRest()) {
      fill(205);
      rect(x, baseY + 46, beatW - 4, 10, 2);
      continue;
    }

    int y = baseY + (69 - event.noteNumber) * 5;
    fill(78, 120, 174);
    rect(x, y, beatW - 4, 24, 3);
    fill(34);
    textSize(10);
    text(midiName(event.noteNumber), x, y - 4);
    if (event.subNote != 0) {
      fill(112, 154, 198);
      rect(x + beatW / 2, y + 26, beatW / 2 - 4, 18, 3);
    }
  }

  fill(34);
  textSize(15);
  text(currentMode, 28, 315);
  textSize(13);
  text("Processing 側では harmonics / envelope / vibrato / noise / chorus風デチューンを使って合成しています。", 28, 342);
}

void keyPressed() {
  if (key == 'p' || key == 'P') {
    playViolin();
  }
}

void playViolin() {
  out.pauseNotes();
  for (ScoreEvent event : VIOLIN_SCORE) {
    if (event.isRest()) {
      continue;
    }
    scheduleEvent(event, event.noteNumber, event.velocity, 0, event.durationQ8);
    if (event.subNote != 0) {
      scheduleEvent(event, event.subNote, event.subVelocity, event.subOffsetQ8, event.subDurationQ8);
    }
  }
  out.resumeNotes();
  currentMode = "ヴァイオリン単体で再生中です。";
}

void scheduleEvent(ScoreEvent event, int noteNumber, int velocity, int offsetQ8, int durationQ8) {
  float startBeat = event.beatAt + offsetQ8 / 256.0f;
  float durationBeats = durationQ8 / 256.0f;
  float velocityScale = velocity / 127.0f;
  float amplitude = VIOLIN_AMPLITUDE * velocityScale;
  out.playNote(startBeat, durationBeats, new ViolinSynthNote(midiToFrequency(noteNumber), amplitude, violin));
}

float midiToFrequency(int midiNote) {
  return 440.0f * pow(2.0f, (midiNote - 69) / 12.0f);
}

String midiName(int midiNote) {
  String[] names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
  return names[midiNote % 12] + str(midiNote / 12 - 1);
}
