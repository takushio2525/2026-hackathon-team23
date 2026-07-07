/* ==========================================================================
   AudioManager — 楽器ロード・発音管理・ドラム管理の共通関数群
   共有タブ: 各スケッチから symlink で参照。

   グローバル依存 (各スケッチの main .pde で宣言が必要):
     Minim minim;  AudioOutput out;
     ArrayList<File> instrumentFiles;  ArrayList<InstrModel> models;
     ArrayList<String> modelLabels;
     ArrayList<ResynthVoice> activeVoices;
     DrumTimbreData[] drumTimbres;  AudioSample[] recordedDrumSamples;
     ArrayList<ActiveDrumSynth> activeDrumSynths;
     ArrayList<MetroClick> metroClicks;
     float masterVolume;  boolean useSimpleADSR;
     int MAX_POLYPHONY;  // 各スケッチで final 定義
   ========================================================================== */

// ── 楽器定義のスキャン / ロード ─────────────────────────────
void rescanInstruments(){
  instrumentFiles.clear();
  File dir = new File(dataPath(""));
  File[] fs = dir.exists() ? dir.listFiles() : null;
  if (fs != null){
    for (File f : fs) if (f.isFile() && f.getName().toLowerCase().endsWith(".json")) instrumentFiles.add(f);
    java.util.Collections.sort(instrumentFiles, new java.util.Comparator<File>(){
      public int compare(File a, File b){ return a.getName().compareToIgnoreCase(b.getName()); }
    });
  }
  models.clear(); modelLabels.clear();
  for (File f : instrumentFiles){
    try {
      JSONObject root = loadJSONObject(f.getAbsolutePath());
      InstrModel m = new InstrModel(root, out.sampleRate());
      models.add(m);
      modelLabels.add(f.getName() + "  —  " + root.getString("name","instrument"));
      println("loaded[" + (models.size()-1) + "] " + f.getName());
    } catch (Exception e){
      models.add(null);
      modelLabels.add(f.getName() + "  [読込失敗]");
      println("[エラー] " + f.getName() + ": " + e);
    }
  }
}

InstrModel modelForId(int id){
  if (models.isEmpty()) return null;
  int idx = constrain(id, 0, models.size()-1);
  InstrModel m = models.get(idx);
  if (m != null) return m;
  for (InstrModel mm : models) if (mm != null) return mm;
  return null;
}

// ── ドラム ─────────────────────────────────────────────────
boolean isDrumInstrument(int instrumentId){ return instrumentId >= 4; }

int drumTimbreIndex(int noteNumber){
  if (noteNumber == KICK_DRUM) return 0;
  if (noteNumber == SNARE_DRUM) return 1;
  if (noteNumber == CLOSED_HI_HAT) return 2;
  if (noteNumber == CRASH_CYMBAL) return 3;
  return 2;
}

float drumNoiseScale(int noteNumber){
  if (noteNumber == KICK_DRUM) return 0.14f;
  if (noteNumber == SNARE_DRUM) return 0.45f;
  if (noteNumber == CRASH_CYMBAL) return 0.30f;
  return 0.42f;
}

float linearToDecibels(float amplitude){ return 20.0f * log(amplitude) / log(10.0f); }

void loadDrumTimbres(){
  drumTimbres = new DrumTimbreData[DRUM_INSTRUMENT_FILES.length];
  for (int i = 0; i < DRUM_INSTRUMENT_FILES.length; i++)
    drumTimbres[i] = new DrumTimbreData(DRUM_INSTRUMENT_FILES[i]);
  recordedDrumSamples = new AudioSample[drumTimbres.length];
  for (int i = 0; i < drumTimbres.length; i++)
    recordedDrumSamples[i] = createRecordedDrumSample(drumTimbres[i]);
}

AudioSample createRecordedDrumSample(DrumTimbreData timbre){
  if (timbre.drumSample == null || timbre.drumSample.length == 0) return null;
  javax.sound.sampled.AudioFormat format = new javax.sound.sampled.AudioFormat(
    timbre.drumSampleRate, 16, 1, true, true
  );
  return minim.createSample(timbre.drumSample, format, 512);
}

// パート別オクターブ移調
int brassOctaveShift(int instrumentId){
  switch (instrumentId){
    case 0: return  12;   // トランペット → C5
    case 1: return   0;   // ホルン → C4
    case 2: return  12;   // フルート → C5
    case 3: return -12;   // オルガン → C3
    default: return  0;
  }
}

