import ddf.minim.*;
import ddf.minim.ugens.*;

final int BPM = 96;
final int NOTE_ON = 0x01;
final int REST = 0x04;
final int MAX_HARMONICS = 12;
final int KICK_DRUM = 36;
final int SNARE_DRUM = 38;
final int CLOSED_HI_HAT = 42;
final int CRASH_CYMBAL = 49;
// week10版は発表前確認用に、全体音量を week9 より大きめにする。
final float MASTER_GAIN = 1.35f;
// 拍位置は変えず、金管の音の立ち上がりだけを速くしてドラムとの聴感上のズレを減らす。
final float BRASS_ATTACK_SCALE = 0.45f;
final float RECORDED_DRUM_GAIN = 2.6f;
final float FLUTE_SAMPLE_GAIN = 1.32f;
// week10/kaeru_score_week10_adjusted/data/ に同梱した音色JSONを読む。外部参照は不要。
final String SOURCE_DATA_DIRECTORY = "data/";

final String[] DRUM_INSTRUMENT_FILES = {
  "kick.tweaked.instrument.json",
  "snare.tweaked.instrument.json",
  "Hi-hat.tweaked.instrument.json",
  "crash.tweaked.instrument.json"
};

Minim minim;
AudioOutput out;
TimbreData[] brassTimbres;
TimbreData[] drumTimbres;
AudioSample[] recordedDrumSamples;
ScoreEvent[] drumScore;
String currentMode = "P キーで4声の主旋律と4/4ドラムを再生します";

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

class PartDefinition {
  String name;
  String instrumentFile;
  int startBeat;
  int octaveShift;
  float amplitude;

  PartDefinition(String name, String instrumentFile, int startBeat, int octaveShift, float amplitude) {
    this.name = name;
    this.instrumentFile = instrumentFile;
    this.startBeat = startBeat;
    this.octaveShift = octaveShift;
    this.amplitude = amplitude;
  }
}

// 4パートともこの同じ譜面を使い、PartDefinition の octaveShift だけで音域を変える。
final PartDefinition[] MELODY_PARTS = {
  new PartDefinition("主旋律1 / フルート",     "flute.tweaked.instrument.json",     0,  12, 0.28f), // C5〜A5
  new PartDefinition("主旋律2 / トランペット", "trumpets.tweaked.instrument.json",  8,  12, 0.22f), // C5〜A5
  new PartDefinition("主旋律3 / トロンボーン", "trombones.tweaked.instrument.json", 16, -12, 0.22f), // C3〜A3
  new PartDefinition("主旋律4 / オルガン",     "organ.tweaked.instrument.json",     24, -12, 0.25f)  // C3〜A3
};
final float DRUM_AMPLITUDE = 0.095f;

class TimbreData {
  String name;
  float fundamentalHz;
  float[] harmonicRatios;
  float[] harmonicGains;
  float noiseLevel;
  float attackSec;
  float decaySec;
  float sustainLevel;
  float releaseSec;
  float[] drumSample;
  float drumSampleRate;
  float[] toneSample;
  float toneSampleRate;
  int toneRootMidiNote;
  int toneLoopStartSample;
  int toneLoopEndSample;

