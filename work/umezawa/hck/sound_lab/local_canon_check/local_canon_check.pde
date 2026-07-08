/* ==========================================================================
   local_canon_check — 通信を使わない production 輪唱同期チェッカー

   Arduino / Serial / UDP を使わず、Minim の単一タイムラインに金管4声と
   ドラムをまとめて予約する。音色処理と JSON は pc_app/test_multi と共有する。
   ========================================================================== */

import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*;
import java.io.File;
import java.util.Iterator;
import java.util.concurrent.ConcurrentLinkedQueue;

final int BPM = 100;
final int CANON_CYCLE_BEATS = 56;
final int NOTE_ON = 0x01;
final int REST = 0x04;
final int MAX_POLYPHONY = 32;

float masterVolume = 0.55f;
boolean useSimpleADSR = true;

Minim minim;
AudioOutput out;

ArrayList<File> instrumentFiles = new ArrayList<File>();
ArrayList<InstrModel> models = new ArrayList<InstrModel>();
ArrayList<String> modelLabels = new ArrayList<String>();
ArrayList<ResynthVoice> activeVoices = new ArrayList<ResynthVoice>();
DrumTimbreData[] drumTimbres;
AudioSample[] recordedDrumSamples;
ArrayList<ActiveDrumSynth> activeDrumSynths = new ArrayList<ActiveDrumSynth>();
ArrayList<MetroClick> metroClicks = new ArrayList<MetroClick>();

ConcurrentLinkedQueue<ResynthVoice> startedVoices = new ConcurrentLinkedQueue<ResynthVoice>();

int playbackGeneration = 0;
int playbackStartedAtMs = 0;
boolean playing = false;
String currentMode = "P キーで全パートを再生";

final int[] PART_COLORS = {
  0xFFE85D4A, 0xFF4DAA6A, 0xFFF39A2E, 0xFF9B59B6, 0xFF795548
};

class ScoreEvent {
  int beatAt, noteNumber, velocity, durationQ8, flags;
  int subNote, subVelocity, subOffsetQ8, subDurationQ8;

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
  int partId, instrumentId, startBeat;

  PartDefinition(String name, int partId, int instrumentId, int startBeat) {
    this.name = name;
    this.partId = partId;
    this.instrumentId = instrumentId;
    this.startBeat = startBeat;
  }
}

final PartDefinition[] BRASS_PARTS = {
  new PartDefinition("Trumpet",  0x02, 0,  0),
  new PartDefinition("Horn",     0x03, 1,  8),
  new PartDefinition("Trombone", 0x04, 2, 16),
  new PartDefinition("Tuba",     0x05, 3, 24)
};

// firmware/production/node_02/src/score_data.cpp と同じ32拍。
final ScoreEvent[] MELODY_SCORE = {
  new ScoreEvent( 0, 60, 96, 240, NOTE_ON), new ScoreEvent( 1, 62, 96, 240, NOTE_ON),
  new ScoreEvent( 2, 64, 96, 240, NOTE_ON), new ScoreEvent( 3, 65, 96, 240, NOTE_ON),
  new ScoreEvent( 4, 64, 96, 240, NOTE_ON), new ScoreEvent( 5, 62, 96, 240, NOTE_ON),
  new ScoreEvent( 6, 60, 96, 480, NOTE_ON), new ScoreEvent( 7,  0,  0,   0, REST),
  new ScoreEvent( 8, 64, 92, 240, NOTE_ON), new ScoreEvent( 9, 65, 92, 240, NOTE_ON),
  new ScoreEvent(10, 67, 92, 240, NOTE_ON), new ScoreEvent(11, 69, 92, 240, NOTE_ON),
  new ScoreEvent(12, 67, 92, 240, NOTE_ON), new ScoreEvent(13, 65, 92, 240, NOTE_ON),
  new ScoreEvent(14, 64, 96, 480, NOTE_ON), new ScoreEvent(15,  0,  0,   0, REST),
  new ScoreEvent(16, 60, 90, 128, NOTE_ON), new ScoreEvent(17,  0,  0,   0, REST),
  new ScoreEvent(18, 60, 90, 128, NOTE_ON), new ScoreEvent(19,  0,  0,   0, REST),
  new ScoreEvent(20, 60, 90, 128, NOTE_ON), new ScoreEvent(21,  0,  0,   0, REST),
  new ScoreEvent(22, 60, 90, 128, NOTE_ON), new ScoreEvent(23,  0,  0,   0, REST),
  new ScoreEvent(24, 60, 96, 128, NOTE_ON, 60, 96, 128, 128),
  new ScoreEvent(25, 62, 96, 128, NOTE_ON, 62, 96, 128, 128),
  new ScoreEvent(26, 64, 96, 128, NOTE_ON, 64, 96, 128, 128),
  new ScoreEvent(27, 65, 96, 128, NOTE_ON, 65, 96, 128, 128),
  new ScoreEvent(28, 64, 96, 240, NOTE_ON), new ScoreEvent(29, 62, 96, 240, NOTE_ON),
  new ScoreEvent(30, 60,100, 480, NOTE_ON), new ScoreEvent(31,  0,  0,   0, REST)
};

