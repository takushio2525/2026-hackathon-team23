class Voice {
  int partId;
  int noteNumber;
  float amp;
  int durationMs;
  int startedAtMs;
  int releaseAtMs;
  boolean releasing = false;
  boolean stopped = false;

  Oscil osc;
  Line env;

  Voice(int partId, int noteNumber, float amp, int durationMs) {
    this.partId = partId;
    this.noteNumber = noteNumber;
    this.amp = amp;
    this.durationMs = durationMs;
  }

  void start() {
    startedAtMs = millis();
    releaseAtMs = startedAtMs + durationMs;
  }

  void update() {
    if (!releasing && millis() >= releaseAtMs) {
      release();
    }
  }

  void release() {
    releasing = true;
  }

  boolean finished() {
    return releasing && millis() >= releaseAtMs + 90;
  }

  void stop() {
    if (stopped) return;
    if (osc != null) osc.unpatch(out);
    stopped = true;
  }
}

class BrassProfile {
  Waveform waveform;
  int attackMs;
  int decayMs;
  float sustain;
  int releaseMs;
  float gain;
  int noteShift;

  BrassProfile(Waveform waveform, int attackMs, int decayMs, float sustain, int releaseMs, float gain, int noteShift) {
    this.waveform = waveform;
    this.attackMs = attackMs;
    this.decayMs = decayMs;
    this.sustain = sustain;
    this.releaseMs = releaseMs;
    this.gain = gain;
    this.noteShift = noteShift;
  }
}

class BrassVoice extends Voice {
  BrassProfile profile;
  int phase = 0;
  float effectiveAmp;

  BrassVoice(int partId, int noteNumber, float amp, int durationMs, BrassProfile profile) {
    super(partId, noteNumber, amp, durationMs);
    this.profile = profile;
    this.effectiveAmp = amp * profile.gain;
  }

  void start() {
    super.start();
    int adjustedNote = constrain(noteNumber + profile.noteShift, 0, 127);
    osc = new Oscil(midiToHz(adjustedNote), 0, profile.waveform);
    env = new Line();
    env.patch(osc.amplitude);
    osc.patch(out);
    env.activate(profile.attackMs / 1000.0, 0, effectiveAmp);
  }

  void update() {
    int elapsed = millis() - startedAtMs;
    if (phase == 0 && elapsed >= profile.attackMs) {
      env.activate(profile.decayMs / 1000.0, effectiveAmp, effectiveAmp * profile.sustain);
      phase = 1;
    }
    super.update();
  }

  void release() {
    if (releasing) return;
    releasing = true;
    releaseAtMs = millis();
    env.activate(profile.releaseMs / 1000.0, effectiveAmp * profile.sustain, 0);
  }

  boolean finished() {
    return releasing && millis() >= releaseAtMs + profile.releaseMs + 20;
  }
}

class RhythmVoice extends Voice {
  int decayMs;

  RhythmVoice(int partId, int noteNumber, float amp, int durationMs) {
    super(partId, noteNumber, amp, durationMs);
    decayMs = rhythmDecay(noteNumber);
  }

  void start() {
    super.start();
    releaseAtMs = startedAtMs + decayMs;
    osc = new Oscil(rhythmFreq(noteNumber), 0, rhythmWave(noteNumber));
    env = new Line();
    env.patch(osc.amplitude);
    osc.patch(out);
    env.activate(decayMs / 1000.0, amp, 0);
    releasing = true;
  }

  int rhythmDecay(int noteNumber) {
    if (noteNumber <= 37) return 150;
    if (noteNumber <= 40) return 95;
    if (noteNumber <= 44) return 45;
    return 70;
  }

  float rhythmFreq(int noteNumber) {
    if (noteNumber <= 37) return 85;
    if (noteNumber <= 40) return 180;
    if (noteNumber <= 44) return 900;
    return 520;
  }

  Waveform rhythmWave(int noteNumber) {
    if (noteNumber <= 37) return Waves.SINE;
    if (noteNumber <= 40) return Waves.SQUARE;
    return Waves.SAW;
  }

  boolean finished() {
    return millis() >= releaseAtMs + 20;
  }
}