  TimbreData(String filename) {
    JSONObject json = loadJSONObject(sketchPath(SOURCE_DATA_DIRECTORY + filename));
    if (json == null) {
      throw new RuntimeException("音色 JSON を読み込めません: " + filename);
    }

    name = json.getString("name");
    fundamentalHz = json.getFloat("fundamental_hz", 440.0f);
    JSONObject sourceEnvelope = json.getJSONObject("envelope");
    attackSec = sourceEnvelope.getFloat("attack_sec");
    decaySec = sourceEnvelope.getFloat("decay_sec");
    sustainLevel = sourceEnvelope.getFloat("sustain_level");
    releaseSec = sourceEnvelope.getFloat("release_sec");
    noiseLevel = json.hasKey("noise") ? json.getJSONObject("noise").getFloat("level", 0) : 0;

    JSONArray sourceHarmonics = json.getJSONArray("harmonics");
    int harmonicCount = min(MAX_HARMONICS, sourceHarmonics.size());
    harmonicRatios = new float[harmonicCount];
    harmonicGains = new float[harmonicCount];
    float gainSum = 0;
    for (int i = 0; i < harmonicCount; i++) {
      JSONObject harmonic = sourceHarmonics.getJSONObject(i);
      harmonicRatios[i] = harmonic.getFloat("ratio");
      harmonicGains[i] = harmonic.getFloat("amp");
      gainSum += harmonicGains[i];
    }
    if (gainSum <= 0) {
      throw new RuntimeException("倍音の振幅合計が 0 以下です: " + filename);
    }
    for (int i = 0; i < harmonicCount; i++) {
      harmonicGains[i] /= gainSum;
    }

    // フルートなどの持続楽器が持つ原音本体サンプル。倍音合成より原音感を優先して鳴らす。
    if (json.hasKey("tone_sample")) {
      JSONObject sourceToneSample = json.getJSONObject("tone_sample");
      JSONArray sourceValues = sourceToneSample.getJSONArray("values");
      if (sourceValues != null && sourceValues.size() > 0) {
        toneSample = new float[sourceValues.size()];
        for (int i = 0; i < toneSample.length; i++) {
          toneSample[i] = sourceValues.getFloat(i);
        }
        toneSampleRate = sourceToneSample.getFloat("sample_rate", 22050.0f);
        toneRootMidiNote = sourceToneSample.getInt("root_midi_note", json.getInt("midi_note", 60));
        toneLoopStartSample = sourceToneSample.getInt("loop_start_sample", max(0, round(sourceToneSample.getFloat("loop_start_sec", 0) * toneSampleRate)));
        toneLoopEndSample = sourceToneSample.getInt("loop_end_sample", min(toneSample.length, round(sourceToneSample.getFloat("loop_end_sec", toneSample.length / toneSampleRate) * toneSampleRate)));
        toneLoopStartSample = constrain(toneLoopStartSample, 0, max(0, toneSample.length - 2));
        toneLoopEndSample = constrain(toneLoopEndSample, toneLoopStartSample + 2, toneSample.length);
      }
    }

    // 打楽器プロファイルが持つ原音1打。クラッシュではこの非周期波形を優先する。
    if (json.hasKey("drum_sample")) {
      JSONObject sourceDrumSample = json.getJSONObject("drum_sample");
      JSONArray sourceValues = sourceDrumSample.getJSONArray("values");
      if (sourceValues != null && sourceValues.size() > 0) {
        drumSample = new float[sourceValues.size()];
        for (int i = 0; i < drumSample.length; i++) {
          drumSample[i] = sourceValues.getFloat(i);
        }
        drumSampleRate = sourceDrumSample.getFloat("sample_rate", 44100.0f);
      }
    }
  }
}

// 「かえるのうた」の基準譜。C4〜A4 を基準にして、各パートがオクターブ移調して演奏する。
ScoreEvent[] MELODY_SCORE = {
  new ScoreEvent( 0, 60, 96, 256, NOTE_ON), new ScoreEvent( 1, 62, 96, 256, NOTE_ON),
  new ScoreEvent( 2, 64, 96, 256, NOTE_ON), new ScoreEvent( 3, 65, 96, 256, NOTE_ON),
  new ScoreEvent( 4, 64, 96, 256, NOTE_ON), new ScoreEvent( 5, 62, 96, 256, NOTE_ON),
  new ScoreEvent( 6, 60, 96, 512, NOTE_ON), new ScoreEvent( 7,  0,  0, 256, REST),
  new ScoreEvent( 8, 64, 92, 256, NOTE_ON), new ScoreEvent( 9, 65, 92, 256, NOTE_ON),
  new ScoreEvent(10, 67, 92, 256, NOTE_ON), new ScoreEvent(11, 69, 92, 256, NOTE_ON),
  new ScoreEvent(12, 67, 92, 256, NOTE_ON), new ScoreEvent(13, 65, 92, 256, NOTE_ON),
  new ScoreEvent(14, 64, 96, 512, NOTE_ON), new ScoreEvent(15,  0,  0, 256, REST),
  new ScoreEvent(16, 60, 90, 256, NOTE_ON), new ScoreEvent(17,  0,  0, 256, REST),
  new ScoreEvent(18, 60, 90, 256, NOTE_ON), new ScoreEvent(19,  0,  0, 256, REST),
  new ScoreEvent(20, 60, 90, 256, NOTE_ON), new ScoreEvent(21,  0,  0, 256, REST),
  new ScoreEvent(22, 60, 90, 256, NOTE_ON), new ScoreEvent(23,  0,  0, 256, REST),
  new ScoreEvent(24, 60, 96, 128, NOTE_ON, 60, 96, 128, 128),
  new ScoreEvent(25, 62, 96, 128, NOTE_ON, 62, 96, 128, 128),
  new ScoreEvent(26, 64, 96, 128, NOTE_ON, 64, 96, 128, 128),
  new ScoreEvent(27, 65, 96, 128, NOTE_ON, 65, 96, 128, 128),
  new ScoreEvent(28, 64, 96, 256, NOTE_ON), new ScoreEvent(29, 62, 96, 256, NOTE_ON),
  new ScoreEvent(30, 60,100, 512, NOTE_ON), new ScoreEvent(31,  0,  0, 256, REST)
};

