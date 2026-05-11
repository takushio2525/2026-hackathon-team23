class PartManager {
  ArrayList<Voice> voices = new ArrayList<Voice>();
  Waveform brassWaveform;

  PartManager() {
    brassWaveform = WavetableGenerator.gen10(
      4096,
      new float[] { 1.00, 0.70, 0.50, 0.30, 0.20, 0.10, 0.05 }
    );
  }

  void handleNote(NotePacket packet) {
    if (muted) return;
    if (!isKnownPart(packet.partId)) {
      dropPacket("unknown part: " + packet.partId, packet);
      return;
    }
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
      voice = new BrassVoice(partId, noteNumber, amp, dur, brassWaveform);
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
    int note = partId == PART_RHYTHM ? 36 : 60 + (partId - PART_BRASS_1) * 4;
    noteOn(partId, note, 100, DEFAULT_TEST_DURATION_MS);
    lastWarning = "test note: " + partName(partId);
  }

  float velocityToAmp(int velocity) {
    return constrain(velocity, 0, 127) / 127.0;
  }
}
