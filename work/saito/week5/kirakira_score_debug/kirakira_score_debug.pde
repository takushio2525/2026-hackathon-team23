import ddf.minim.*;
import ddf.minim.ugens.*;

final int BPM = 96;
final int NOTE_ON = 0x01;
final int REST = 0x04;

final String[] PART_NAMES = {
  "Brass 1 / Main",
  "Brass 2 / Canon 1",
  "Brass 3 / Canon 2",
  "Brass 4 / Canon 3"
};

final int[] START_BEATS = {0, 4, 8, 12};
final float[] PART_AMPLITUDES = {0.20f, 0.17f, 0.15f, 0.13f};

Minim minim;
AudioOutput out;
String currentMode = "Press P to play all four parts";

class ScoreEvent {
  int beatAt;
  int noteNumber;
  int velocity;
  int durationQ8;
  int flags;

  ScoreEvent(int beatAt, int noteNumber, int velocity, int durationQ8, int flags) {
    this.beatAt = beatAt;
    this.noteNumber = noteNumber;
    this.velocity = velocity;
    this.durationQ8 = durationQ8;
    this.flags = flags;
  }

  boolean isRest() {
    return noteNumber == 0 || (flags & REST) != 0;
  }
}

// "Twinkle, Twinkle, Little Star" in C major.
// One array slot corresponds to one beat. A rest slot following each two-beat
// note preserves beat indexing when this data is moved to Arduino.
ScoreEvent[] TWINKLE_SCORE = {
  new ScoreEvent( 0, 60, 96, 256, NOTE_ON), // C4
  new ScoreEvent( 1, 60, 96, 256, NOTE_ON), // C4
  new ScoreEvent( 2, 67, 96, 256, NOTE_ON), // G4
  new ScoreEvent( 3, 67, 96, 256, NOTE_ON), // G4
  new ScoreEvent( 4, 69, 96, 256, NOTE_ON), // A4
  new ScoreEvent( 5, 69, 96, 256, NOTE_ON), // A4
  new ScoreEvent( 6, 67, 96, 512, NOTE_ON), // G4, two beats
  new ScoreEvent( 7,  0,  0, 256, REST),
  new ScoreEvent( 8, 65, 92, 256, NOTE_ON), // F4
  new ScoreEvent( 9, 65, 92, 256, NOTE_ON), // F4
  new ScoreEvent(10, 64, 92, 256, NOTE_ON), // E4
  new ScoreEvent(11, 64, 92, 256, NOTE_ON), // E4
  new ScoreEvent(12, 62, 92, 256, NOTE_ON), // D4
  new ScoreEvent(13, 62, 92, 256, NOTE_ON), // D4
  new ScoreEvent(14, 60, 96, 512, NOTE_ON), // C4, two beats
  new ScoreEvent(15,  0,  0, 256, REST),

  new ScoreEvent(16, 67, 90, 256, NOTE_ON), // G4
  new ScoreEvent(17, 67, 90, 256, NOTE_ON), // G4
  new ScoreEvent(18, 65, 90, 256, NOTE_ON), // F4
  new ScoreEvent(19, 65, 90, 256, NOTE_ON), // F4
  new ScoreEvent(20, 64, 90, 256, NOTE_ON), // E4
  new ScoreEvent(21, 64, 90, 256, NOTE_ON), // E4
  new ScoreEvent(22, 62, 92, 512, NOTE_ON), // D4, two beats
  new ScoreEvent(23,  0,  0, 256, REST),
  new ScoreEvent(24, 67, 90, 256, NOTE_ON), // G4
  new ScoreEvent(25, 67, 90, 256, NOTE_ON), // G4
  new ScoreEvent(26, 65, 90, 256, NOTE_ON), // F4
  new ScoreEvent(27, 65, 90, 256, NOTE_ON), // F4
  new ScoreEvent(28, 64, 90, 256, NOTE_ON), // E4
  new ScoreEvent(29, 64, 90, 256, NOTE_ON), // E4
  new ScoreEvent(30, 62, 92, 512, NOTE_ON), // D4, two beats
  new ScoreEvent(31,  0,  0, 256, REST),

  new ScoreEvent(32, 60, 96, 256, NOTE_ON), // C4
  new ScoreEvent(33, 60, 96, 256, NOTE_ON), // C4
  new ScoreEvent(34, 67, 96, 256, NOTE_ON), // G4
  new ScoreEvent(35, 67, 96, 256, NOTE_ON), // G4
  new ScoreEvent(36, 69, 96, 256, NOTE_ON), // A4
  new ScoreEvent(37, 69, 96, 256, NOTE_ON), // A4
  new ScoreEvent(38, 67, 96, 512, NOTE_ON), // G4, two beats
  new ScoreEvent(39,  0,  0, 256, REST),
  new ScoreEvent(40, 65, 92, 256, NOTE_ON), // F4
  new ScoreEvent(41, 65, 92, 256, NOTE_ON), // F4
  new ScoreEvent(42, 64, 92, 256, NOTE_ON), // E4
  new ScoreEvent(43, 64, 92, 256, NOTE_ON), // E4
  new ScoreEvent(44, 62, 92, 256, NOTE_ON), // D4
  new ScoreEvent(45, 62, 92, 256, NOTE_ON), // D4
  new ScoreEvent(46, 60, 100, 512, NOTE_ON), // C4, two beats
  new ScoreEvent(47,  0,   0, 256, REST)
};