// 56拍: 4声目（24拍遅れのチューバ）が終わる位置まで支える。
// week10版では4分の4拍子が分かりやすいように、
// 各小節の1・3拍目をキック、2・4拍目をスネアにする。
// 各声部の入り（0/8/16/24拍）と最後の拍だけクラッシュ+キックで強調する。
ScoreEvent[] createDrumScore() {
  ScoreEvent[] score = new ScoreEvent[56];
  for (int beat = 0; beat < score.length; beat++) {
    int beatInBar = beat % 4;
    boolean strongBeat = beatInBar == 0;
    boolean kickBeat = beatInBar == 0 || beatInBar == 2;
    int note = kickBeat ? KICK_DRUM : SNARE_DRUM;
    int velocity = kickBeat ? (strongBeat ? 86 : 78) : 74;

    // 各声部の入りと最後の拍は、クラッシュとキックを同時に鳴らす。
    if (beat == 0 || beat == 8 || beat == 16 || beat == 24 || beat == 55) {
      int crashVelocity = beat == 55 ? 92 : 84;
      int kickVelocity = beat == 55 ? 86 : 82;
      score[beat] = new ScoreEvent(beat, CRASH_CYMBAL, crashVelocity, 256, NOTE_ON,
                                   KICK_DRUM, kickVelocity, 0, 256);
      continue;
    }

    score[beat] = new ScoreEvent(beat, note, velocity, 256, NOTE_ON);
  }
  return score;
}

class BrassNote implements Instrument {
  Summer mix;
  ADSR envelope;

  BrassNote(float frequency, float amplitude, TimbreData timbre) {
    mix = new Summer();
    for (int i = 0; i < timbre.harmonicRatios.length; i++) {
      Oscil harmonic = new Oscil(frequency * timbre.harmonicRatios[i],
                                 amplitude * timbre.harmonicGains[i], Waves.SINE);
      harmonic.patch(mix);
    }
    float attack = max(0.003f, timbre.attackSec * BRASS_ATTACK_SCALE);
    envelope = new ADSR(1.0f, attack, timbre.decaySec,
                        timbre.sustainLevel, timbre.releaseSec);
    mix.patch(envelope);
  }

  void noteOn(float duration) { envelope.noteOn(); envelope.patch(out); }
  void noteOff() { envelope.unpatchAfterRelease(out); envelope.noteOff(); }
}

class ToneSampleUGen extends UGen {
  float[] sample;
  float sourceSampleRate;
  float position;
  float step;
  float pitchRatio;
  float lastOutputSampleRate;
  int loopStart;
  int loopEnd;

  ToneSampleUGen(TimbreData timbre, int midiNote) {
    sample = timbre.toneSample;
    sourceSampleRate = timbre.toneSampleRate;
    loopStart = timbre.toneLoopStartSample;
    loopEnd = timbre.toneLoopEndSample;
    position = 0;
    pitchRatio = pow(2.0f, (midiNote - timbre.toneRootMidiNote) / 12.0f);
    lastOutputSampleRate = 0;
  }

  protected void uGenerate(float[] channels) {
    if (sample == null || sample.length == 0) {
      for (int i = 0; i < channels.length; i++) channels[i] = 0;
      return;
    }
    float outputSampleRate = max(1.0f, sampleRate());
    if (outputSampleRate != lastOutputSampleRate) {
      step = pitchRatio * sourceSampleRate / outputSampleRate;
      lastOutputSampleRate = outputSampleRate;
    }

    if (position >= loopEnd) {
      float loopLength = max(1, loopEnd - loopStart);
      position = loopStart + ((position - loopStart) % loopLength);
    }

    int i0 = constrain(floor(position), 0, sample.length - 1);
    int i1 = min(i0 + 1, sample.length - 1);
    float frac = position - i0;
    float value = lerp(sample[i0], sample[i1], frac);
    position += step;
    for (int i = 0; i < channels.length; i++) channels[i] = value;
  }
}

class SampledMelodyNote implements Instrument {
  ToneSampleUGen tone;
  ADSR envelope;

