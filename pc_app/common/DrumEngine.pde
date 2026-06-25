/* ==========================================================================
   DrumEngine — ドラム音色・合成・再生クラス群 + MetroClick
   共有タブ: 各スケッチから symlink で参照。

   含まれるクラス:
     DrumTimbreData    — ドラム JSON を読む
     DrumNote          — 合成ドラム (Oscil 倍音 + Noise + ADSR)
     RecordedDrumNote  — 原音サンプル再生
     ActiveDrumSynth   — DrumNote のライフサイクル管理
     MetroClick        — メトロノームの短いクリック音 (UGen)

   グローバル依存: out (AudioOutput)
   ========================================================================== */

// ── ドラム定数 ───────────────────────────────────────────
final int   KICK_DRUM         = 36;
final int   SNARE_DRUM        = 38;
final int   CLOSED_HI_HAT     = 42;
final int   CRASH_CYMBAL      = 49;
final float RECORDED_DRUM_GAIN = 2.0f;
final int   MAX_DRUM_HARMONICS = 12;
final int   MAX_DRUM_POLYPHONY = 12;
final float DRUM_AMPLITUDE     = 0.075f;
final String[] DRUM_INSTRUMENT_FILES = {
  "4_kick.tweaked.instrument.json",
  "5_snare.tweaked.instrument.json",
  "6_hi_hat.tweaked.instrument.json",
  "7_crash.tweaked.instrument.json"
};


class DrumTimbreData {
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

  DrumTimbreData(String filename){
    JSONObject json = loadJSONObject(sketchPath("data/" + filename));
    if (json == null) throw new RuntimeException("ドラム音色 JSON を読み込めません: " + filename);

    name = json.getString("name");
    fundamentalHz = json.getFloat("fundamental_hz", 440.0f);
    JSONObject sourceEnvelope = json.getJSONObject("envelope");
    attackSec = sourceEnvelope.getFloat("attack_sec");
    decaySec = sourceEnvelope.getFloat("decay_sec");
    sustainLevel = sourceEnvelope.getFloat("sustain_level");
    releaseSec = sourceEnvelope.getFloat("release_sec");
    noiseLevel = json.hasKey("noise") ? json.getJSONObject("noise").getFloat("level", 0) : 0;

    JSONArray sourceHarmonics = json.getJSONArray("harmonics");
    int harmonicCount = min(MAX_DRUM_HARMONICS, sourceHarmonics.size());
    harmonicRatios = new float[harmonicCount];
    harmonicGains = new float[harmonicCount];
    float gainSum = 0;
    for (int i = 0; i < harmonicCount; i++){
      JSONObject harmonic = sourceHarmonics.getJSONObject(i);
      harmonicRatios[i] = harmonic.getFloat("ratio");
      harmonicGains[i] = harmonic.getFloat("amp");
      gainSum += harmonicGains[i];
    }
    if (gainSum <= 0) throw new RuntimeException("倍音の振幅合計が 0 以下: " + filename);
    for (int i = 0; i < harmonicCount; i++) harmonicGains[i] /= gainSum;

    if (json.hasKey("drum_sample")){
      JSONObject sourceDrumSample = json.getJSONObject("drum_sample");
      JSONArray sourceValues = sourceDrumSample.getJSONArray("values");
      if (sourceValues != null && sourceValues.size() > 0){
        drumSample = new float[sourceValues.size()];
        for (int i = 0; i < drumSample.length; i++) drumSample[i] = sourceValues.getFloat(i);
        drumSampleRate = sourceDrumSample.getFloat("sample_rate", 44100.0f);
      }
    }
  }
}


class DrumNote implements Instrument {
  Summer mix;
  Noise noise;
  ADSR envelope;

  DrumNote(int noteNumber, float amplitude){
    mix = new Summer();
    DrumTimbreData timbre = drumTimbres[drumTimbreIndex(noteNumber)];
    for (int i = 0; i < timbre.harmonicRatios.length; i++){
      Oscil harmonic = new Oscil(timbre.fundamentalHz * timbre.harmonicRatios[i],
                                 amplitude * timbre.harmonicGains[i], Waves.SINE);
      harmonic.patch(mix);
    }
    float noiseAmplitude = amplitude * timbre.noiseLevel * drumNoiseScale(noteNumber);
    if (noiseAmplitude > 0.001f){
      noise = new Noise(noiseAmplitude, Noise.Tint.WHITE);
      noise.patch(mix);
    }
    envelope = new ADSR(1.0f, timbre.attackSec, timbre.decaySec,
                        timbre.sustainLevel, timbre.releaseSec);
    mix.patch(envelope);
  }

  void noteOn(float duration){ envelope.noteOn(); envelope.patch(out); }
  void noteOff(){ envelope.unpatchAfterRelease(out); envelope.noteOff(); }
}


class RecordedDrumNote implements Instrument {
  AudioSample sample;
  float amplitude;

  RecordedDrumNote(AudioSample sample, float amplitude){
    this.sample = sample;
    this.amplitude = amplitude;
  }

  void noteOn(float duration){
    sample.setGain(linearToDecibels(constrain(amplitude * RECORDED_DRUM_GAIN, 0.001f, 1.0f)));
    sample.trigger();
  }
  void noteOff(){}
}


class ActiveDrumSynth {
  DrumNote note;
  int offAtMs;
  boolean released;
  int releaseMs;

  ActiveDrumSynth(DrumNote n, int offMs){
    note = n;
    offAtMs = offMs;
    released = false;
    releaseMs = 0;
  }
}


class MetroClick extends UGen {
  float freq = 880;
  float phase = 0;
  float tSec = 0;
  float duration = 0.05f;
  float gain;
  boolean done = false;

  MetroClick(float g){ this.gain = g; }

  protected void uGenerate(float[] channels){
    if (done){ for (int i=0; i<channels.length; i++) channels[i]=0; return; }
    float env;
    if (tSec < 0.005f) env = tSec / 0.005f;
    else env = max(0, 1.0f - (tSec - 0.005f) / (duration - 0.005f));
    float s = sin(phase) * env * gain * 0.25f;
    for (int i=0; i<channels.length; i++) channels[i] = s;
    phase += TWO_PI * freq / sampleRate();
    if (phase >= TWO_PI) phase -= TWO_PI;
    tSec += 1.0f / sampleRate();
    if (tSec >= duration) done = true;
  }
}
