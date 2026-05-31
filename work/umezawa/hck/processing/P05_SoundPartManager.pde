class PartManager {
  ArrayList<Voice> voices = new ArrayList<Voice>();
  BrassProfile tubaProfile;
  BrassProfile tromboneProfile;
  BrassProfile hornProfile;
  BrassProfile trumpetProfile;

  PartManager() {
    tubaProfile = makeBrassProfile(new float[] { 1.00, 0.42, 0.20, 0.10 }, 45, 90, 0.85, 130, 1.15, -12);
    tromboneProfile = makeBrassProfile(new float[] { 1.00, 0.68, 0.46, 0.24, 0.14 }, 30, 70, 0.80, 110, 1.00, -5);
    hornProfile = makeBrassProfile(new float[] { 1.00, 0.48, 0.28, 0.15, 0.08 }, 55, 95, 0.70, 140, 0.90, 0);
    trumpetProfile = makeBrassProfile(new float[] { 1.00, 0.92, 0.70, 0.48, 0.30, 0.18, 0.10 }, 12, 35, 0.78, 70, 0.95, 7);
  }

  void handleNote(NotePacket packet) {
    if (muted) return;
    if (packet.gate == 0 || packet.velocity == 0 || packet.noteNumber == 0) {
      noteOff(packet.partId, packet.noteNumber);
      return;
    }
    noteOn(packet.partId, packet.noteNumber, packet.velocity, packet.durationMs);
  }

  void noteOn(int partId, int noteNumber, int velocity, int durationMs) {
    enforceVoiceLimit(partId);
    float amp = velocityToAmp(velocity) * MASTER_GAIN;
    int dur = max(durationMs, MIN_DURATION_MS);

    Voice voice;
    if (partId == PART_RHYTHM) {
      voice = new RhythmVoice(partId, noteNumber, amp, dur);
    } else {
      voice = new BrassVoice(partId, noteNumber, amp, dur, brassProfileFor(partId));
    }
    voices.add(voice);
    voice.start();
    logger.logEvent("voice_on,0x" + hex(partId, 2) + "," + noteNumber + "," + velocity + "," + dur);
  }

  void noteOff(int partId, int noteNumber) {
    for (Voice v : voices) {
      if (v.partId == partId && (noteNumber == 0 || v.noteNumber == noteNumber)) {
        v.release();
      }
    }
    logger.logEvent("voice_off,0x" + hex(partId, 2) + "," + noteNumber);
  }

  void enforceVoiceLimit(int partId) {
    int count = 0;
    Voice oldest = null;
    for (Voice v : voices) {
      if (v.partId == partId && !v.releasing) {
        count++;
        if (oldest == null || v.startedAtMs < oldest.startedAtMs) oldest = v;
      }
    }
    if (count >= MAX_VOICES_PER_PART && oldest != null) {
      oldest.release();
    }
  }

  void update() {
    for (int i = voices.size() - 1; i >= 0; i--) {
      Voice v = voices.get(i);
      v.update();
      if (v.finished()) {
        v.stop();
        voices.remove(i);
      }
    }
  }

  void releaseAll() {
    for (Voice v : voices) v.release();
  }

  int activeVoiceCount() {
    return voices.size();
  }

  void playTestNote(int partId) {
    if (muted) muted = false;
    int note = testNoteFor(partId);
    noteOn(partId, note, 100, DEFAULT_TEST_DURATION_MS);
    lastWarning = "テスト音: " + partName(partId);
  }

  BrassProfile makeBrassProfile(float[] harmonics, int attackMs, int decayMs, float sustain, int releaseMs, float gain, int noteShift) {
    return new BrassProfile(WavetableGenerator.gen10(4096, harmonics), attackMs, decayMs, sustain, releaseMs, gain, noteShift);
  }

  BrassProfile brassProfileFor(int partId) {
    if (partId == PART_BRASS_1) return tubaProfile;
    if (partId == PART_BRASS_2) return tromboneProfile;
    if (partId == PART_BRASS_3) return hornProfile;
    if (partId == PART_BRASS_4) return trumpetProfile;
    return trumpetProfile;
  }

  int testNoteFor(int partId) {
    if (partId == PART_BRASS_1) return 48;
    if (partId == PART_BRASS_2) return 55;
    if (partId == PART_BRASS_3) return 60;
    if (partId == PART_RHYTHM) return 36;
    if (partId == PART_BRASS_4) return 65;
    return 60;
  }

  float velocityToAmp(int velocity) {
    return constrain(velocity, 0, 127) / 127.0;
  }
}
