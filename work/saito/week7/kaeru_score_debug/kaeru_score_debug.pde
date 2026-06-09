import ddf.minim.*;
import ddf.minim.ugens.*;

final int BPM = 96;
final int NOTE_ON = 0x01;
final int REST = 0x04;
final int MAX_HARMONICS = 12;
final int DRUM_PART = 4;
final int KICK_DRUM = 36;
final int SNARE_DRUM = 38;
final int CLOSED_HI_HAT = 42;
final int CRASH_CYMBAL = 49;

final String[] PART_NAMES = {
  "主旋律1 / トランペット",
  "主旋律2 / ホルン",
  "主旋律3 / トロンボーン",
  "低音 / チューバ",
  "リズム / ドラム"
};

final String[] INSTRUMENT_FILES = {
  "trumpets.tweaked.instrument.json",
  "horns.tweaked.instrument.json",
  "trombones.tweaked.instrument.json",
  "tuba.tweaked.instrument.json"
};

final String[] DRUM_INSTRUMENT_FILES = {
  "kick.tweaked.instrument.json",
  "snare.tweaked.instrument.json",
  "Hi-hat.tweaked.instrument.json",
  "crash.tweaked.instrument.json"
};

final int[] START_BEATS = {0, 8, 16, 0, 0};
final float[] PART_AMPLITUDES = {0.20f, 0.17f, 0.15f, 0.13f, 0.24f};