ScoreEvent[] drumScore;

// firmware/production/node_06/src/score_data.cpp と同じ56拍。
ScoreEvent[] createDrumScore() {
  ScoreEvent[] score = new ScoreEvent[CANON_CYCLE_BEATS];
  for (int beat = 0; beat < score.length; beat++) {
    if (beat == 0 || beat == 8 || beat == 16 || beat == 24 ||
        beat == 32 || beat == 40 || beat == 48 || beat == 55) {
      score[beat] = new ScoreEvent(beat, CRASH_CYMBAL, beat == 55 ? 90 : 80,
                                   512, NOTE_ON);
    } else if (beat >= 52 && beat <= 54) {
      int[] velocities = {72, 76, 80};
      score[beat] = new ScoreEvent(beat, SNARE_DRUM, velocities[beat - 52],
                                   128, NOTE_ON);
    } else {
      score[beat] = new ScoreEvent(beat, KICK_DRUM, 72, 128, NOTE_ON);
    }
  }
  return score;
}

// AudioOutput の同じ音符タイムラインから test_multi の ResynthVoice を開始する。
class ScheduledBrassNote implements Instrument {
  int generation, partId, instrumentId, midi, velocity;
  ResynthVoice voice;

  ScheduledBrassNote(int generation, int partId, int instrumentId, int midi, int velocity) {
    this.generation = generation;
    this.partId = partId;
    this.instrumentId = instrumentId;
    this.midi = midi;
    this.velocity = velocity;
  }

  void noteOn(float duration) {
    if (generation != playbackGeneration) return;
    InstrModel model = modelForId(instrumentId);
    if (model == null) return;
    int effectiveMidi = midi + brassOctaveShift(instrumentId);
    float gain = constrain(velocity / 127.0f, 0, 1) *
                 brassPartAmplitude(instrumentId) * masterVolume;
    voice = new ResynthVoice(model, effectiveMidi, gain, useSimpleADSR);
    voice.partId = partId;
    voice.instrumentIdx = instrumentId;
    voice.patch(out);
    startedVoices.add(voice);
  }

  void noteOff() {
    if (voice != null) voice.noteOff();
  }
}

class ScheduledDrumNote implements Instrument {
  int generation, noteNumber, velocity, durationMs;

  ScheduledDrumNote(int generation, int noteNumber, int velocity, int durationMs) {
    this.generation = generation;
    this.noteNumber = noteNumber;
    this.velocity = velocity;
    this.durationMs = durationMs;
  }

  void noteOn(float duration) {
    if (generation == playbackGeneration)
      triggerDrumNote(noteNumber, velocity, durationMs);
  }

  void noteOff() {}
}

void settings() {
  size(1120, 620);
}

void setup() {
  frameRate(60);
  surface.setTitle("通信なし輪唱チェッカー");
  textFont(createFont("SansSerif", 14));
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 512, 44100);
  rescanInstruments();
  loadDrumTimbres();
  drumScore = createDrumScore();
  println("[LOCAL] communication disabled / instruments=" + models.size() +
          " / drums=" + drumTimbres.length + " / BPM=" + BPM);
}

void draw() {
  drainStartedVoices();
  updateVoiceLifecycle();
  updatePlaybackState();
  drawScreen();
}

void drainStartedVoices() {
  ResynthVoice voice;
  while ((voice = startedVoices.poll()) != null) activeVoices.add(voice);
}

void updatePlaybackState() {
  if (playing && millis() - playbackStartedAtMs >= cycleDurationMs() + 500) {
    playing = false;
    currentMode = "再生完了 — P で全パートをもう一度再生";
  }
}

int beatDurationMs() {
  return round(60000.0f / BPM);
}

int cycleDurationMs() {
  return CANON_CYCLE_BEATS * beatDurationMs();
}

void playAllParts() {
  beginPlayback("全パート再生中（通信なし・単一タイムライン）");
  for (int part = 0; part < BRASS_PARTS.length; part++) scheduleBrassPart(part);
  scheduleDrums();
  out.resumeNotes();
}

void playSinglePart(int part) {
  String name = part < BRASS_PARTS.length ? BRASS_PARTS[part].name : "Drum";
  beginPlayback("単独再生中: " + name);
  if (part < BRASS_PARTS.length) scheduleBrassPart(part);
  else scheduleDrums();
  out.resumeNotes();
}

void beginPlayback(String mode) {
  stopPlayback();
  playbackGeneration++;
  out.setTempo(BPM);
  out.pauseNotes();
  playbackStartedAtMs = millis();
  playing = true;
  currentMode = mode;
}