float brassPartAmplitude(int instrumentId){
  switch (instrumentId){
    case 0: return 0.20f;  // トランペット
    case 1: return 0.17f;  // ホルン
    case 2: return 0.18f;  // フルート
    case 3: return 0.25f;  // オルガン
    default: return 0.18f;
  }
}

// ── 発音管理 ──────────────────────────────────────────────
void triggerNote(int partId, int instrumentId, int midi, int velocity, int durationMs){
  if (isDrumInstrument(instrumentId)){
    triggerDrumNote(midi, velocity, durationMs);
    return;
  }
  InstrModel m = modelForId(instrumentId);
  if (m == null) return;
  int guard = 0;
  while (countNonReleasing() >= MAX_POLYPHONY && guard++ < MAX_POLYPHONY){
    for (ResynthVoice v : activeVoices){ if (!v.releasing){ v.noteOff(); break; } }
  }
  int effectiveMidi = midi + brassOctaveShift(instrumentId);
  float g = constrain(velocity / 127.0f, 0.0f, 1.0f) * brassPartAmplitude(instrumentId) * masterVolume;
  ResynthVoice v = new ResynthVoice(m, effectiveMidi, g, useSimpleADSR);
  v.partId        = partId;
  v.instrumentIdx = constrain(instrumentId, 0, max(0, models.size()-1));
  v.scheduledOffMs = millis() + max(40, durationMs);
  v.patch(out);
  activeVoices.add(v);
}

void triggerDrumNote(int noteNumber, int velocity, int durationMs){
  int idx = drumTimbreIndex(noteNumber);
  float amplitude = DRUM_AMPLITUDE * constrain(velocity / 127.0f, 0.0f, 1.0f) * masterVolume;
  AudioSample sample = recordedDrumSamples[idx];
  if (sample != null){
    sample.setGain(linearToDecibels(constrain(amplitude * RECORDED_DRUM_GAIN, 0.001f, 1.0f)));
    sample.trigger();
    return;
  }
  while (activeDrumSynths.size() >= MAX_DRUM_POLYPHONY && !activeDrumSynths.isEmpty()){
    ActiveDrumSynth oldest = activeDrumSynths.remove(0);
    if (!oldest.released) oldest.note.noteOff();
  }
  DrumNote dn = new DrumNote(noteNumber, amplitude);
  dn.noteOn(0);
  int drumDurMs = max(durationMs, 500);
  activeDrumSynths.add(new ActiveDrumSynth(dn, millis() + drumDurMs));
}

int countNonReleasing(){
  int n = 0; for (ResynthVoice v : activeVoices) if (!v.releasing) n++; return n;
}

void releaseMatching(int partId, int midi){
  for (ResynthVoice v : activeVoices)
    if (!v.releasing && v.partId == partId && v.midiNote == midi) v.noteOff();
}

void stopAll(){
  for (ResynthVoice v : activeVoices) v.unpatch(out);
  activeVoices.clear();
  for (ActiveDrumSynth ds : activeDrumSynths){ if (!ds.released) ds.note.noteOff(); }
  activeDrumSynths.clear();
  for (MetroClick mc : metroClicks) mc.unpatch(out);
  metroClicks.clear();
}

void playTestChord(){
  int[] chord = {60, 64, 67};
  for (int i=0;i<chord.length;i++) triggerNote(0x02+i, i, chord[i], 100, 900);
}

void playTestNoteOnInstrument(int idx){
  triggerNote(0x02, idx, 60, 100, 1000);
}

// ── ボイスのライフサイクル管理 (draw() から毎フレーム呼ぶ) ──
void updateVoiceLifecycle(){
  int now = millis();
  for (ResynthVoice v : activeVoices) if (!v.releasing && now >= v.scheduledOffMs) v.noteOff();
  for (Iterator<ResynthVoice> it = activeVoices.iterator(); it.hasNext();){
    ResynthVoice v = it.next();
    if (v.done){ v.unpatch(out); it.remove(); }
  }
  for (Iterator<ActiveDrumSynth> it = activeDrumSynths.iterator(); it.hasNext();){
    ActiveDrumSynth ds = it.next();
    if (!ds.released && now >= ds.offAtMs){ ds.note.noteOff(); ds.released = true; ds.releaseMs = now; }
    if (ds.released && now - ds.releaseMs > 500){ ds.note.envelope.unpatch(out); it.remove(); }
  }
}