  SampledMelodyNote(int midiNote, float amplitude, TimbreData timbre) {
    tone = new ToneSampleUGen(timbre, midiNote);
    envelope = new ADSR(constrain(amplitude * FLUTE_SAMPLE_GAIN, 0.0f, 1.0f),
                        0.004f, 0.04f, 0.92f, max(0.08f, timbre.releaseSec * 0.45f));
    tone.patch(envelope);
  }

  void noteOn(float duration) { envelope.noteOn(); envelope.patch(out); }
  void noteOff() { envelope.unpatchAfterRelease(out); envelope.noteOff(); }
}

class DrumNote implements Instrument {
  Summer mix;
  Noise noise;
  ADSR envelope;

  DrumNote(int noteNumber, float amplitude) {
    mix = new Summer();
    TimbreData timbre = drumTimbres[drumIndex(noteNumber)];
    for (int i = 0; i < timbre.harmonicRatios.length; i++) {
      Oscil harmonic = new Oscil(timbre.fundamentalHz * timbre.harmonicRatios[i],
                                 amplitude * timbre.harmonicGains[i], Waves.SINE);
      harmonic.patch(mix);
    }
    float noiseAmplitude = amplitude * timbre.noiseLevel * drumNoiseScale(noteNumber);
    if (noiseAmplitude > 0.001f) {
      noise = new Noise(noiseAmplitude, Noise.Tint.WHITE);
      noise.patch(mix);
    }
    envelope = new ADSR(1.0f, timbre.attackSec, timbre.decaySec,
                        timbre.sustainLevel, timbre.releaseSec);
    mix.patch(envelope);
  }

  void noteOn(float duration) { envelope.noteOn(); envelope.patch(out); }
  void noteOff() { envelope.unpatchAfterRelease(out); envelope.noteOff(); }
}

// ドラムJSONに原音1打があれば優先して再生する。サンプルがないJSONは従来どおり合成する。
class RecordedDrumNote implements Instrument {
  AudioSample sample;
  float amplitude;

  RecordedDrumNote(AudioSample sample, float amplitude) {
    this.sample = sample;
    this.amplitude = amplitude;
  }

  void noteOn(float duration) {
    sample.setGain(linearToDecibels(constrain(amplitude * RECORDED_DRUM_GAIN, 0.001f, 1.0f)));
    sample.trigger();
  }

  // 原音に含まれる自然な減衰を最後まで鳴らすため、譜面上の短い長さでは停止しない。
  void noteOff() {
  }
}

void setup() {
  size(940, 490);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  out.setTempo(BPM);
  brassTimbres = new TimbreData[MELODY_PARTS.length];
  for (int i = 0; i < MELODY_PARTS.length; i++) brassTimbres[i] = new TimbreData(MELODY_PARTS[i].instrumentFile);
  drumTimbres = new TimbreData[DRUM_INSTRUMENT_FILES.length];
  for (int i = 0; i < DRUM_INSTRUMENT_FILES.length; i++) drumTimbres[i] = new TimbreData(DRUM_INSTRUMENT_FILES[i]);
  recordedDrumSamples = new AudioSample[drumTimbres.length];
  for (int i = 0; i < drumTimbres.length; i++) recordedDrumSamples[i] = createRecordedDrumSample(drumTimbres[i]);
  drumScore = createDrumScore();
  textFont(createFont("SansSerif", 16));
  // 起動直後には再生しない。P キー、または 1〜5 キーで再生する。
}

void draw() {
  background(248, 246, 242);
  fill(34);
  textSize(26);
  text("かえるのうた 4声輪唱・week10 フルート/オルガン版", 28, 42);
  textSize(15);
  text("固定テンポ: " + BPM + " BPM   共通主旋律: " + MELODY_SCORE.length + " 拍   ドラム: " + drumScore.length + " 拍   全体音量倍率: x" + nf(MASTER_GAIN, 1, 2), 28, 72);
  text("P: 全パート再生    1-5: 単独再生    再生完了後に次のキーを押してください", 28, 98);
  for (int part = 0; part < MELODY_PARTS.length; part++) {
    PartDefinition definition = MELODY_PARTS[part];
    int y = 146 + part * 42;
    fill(34);
    text(definition.name + "   開始拍 = " + definition.startBeat + "   オクターブ = " + octaveLabel(definition.octaveShift), 28, y);
    fill(70 + part * 24, 130, 180);
    rect(410 + definition.startBeat * 7, y - 14, MELODY_SCORE.length * 7, 14, 3);
  }
  fill(34);
  text("リズム / ドラム   開始拍 = 0   4/4 = 1・3拍キック / 2・4拍スネア", 28, 314);
  fill(176, 112, 90);
  rect(410, 300, drumScore.length * 7, 14, 3);
  fill(34);
  text(currentMode, 28, 368);
  textSize(13);
  text("共通譜をオクターブ移調: フルート C5〜A5 / トランペット C5〜A5 / トロンボーン C3〜A3 / オルガン C3〜A3", 28, 410);
  text("ドラム: 56拍の4/4パターン。声部の入りと最後だけクラッシュ+キックで強調", 28, 434);
  text("音色 JSON はこのスケッチの data/ フォルダを参照", 28, 456);
}