void scheduleBrassPart(int index) {
  PartDefinition part = BRASS_PARTS[index];
  for (ScoreEvent event : MELODY_SCORE) {
    if (event.isRest()) continue;
    float startBeat = part.startBeat + event.beatAt;
    float durationBeat = event.durationQ8 / 256.0f;
    out.playNote(startBeat, durationBeat,
      new ScheduledBrassNote(playbackGeneration, part.partId, part.instrumentId,
                             event.noteNumber, event.velocity));
    if (event.subNote != 0) {
      out.playNote(startBeat + event.subOffsetQ8 / 256.0f,
                   event.subDurationQ8 / 256.0f,
        new ScheduledBrassNote(playbackGeneration, part.partId, part.instrumentId,
                               event.subNote, event.subVelocity));
    }
  }
}

void scheduleDrums() {
  for (ScoreEvent event : drumScore) {
    float durationBeat = event.durationQ8 / 256.0f;
    int durationMs = round(durationBeat * beatDurationMs());
    out.playNote(event.beatAt, durationBeat,
      new ScheduledDrumNote(playbackGeneration, event.noteNumber,
                            event.velocity, durationMs));
  }
}

void stopPlayback() {
  playbackGeneration++;
  playing = false;
  drainStartedVoices();
  stopAll();
  currentMode = "停止中 — P で全パートを再生";
}

void keyPressed() {
  if (key == 'p' || key == 'P') playAllParts();
  else if (key >= '1' && key <= '5') playSinglePart(key - '1');
  else if (key == ' ') stopPlayback();
  else if (key == '+' || key == '=') masterVolume = constrain(masterVolume + 0.05f, 0.05f, 1.5f);
  else if (key == '-' || key == '_') masterVolume = constrain(masterVolume - 0.05f, 0.05f, 1.5f);
}

void drawScreen() {
  background(246, 247, 250);
  fill(30, 42, 56);
  textSize(26);
  text("通信なし輪唱チェッカー", 32, 44);
  textSize(14);
  fill(75, 88, 104);
  text("production/test_multi と同じ音色・楽譜を、PC内の単一クロックで再生", 32, 70);
  text("P: 全パート   1-5: 単独   Space: 停止   +/-: 音量", 32, 96);

  fill(255);
  stroke(214, 220, 228);
  rect(28, 118, width - 56, 82, 12);
  noStroke();
  fill(30, 42, 56);
  textSize(16);
  text(currentMode, 48, 150);
  textSize(14);
  float shownBeat = currentBeat();
  String beatText = playing ? nf(shownBeat + 1, 1, 1) + " / 56" : "— / 56";
  text("固定テンポ: " + BPM + " BPM    現在拍: " + beatText +
       "    音量: " + nf(masterVolume, 1, 2), 48, 178);

  drawTimeline(28, 224, width - 56, 326);

  fill(92, 103, 116);
  textSize(13);
  text("ここで揃う → 通信・マイコン側を確認 / ここでもズレる → 音色の立ち上がり・楽譜を確認", 32, 588);
}

float currentBeat() {
  if (!playing) return 0;
  return constrain((millis() - playbackStartedAtMs) / (float)beatDurationMs(),
                   0, CANON_CYCLE_BEATS);
}

void drawTimeline(float x, float y, float w, float h) {
  fill(255);
  stroke(214, 220, 228);
  rect(x, y, w, h, 12);
  float labelW = 112;
  float gridX = x + labelW;
  float gridW = w - labelW - 22;
  float beatW = gridW / CANON_CYCLE_BEATS;
  float rowH = 48;
  float top = y + 52;

  textSize(11);
  textAlign(CENTER, BASELINE);
  for (int beat = 0; beat <= CANON_CYCLE_BEATS; beat += 4) {
    float bx = gridX + beat * beatW;
    stroke(226, 230, 236);
    line(bx, y + 34, bx, y + h - 20);
    fill(100, 110, 122);
    text(beat, bx, y + 26);
  }

  String[] names = {"Trumpet", "Horn", "Trombone", "Tuba", "Drum"};
  textAlign(LEFT, BASELINE);
  for (int row = 0; row < names.length; row++) {
    float ry = top + row * rowH;
    fill(47, 59, 72);
    textSize(13);
    text(names[row], x + 18, ry + 17);
    noStroke();
    fill(238, 241, 245);
    rect(gridX, ry, gridW, 22, 4);
    fill(PART_COLORS[row]);
    if (row < 4) {
      rect(gridX + BRASS_PARTS[row].startBeat * beatW, ry,
           MELODY_SCORE.length * beatW, 22, 4);
    } else {
      rect(gridX, ry, CANON_CYCLE_BEATS * beatW, 22, 4);
    }
  }

  if (playing) {
    float cursorX = gridX + currentBeat() * beatW;
    stroke(32, 120, 220);
    strokeWeight(2);
    line(cursorX, y + 34, cursorX, y + h - 20);
    strokeWeight(1);
  }
  textAlign(LEFT, BASELINE);
}

void stop() {
  stopPlayback();
  out.close();
  minim.stop();
  super.stop();
}
