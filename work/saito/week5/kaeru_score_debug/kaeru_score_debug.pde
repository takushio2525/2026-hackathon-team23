import ddf.minim.*;
import ddf.minim.ugens.*;

final int BPM = 96;
final int NOTE_ON = 0x01;
final int REST = 0x04;
final int MAX_HARMONICS = 12;

final String[] PART_NAMES = {
  "主旋律1 / トランペット",
  "主旋律2 / ホルン",
  "主旋律3 / トロンボーン",
  "低音 / チューバ"
};

final String[] INSTRUMENT_FILES = {
  "trumpets.tweaked.instrument.json",
  "horns.tweaked.instrument.json",
  "trombones.tweaked.instrument.json",
  "tuba.tweaked.instrument.json"
};

final int[] START_BEATS = {0, 8, 16, 0};
final float[] PART_AMPLITUDES = {0.20f, 0.17f, 0.15f, 0.13f};

Minim minim;
AudioOutput out;
TimbreData[] timbres;
String currentMode = "P キーで主旋律3声と低音を再生します";

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
    JSONObject sourceEnvelope = json.getJSONObject("envelope");
    attackSec = sourceEnvelope.getFloat("attack_sec");
    decaySec = sourceEnvelope.getFloat("decay_sec");
    sustainLevel = sourceEnvelope.getFloat("sustain_level");
    releaseSec = sourceEnvelope.getFloat("release_sec");

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

void setup() {
  size(920, 420);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  out.setTempo(BPM);
  timbres = new TimbreData[INSTRUMENT_FILES.length];
  for (int part = 0; part < INSTRUMENT_FILES.length; part++) {
    timbres[part] = new TimbreData(INSTRUMENT_FILES[part]);
  }
  textFont(createFont("SansSerif", 16));
}

void draw() {
  background(248, 246, 242);
  fill(34);
  textSize(26);
  text("かえるのうた 楽譜・解析音色プレビュー", 28, 42);
  textSize(15);
  text("固定テンポ: " + BPM + " BPM   主旋律: " + MELODY_SCORE.length + " 拍   低音: " + BASS_SCORE.length + " 拍", 28, 72);
  text("P: 全パート再生    1-4: 単独再生    再生完了後に次のキーを押してください", 28, 98);

  int y = 148;
  for (int part = 0; part < PART_NAMES.length; part++) {
    fill(34);
    text(PART_NAMES[part] + "   開始拍 = " + START_BEATS[part], 28, y);
    fill(70 + part * 24, 130, 180);
    int scoreLength = part == 3 ? BASS_SCORE.length : MELODY_SCORE.length;
    rect(322 + START_BEATS[part] * 8, y - 14, scoreLength * 8, 14, 3);
    y += 42;
  }

  fill(34);
  text(currentMode, 28, 338);
  textSize(13);
  text("音色: 解析 JSON の第1〜第" + MAX_HARMONICS + "倍音と ADSR を利用", 28, 377);
  text("Arduino 転記対象: { beatAt, noteNumber, velocity, durationQ8, flags, sub... }", 28, 398);
}

void keyPressed() {
  if (key == 'p' || key == 'P') {
    playAllParts();
  } else if (key >= '1' && key <= '4') {
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
  currentMode = "主旋律3声の輪唱と、チューバの低音伴奏を再生中です。";
}

void playPart(int part) {
  out.pauseNotes();
  schedulePart(part);
  out.resumeNotes();
  currentMode = "単独再生中: " + PART_NAMES[part] + "。";
}

void schedulePart(int part) {
  ScoreEvent[] score = part == 3 ? BASS_SCORE : MELODY_SCORE;
  for (ScoreEvent event : score) {
    if (event.isRest()) {
      continue;
    }
    float startBeat = START_BEATS[part] + event.beatAt;
    float durationBeats = event.durationQ8 / 256.0f;
    float frequency = midiToFrequency(event.noteNumber);
    float velocityScale = event.velocity / 127.0f;
    float amplitude = PART_AMPLITUDES[part] * velocityScale;
    out.playNote(startBeat, durationBeats, new BrassNote(frequency, amplitude, timbres[part]));
    if (event.subNote != 0) {
      float subStartBeat = startBeat + event.subOffsetQ8 / 256.0f;
      float subDurationBeats = event.subDurationQ8 / 256.0f;
      float subFrequency = midiToFrequency(event.subNote);
      float subVelocityScale = event.subVelocity / 127.0f;
      float subAmplitude = PART_AMPLITUDES[part] * subVelocityScale;
      out.playNote(subStartBeat, subDurationBeats, new BrassNote(subFrequency, subAmplitude, timbres[part]));
    }
  }
}

float midiToFrequency(int midiNote) {
  return 440.0f * pow(2.0f, (midiNote - 69) / 12.0f);
}