void keyPressed() {
  if (key == 'p' || key == 'P') playAllParts();
  else if (key >= '1' && key <= '5') playPart(key - '1');
}

void playAllParts() {
  out.pauseNotes();
  for (int part = 0; part < MELODY_PARTS.length + 1; part++) schedulePart(part);
  out.resumeNotes();
  currentMode = "4声の主旋律輪唱（フルート高音・オルガン低音）と、音量を上げた4/4ドラムを再生中です。";
}

void playPart(int part) {
  out.pauseNotes();
  schedulePart(part);
  out.resumeNotes();
  currentMode = "単独再生中: " + partName(part) + "。";
}

void schedulePart(int part) {
  ScoreEvent[] score = part == MELODY_PARTS.length ? drumScore : MELODY_SCORE;
  int startBeat = part == MELODY_PARTS.length ? 0 : MELODY_PARTS[part].startBeat;
  for (ScoreEvent event : score) {
    if (event.isRest()) continue;
    float amplitude = partAmplitude(part) * event.velocity / 127.0f * MASTER_GAIN;
    float start = startBeat + event.beatAt;
    out.playNote(start, event.durationQ8 / 256.0f, noteInstrument(part, event.noteNumber, amplitude));
    if (event.subNote != 0 && event.subVelocity > 0) {
      float subAmplitude = partAmplitude(part) * event.subVelocity / 127.0f * MASTER_GAIN;
      out.playNote(start + event.subOffsetQ8 / 256.0f, event.subDurationQ8 / 256.0f,
                   noteInstrument(part, event.subNote, subAmplitude));
    }
  }
}

Instrument noteInstrument(int part, int noteNumber, float amplitude) {
  if (part == MELODY_PARTS.length) {
    AudioSample sample = recordedDrumSamples[drumIndex(noteNumber)];
    if (sample != null) return new RecordedDrumNote(sample, amplitude);
    return new DrumNote(noteNumber, amplitude);
  }
  int shiftedNote = noteNumber + MELODY_PARTS[part].octaveShift;
  if (brassTimbres[part].toneSample != null) {
    return new SampledMelodyNote(shiftedNote, amplitude, brassTimbres[part]);
  }
  return new BrassNote(midiToFrequency(shiftedNote), amplitude, brassTimbres[part]);
}

AudioSample createRecordedDrumSample(TimbreData timbre) {
  if (timbre.drumSample == null || timbre.drumSample.length == 0) return null;
  javax.sound.sampled.AudioFormat format = new javax.sound.sampled.AudioFormat(
    timbre.drumSampleRate, 16, 1, true, true
  );
  return minim.createSample(timbre.drumSample, format, 1024);
}

float partAmplitude(int part) { return part == MELODY_PARTS.length ? DRUM_AMPLITUDE : MELODY_PARTS[part].amplitude; }
String partName(int part) { return part == MELODY_PARTS.length ? "リズム / ドラム" : MELODY_PARTS[part].name; }
String octaveLabel(int semitones) { return (semitones > 0 ? "+" : "") + (semitones / 12) + " octave"; }

int drumIndex(int noteNumber) {
  if (noteNumber == KICK_DRUM) return 0;
  if (noteNumber == SNARE_DRUM) return 1;
  if (noteNumber == CLOSED_HI_HAT) return 2;
  if (noteNumber == CRASH_CYMBAL) return 3;
  return 2;
}

float drumNoiseScale(int noteNumber) {
  if (noteNumber == KICK_DRUM) return 0.14f;
  if (noteNumber == SNARE_DRUM) return 0.45f;
  if (noteNumber == CRASH_CYMBAL) return 0.30f;
  return 0.42f;
}

float linearToDecibels(float amplitude) { return 20.0f * log(amplitude) / log(10.0f); }
float midiToFrequency(int midiNote) { return 440.0f * pow(2.0f, (midiNote - 69) / 12.0f); }