Minim minim;
AudioOutput out;
TimbreData[] timbres;
TimbreData[] drumTimbres;
String currentMode = "P キーで主旋律3声、低音、ドラムを再生します";

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
  float fundamentalHz;
  float[] harmonicRatios;
  float[] harmonicGains;
  float noiseLevel;
  float attackSec;
  float decaySec;
  float sustainLevel;
  float releaseSec;

  TimbreData(String filename) {
    JSONObject json = loadJSONObject(filename);
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
    noiseLevel = 0;
    if (json.hasKey("noise")) {
      JSONObject sourceNoise = json.getJSONObject("noise");
      noiseLevel = sourceNoise.getFloat("level", 0);
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

// 「かえるのうた」のハ長調の主旋律。3つの金管パートで輪唱する。
// 配列の1要素を1拍とし、伸ばす音の後ろには休符を置いて
// Arduino に移した場合も拍位置がずれないようにする。
ScoreEvent[] MELODY_SCORE = {
  new ScoreEvent( 0, 60, 96, 256, NOTE_ON), // C4
  new ScoreEvent( 1, 62, 96, 256, NOTE_ON), // D4
  new ScoreEvent( 2, 64, 96, 256, NOTE_ON), // E4
  new ScoreEvent( 3, 65, 96, 256, NOTE_ON), // F4
  new ScoreEvent( 4, 64, 96, 256, NOTE_ON), // E4
  new ScoreEvent( 5, 62, 96, 256, NOTE_ON), // D4
  new ScoreEvent( 6, 60, 96, 512, NOTE_ON), // C4、2拍
  new ScoreEvent( 7,  0,  0, 256, REST),
  new ScoreEvent( 8, 64, 92, 256, NOTE_ON), // E4
  new ScoreEvent( 9, 65, 92, 256, NOTE_ON), // F4
  new ScoreEvent(10, 67, 92, 256, NOTE_ON), // G4
  new ScoreEvent(11, 69, 92, 256, NOTE_ON), // A4
  new ScoreEvent(12, 67, 92, 256, NOTE_ON), // G4
  new ScoreEvent(13, 65, 92, 256, NOTE_ON), // F4
  new ScoreEvent(14, 64, 96, 512, NOTE_ON), // E4、2拍
  new ScoreEvent(15,  0,  0, 256, REST),

  new ScoreEvent(16, 60, 90, 256, NOTE_ON), // C4
  new ScoreEvent(17,  0,  0, 256, REST),
  new ScoreEvent(18, 60, 90, 256, NOTE_ON), // C4
  new ScoreEvent(19,  0,  0, 256, REST),
  new ScoreEvent(20, 60, 90, 256, NOTE_ON), // C4
  new ScoreEvent(21,  0,  0, 256, REST),
  new ScoreEvent(22, 60, 90, 256, NOTE_ON), // C4
  new ScoreEvent(23,  0,  0, 256, REST),

  new ScoreEvent(24, 60, 96, 128, NOTE_ON, 60, 96, 128, 128), // C4 C4
  new ScoreEvent(25, 62, 96, 128, NOTE_ON, 62, 96, 128, 128), // D4 D4
  new ScoreEvent(26, 64, 96, 128, NOTE_ON, 64, 96, 128, 128), // E4 E4
  new ScoreEvent(27, 65, 96, 128, NOTE_ON, 65, 96, 128, 128), // F4 F4
  new ScoreEvent(28, 64, 96, 256, NOTE_ON), // E4
  new ScoreEvent(29, 62, 96, 256, NOTE_ON), // D4
  new ScoreEvent(30, 60, 100, 512, NOTE_ON), // C4、2拍
  new ScoreEvent(31,  0,   0, 256, REST)
};

// チューバ用の低音伴奏。C3、F2、G2 の長音で輪唱の和声を支える。
ScoreEvent[] BASS_SCORE = {
  new ScoreEvent( 0, 48, 84, 1024, NOTE_ON), // C3、4拍
  new ScoreEvent( 1,  0,  0, 256, REST),
  new ScoreEvent( 2,  0,  0, 256, REST),
  new ScoreEvent( 3,  0,  0, 256, REST),
  new ScoreEvent( 4, 43, 80, 512, NOTE_ON), // G2、2拍
  new ScoreEvent( 5,  0,  0, 256, REST),
  new ScoreEvent( 6, 48, 84, 512, NOTE_ON), // C3、2拍
  new ScoreEvent( 7,  0,  0, 256, REST),
  new ScoreEvent( 8, 48, 84, 512, NOTE_ON), // C3、2拍
  new ScoreEvent( 9,  0,  0, 256, REST),
  new ScoreEvent(10, 41, 80, 512, NOTE_ON), // F2、2拍
  new ScoreEvent(11,  0,  0, 256, REST),
  new ScoreEvent(12, 43, 80, 512, NOTE_ON), // G2、2拍
  new ScoreEvent(13,  0,  0, 256, REST),
  new ScoreEvent(14, 48, 84, 512, NOTE_ON), // C3、2拍
  new ScoreEvent(15,  0,  0, 256, REST),
  new ScoreEvent(16, 48, 84, 512, NOTE_ON), // C3、2拍
  new ScoreEvent(17,  0,  0, 256, REST),
  new ScoreEvent(18, 43, 80, 512, NOTE_ON), // G2、2拍
  new ScoreEvent(19,  0,  0, 256, REST),
  new ScoreEvent(20, 48, 84, 512, NOTE_ON), // C3、2拍
  new ScoreEvent(21,  0,  0, 256, REST),
  new ScoreEvent(22, 43, 80, 512, NOTE_ON), // G2、2拍
  new ScoreEvent(23,  0,  0, 256, REST),
  new ScoreEvent(24, 48, 84, 512, NOTE_ON), // C3、2拍
  new ScoreEvent(25,  0,  0, 256, REST),
  new ScoreEvent(26, 41, 80, 512, NOTE_ON), // F2、2拍
  new ScoreEvent(27,  0,  0, 256, REST),
  new ScoreEvent(28, 43, 82, 512, NOTE_ON), // G2、2拍
  new ScoreEvent(29,  0,  0, 256, REST),
  new ScoreEvent(30, 48, 88, 512, NOTE_ON), // C3、2拍
  new ScoreEvent(31,  0,  0, 256, REST),
  new ScoreEvent(32, 48, 84, 1024, NOTE_ON), // C3、4拍
  new ScoreEvent(33,  0,  0, 256, REST),
  new ScoreEvent(34,  0,  0, 256, REST),
  new ScoreEvent(35,  0,  0, 256, REST),
  new ScoreEvent(36, 43, 82, 512, NOTE_ON), // G2、2拍
  new ScoreEvent(37,  0,  0, 256, REST),
  new ScoreEvent(38, 48, 88, 512, NOTE_ON), // C3、2拍
  new ScoreEvent(39,  0,  0, 256, REST)
};

// ドラム用のリズム伴奏。キックとスネアを交互に置き、各拍にハイハットを重ねる。
// 8拍ごとの区切りと終止直前だけ少し強め、輪唱の流れを邪魔しないようにする。
// MIDI 打楽器番号を用い、ホルンとチューバが終わる40拍目で一緒に締める。
ScoreEvent[] DRUM_SCORE = {
  // 主旋律1の前半
  new ScoreEvent( 0, KICK_DRUM, 104, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent( 1, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent( 2, KICK_DRUM,  98, 64, NOTE_ON, CLOSED_HI_HAT, 54, 0, 48),
  new ScoreEvent( 3, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent( 4, KICK_DRUM, 104, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent( 5, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent( 6, KICK_DRUM,  98, 64, NOTE_ON, CLOSED_HI_HAT, 54, 0, 48),
  new ScoreEvent( 7, SNARE_DRUM,  98, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent( 8, KICK_DRUM, 104, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent( 9, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent(10, KICK_DRUM,  98, 64, NOTE_ON, CLOSED_HI_HAT, 54, 0, 48),
  new ScoreEvent(11, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent(12, KICK_DRUM, 104, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent(13, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent(14, KICK_DRUM,  98, 64, NOTE_ON, CLOSED_HI_HAT, 54, 0, 48),
  new ScoreEvent(15, SNARE_DRUM, 102, 64, NOTE_ON, CLOSED_HI_HAT, 60, 0, 48),

  // 主旋律が3声そろう区間
  new ScoreEvent(16, KICK_DRUM, 108, 64, NOTE_ON, CLOSED_HI_HAT, 58, 0, 48),
  new ScoreEvent(17, SNARE_DRUM,  96, 64, NOTE_ON, CLOSED_HI_HAT, 52, 0, 48),
  new ScoreEvent(18, KICK_DRUM, 102, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent(19, SNARE_DRUM,  96, 64, NOTE_ON, CLOSED_HI_HAT, 52, 0, 48),
  new ScoreEvent(20, KICK_DRUM, 108, 64, NOTE_ON, CLOSED_HI_HAT, 58, 0, 48),
  new ScoreEvent(21, SNARE_DRUM,  96, 64, NOTE_ON, CLOSED_HI_HAT, 52, 0, 48),
  new ScoreEvent(22, KICK_DRUM, 102, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent(23, SNARE_DRUM, 104, 64, NOTE_ON, CLOSED_HI_HAT, 62, 0, 48),
  new ScoreEvent(24, KICK_DRUM, 108, 64, NOTE_ON, CLOSED_HI_HAT, 58, 0, 48),
  new ScoreEvent(25, SNARE_DRUM,  96, 64, NOTE_ON, CLOSED_HI_HAT, 52, 0, 48),
  new ScoreEvent(26, KICK_DRUM, 102, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent(27, SNARE_DRUM,  96, 64, NOTE_ON, CLOSED_HI_HAT, 52, 0, 48),
  new ScoreEvent(28, KICK_DRUM, 108, 64, NOTE_ON, CLOSED_HI_HAT, 58, 0, 48),
  new ScoreEvent(29, SNARE_DRUM,  96, 64, NOTE_ON, CLOSED_HI_HAT, 52, 0, 48),
  new ScoreEvent(30, KICK_DRUM, 102, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent(31, SNARE_DRUM, 106, 64, NOTE_ON, CLOSED_HI_HAT, 64, 0, 48),

  // ホルンとチューバの終止まで
  new ScoreEvent(32, KICK_DRUM, 104, 64, NOTE_ON, CLOSED_HI_HAT, 56, 0, 48),
  new ScoreEvent(33, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent(34, KICK_DRUM,  98, 64, NOTE_ON, CLOSED_HI_HAT, 54, 0, 48),
  new ScoreEvent(35, SNARE_DRUM,  92, 64, NOTE_ON, CLOSED_HI_HAT, 50, 0, 48),
  new ScoreEvent(36, KICK_DRUM, 100, 64, NOTE_ON, CLOSED_HI_HAT, 48, 0, 48),
  new ScoreEvent(37, SNARE_DRUM,  88, 64, NOTE_ON, CLOSED_HI_HAT, 44, 0, 48),
  new ScoreEvent(38, KICK_DRUM,  94, 64, NOTE_ON, CLOSED_HI_HAT, 44, 0, 48),
  new ScoreEvent(39, SNARE_DRUM,  86, 64, NOTE_ON, CLOSED_HI_HAT, 40, 0, 48)
};

class BrassNote implements Instrument {
  Oscil[] harmonics;
  Summer mix;
  ADSR envelope;

  BrassNote(float frequency, float amplitude, TimbreData timbre) {
    mix = new Summer();
    harmonics = new Oscil[timbre.harmonicRatios.length];
    for (int i = 0; i < harmonics.length; i++) {
      float partialFrequency = frequency * timbre.harmonicRatios[i];
      float partialAmplitude = amplitude * timbre.harmonicGains[i];
      harmonics[i] = new Oscil(partialFrequency, partialAmplitude, Waves.SINE);
      harmonics[i].patch(mix);
    }
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

class DrumNote implements Instrument {
  Summer mix;
  Oscil[] harmonics;
  Noise noise;
  ADSR envelope;

  DrumNote(int noteNumber, float amplitude) {
    mix = new Summer();
    TimbreData timbre = drumTimbres[drumIndex(noteNumber)];
    harmonics = new Oscil[timbre.harmonicRatios.length];
    for (int i = 0; i < harmonics.length; i++) {
      float partialFrequency = timbre.fundamentalHz * timbre.harmonicRatios[i];
      float partialAmplitude = amplitude * timbre.harmonicGains[i];
      harmonics[i] = new Oscil(partialFrequency, partialAmplitude, Waves.SINE);
      harmonics[i].patch(mix);
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
  size(920, 470);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  out.setTempo(BPM);
  timbres = new TimbreData[INSTRUMENT_FILES.length];
  for (int part = 0; part < INSTRUMENT_FILES.length; part++) {
    timbres[part] = new TimbreData(INSTRUMENT_FILES[part]);
  }
  drumTimbres = new TimbreData[DRUM_INSTRUMENT_FILES.length];
  for (int i = 0; i < DRUM_INSTRUMENT_FILES.length; i++) {
    drumTimbres[i] = new TimbreData(DRUM_INSTRUMENT_FILES[i]);
  }
  textFont(createFont("SansSerif", 16));
  playAllParts();
}

void draw() {
  background(248, 246, 242);
  fill(34);
  textSize(26);
  text("かえるのうた 楽譜・音色プレビュー", 28, 42);
  textSize(15);
  text("固定テンポ: " + BPM + " BPM   主旋律: " + MELODY_SCORE.length + " 拍   低音: " + BASS_SCORE.length + " 拍   ドラム: " + DRUM_SCORE.length + " 拍", 28, 72);
  text("P: 全パート再生    1-5: 単独再生    再生完了後に次のキーを押してください", 28, 98);

  int y = 148;
  for (int part = 0; part < PART_NAMES.length; part++) {
    fill(34);
    text(PART_NAMES[part] + "   開始拍 = " + START_BEATS[part], 28, y);
    fill(70 + part * 24, 130, 180);
    int scoreLength = scoreForPart(part).length;
    rect(322 + START_BEATS[part] * 8, y - 14, scoreLength * 8, 14, 3);
    y += 42;
  }

  fill(34);
  text(currentMode, 28, 382);
  textSize(13);
  text("音色: 金管・低音・ドラムすべて解析 JSON を利用", 28, 421);
  text("Arduino 転記対象: { beatAt, noteNumber, velocity, durationQ8, flags, sub... }", 28, 442);
}

void keyPressed() {
  if (key == 'p' || key == 'P') {
    playAllParts();
  } else if (key >= '1' && key <= '5') {
    int part = key - '1';
    playPart(part);
  }
}

void playAllParts() {
  out.pauseNotes();
  for (int part = 0; part < PART_NAMES.length; part++) {
    schedulePart(part);
  }
  out.resumeNotes();
  currentMode = "主旋律3声の輪唱、チューバ低音、ドラム伴奏を再生中です。";
}

void playPart(int part) {
  out.pauseNotes();
  schedulePart(part);
  out.resumeNotes();
  currentMode = "単独再生中: " + PART_NAMES[part] + "。";
}

void schedulePart(int part) {
  ScoreEvent[] score = scoreForPart(part);
  for (ScoreEvent event : score) {
    if (event.isRest()) {
      continue;
    }
    float startBeat = START_BEATS[part] + event.beatAt;
    float durationBeats = event.durationQ8 / 256.0f;
    float velocityScale = event.velocity / 127.0f;
    float amplitude = PART_AMPLITUDES[part] * velocityScale;
    out.playNote(startBeat, durationBeats, noteInstrument(part, event.noteNumber, amplitude));
    if (event.subNote != 0) {
      float subStartBeat = startBeat + event.subOffsetQ8 / 256.0f;
      float subDurationBeats = event.subDurationQ8 / 256.0f;
      float subVelocityScale = event.subVelocity / 127.0f;
      float subAmplitude = PART_AMPLITUDES[part] * subVelocityScale;
      out.playNote(subStartBeat, subDurationBeats, noteInstrument(part, event.subNote, subAmplitude));
    }
  }
}

ScoreEvent[] scoreForPart(int part) {
  if (part == DRUM_PART) {
    return DRUM_SCORE;
  }
  return part == 3 ? BASS_SCORE : MELODY_SCORE;
}

Instrument noteInstrument(int part, int noteNumber, float amplitude) {
  if (part == DRUM_PART) {
    return new DrumNote(noteNumber, amplitude);
  }
  float frequency = midiToFrequency(noteNumber);
  return new BrassNote(frequency, amplitude, timbres[part]);
}

int drumIndex(int noteNumber) {
  if (noteNumber == KICK_DRUM) return 0;
  if (noteNumber == SNARE_DRUM) return 1;
  if (noteNumber == CLOSED_HI_HAT) return 2;
  if (noteNumber == CRASH_CYMBAL) return 3;
  return 2;
}

float drumNoiseScale(int noteNumber) {
  if (noteNumber == KICK_DRUM) return 0.18f;
  if (noteNumber == SNARE_DRUM) return 0.65f;
  if (noteNumber == CRASH_CYMBAL) return 0.55f;
  return 0.75f;
}

float midiToFrequency(int midiNote) {
  return 440.0f * pow(2.0f, (midiNote - 69) / 12.0f);
}