class BrassNote implements Instrument {
  Oscil fundamental;
  Oscil secondHarmonic;
  Oscil thirdHarmonic;
  Line envelope;
  Summer mix;
  float amplitude;

  BrassNote(float frequency, float amplitude) {
    this.amplitude = amplitude;
    mix = new Summer();
    fundamental = new Oscil(frequency, 0, Waves.SAW);
    secondHarmonic = new Oscil(frequency * 2.0f, 0, Waves.SINE);
    thirdHarmonic = new Oscil(frequency * 3.0f, 0, Waves.SINE);
    envelope = new Line();

    fundamental.patch(mix);
    secondHarmonic.patch(mix);
    thirdHarmonic.patch(mix);
    envelope.patch(fundamental.amplitude);
  }

  void noteOn(float duration) {
    fundamental.setAmplitude(amplitude);
    secondHarmonic.setAmplitude(amplitude * 0.32f);
    thirdHarmonic.setAmplitude(amplitude * 0.18f);
    envelope.activate(duration, amplitude, 0);
    mix.patch(out);
  }

  void noteOff() {
    mix.unpatch(out);
  }
}

void setup() {
  size(920, 420);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  out.setTempo(BPM);
  textFont(createFont("SansSerif", 16));
}

void draw() {
  background(248, 246, 242);
  fill(34);
  textSize(26);
  text("Twinkle Score Debug - ScoreEvent Preview", 28, 42);
  textSize(15);
  text("Fixed tempo: " + BPM + " BPM   Score length: " + TWINKLE_SCORE.length + " beats   Drum: excluded", 28, 72);
  text("P: play all parts    1-4: solo part    Wait for playback to finish before replaying.", 28, 98);

  int y = 148;
  for (int part = 0; part < PART_NAMES.length; part++) {
    fill(34);
    text(PART_NAMES[part] + "   startBeatNo = " + START_BEATS[part], 28, y);
    fill(70 + part * 24, 130, 180);
    rect(322 + START_BEATS[part] * 8, y - 14, TWINKLE_SCORE.length * 8, 14, 3);
    y += 42;
  }

  fill(34);
  text(currentMode, 28, 338);
  textSize(13);
  text("Arduino transfer target: { beatAt, noteNumber, velocity, durationQ8, flags }", 28, 377);
  text("A two-beat note is followed by a REST slot so beatAt remains aligned.", 28, 398);
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
  currentMode = "Playing all four brass parts at offsets 0 / 4 / 8 / 12 beats.";
}

void playPart(int part) {
  out.pauseNotes();
  schedulePart(part);
  out.resumeNotes();
  currentMode = "Playing solo: " + PART_NAMES[part] + ".";
}

void schedulePart(int part) {
  for (ScoreEvent event : TWINKLE_SCORE) {
    if (event.isRest()) {
      continue;
    }
    float startBeat = START_BEATS[part] + event.beatAt;
    float durationBeats = event.durationQ8 / 256.0f;
    float frequency = midiToFrequency(event.noteNumber);
    float velocityScale = event.velocity / 127.0f;
    float amplitude = PART_AMPLITUDES[part] * velocityScale;
    out.playNote(startBeat, durationBeats, new BrassNote(frequency, amplitude));
  }
}

float midiToFrequency(int midiNote) {
  return 440.0f * pow(2.0f, (midiNote - 69) / 12.0f);
}
