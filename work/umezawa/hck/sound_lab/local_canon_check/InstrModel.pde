/* ==========================================================================
   InstrModel — sound_lab の JSON を解釈して合成に必要な配列を保持。
   共有タブ: 各スケッチから symlink で参照。
   ========================================================================== */
class InstrModel {
  float fundamentalHz;  int midiNote;  String noteName;
  boolean sustaining;   float inharmB;  int harmonicCount;
  int     N;
  int[]   harmN;
  float[] harmRatio;
  float[] harmAmp;
  float[] harmPhase;
  float[][] harmEnv;
  int     envPoints;
  float   harmNorm;
  float[] envValues;  float envRate;
  float attackSec, decaySec, sustainLevel, releaseSec, loopStartSec, loopEndSec;
  float   noiseLevel;
  float[] noiseEnv;   float noiseEnvRate;
  float[] noiseTable;
  float   vibRateHz, vibDepthCents, vibOnsetSec;
  float   tremRateHz, tremDepth;

  InstrModel(JSONObject root, float synthSampleRate){
    fundamentalHz = root.getFloat("fundamental_hz", 261.626f);
    midiNote      = root.getInt("midi_note", 60);
    noteName      = root.getString("note_name", "C4");
    sustaining    = root.getBoolean("sustaining", true);
    inharmB       = root.getFloat("inharmonicity_b", 0.0f);

    JSONObject e = root.getJSONObject("envelope");
    envValues  = toFloatArray(e.getJSONArray("values"));
    envRate    = e.getFloat("rate_hz", 200);
    attackSec  = e.getFloat("attack_sec", 0.01f);
    decaySec   = e.getFloat("decay_sec", 0.05f);
    sustainLevel = e.getFloat("sustain_level", 0.7f);
    releaseSec = e.getFloat("release_sec", 0.08f);
    loopStartSec = e.getFloat("loop_start_sec", (envValues.length-1)/envRate*0.4f);
    loopEndSec   = e.getFloat("loop_end_sec",   (envValues.length-1)/envRate*0.7f);
    if (envValues.length < 2){ envValues = new float[]{0,1,1,0}; envRate=10; }
    if (loopEndSec <= loopStartSec) loopEndSec = loopStartSec + max(0.05f, 1.0f/envRate);

    JSONArray ha = root.getJSONArray("harmonics");
    N = ha.size();
    harmN=new int[N]; harmRatio=new float[N]; harmAmp=new float[N]; harmPhase=new float[N];
    harmEnv=new float[N][]; envPoints=1;
    float sumAmp=0;
    for (int i=0;i<N;i++){
      JSONObject h = ha.getJSONObject(i);
      harmN[i]     = h.getInt("n", i+1);
      harmRatio[i] = h.getFloat("ratio", harmN[i]);
      harmAmp[i]   = h.getFloat("amp", 0);
      harmPhase[i] = h.getFloat("phase", 0);
      JSONArray ev = h.hasKey("env") ? h.getJSONArray("env") : null;
      harmEnv[i]   = (ev!=null && ev.size()>=2) ? toFloatArray(ev) : new float[]{1,1};
      envPoints    = max(envPoints, harmEnv[i].length);
      if (harmAmp[i]>0) sumAmp += harmAmp[i];
    }
    harmNorm = 1.0f / max(sumAmp, 1.0f);
    harmonicCount = 0; for (int i=0;i<N;i++) if (harmAmp[i]>0) harmonicCount++;

    JSONObject no = root.hasKey("noise") ? root.getJSONObject("noise") : null;
    noiseLevel   = no!=null ? no.getFloat("level", 0) : 0;
    noiseEnv     = (no!=null && no.hasKey("envelope")) ? toFloatArray(no.getJSONArray("envelope")) : new float[]{1,1};
    noiseEnvRate = no!=null ? no.getFloat("rate_hz", 200) : 200;
    float[] bandsHz  = (no!=null && no.hasKey("bands_hz"))    ? toFloatArray(no.getJSONArray("bands_hz"))    : new float[]{0,(int)(synthSampleRate/2)};
    float[] bandLevs = (no!=null && no.hasKey("band_levels")) ? toFloatArray(no.getJSONArray("band_levels")) : new float[]{1};
    noiseTable = makeShapedNoise(synthSampleRate, bandsHz, bandLevs);

    JSONObject mod = root.hasKey("modulation") ? root.getJSONObject("modulation") : null;
    JSONObject vib = (mod!=null && mod.hasKey("vibrato")) ? mod.getJSONObject("vibrato") : null;
    JSONObject trem= (mod!=null && mod.hasKey("tremolo")) ? mod.getJSONObject("tremolo") : null;
    vibRateHz     = (vib!=null && vib.getBoolean("detected", false)) ? vib.getFloat("rate_hz", 0) : 0;
    vibDepthCents = (vib!=null && vib.getBoolean("detected", false)) ? vib.getFloat("depth_cents", 0) : 0;
    vibOnsetSec   = (vib!=null) ? vib.getFloat("onset_sec", 0) : 0;
    tremRateHz    = (trem!=null && trem.getBoolean("detected", false)) ? trem.getFloat("rate_hz", 0) : 0;
    tremDepth     = (trem!=null && trem.getBoolean("detected", false)) ? constrain(trem.getFloat("depth", 0),0,0.95f) : 0;
  }

  float[] makeShapedNoise(float sr, float[] bandsHz, float[] bandLevs){
    if (noiseLevel <= 0.0005f) return new float[]{0};
    int Nfft = 16384;
    float[] buf = new float[Nfft];
    for (int i=0;i<Nfft;i++) buf[i] = random(-1,1);
    FFT fft = new FFT(Nfft, sr);
    fft.forward(buf);
    int bands = fft.specSize();
    for (int b=0;b<bands;b++){
      float fc = b * sr / Nfft;
      fft.setBand(b, fft.getBand(b) * bandGain(fc, bandsHz, bandLevs));
    }
    fft.inverse(buf);
    float mx=1e-9f; for (int i=0;i<Nfft;i++) mx=max(mx, abs(buf[i]));
    for (int i=0;i<Nfft;i++) buf[i] /= mx;
    return buf;
  }
  float bandGain(float fc, float[] bandsHz, float[] bandLevs){
    for (int i=0;i<bandLevs.length;i++){
      float lo = bandsHz[min(i, bandsHz.length-1)], hi = bandsHz[min(i+1, bandsHz.length-1)];
      if (fc >= lo && fc < hi) return bandLevs[i];
    }
    return bandLevs[bandLevs.length-1];
  }
  float origDurSec(){ return (envValues.length-1)/envRate; }
}

float[] toFloatArray(JSONArray a){
  float[] r = new float[a.size()];
  for (int i=0;i<a.size();i++) r[i] = a.getFloat(i);
  return r;
}
