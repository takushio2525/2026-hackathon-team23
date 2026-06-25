/* ==========================================================================
   ResynthVoice — 1 音ぶんの加算合成ボイス (Minim UGen)。
   共有タブ: 各スケッチから symlink で参照。
   ========================================================================== */
class ResynthVoice extends UGen {
  InstrModel m;
  int   midiNote;
  float targetF0;
  float gain;
  boolean simpleADSR;

  int   partId = -1;
  int   instrumentIdx = -1;
  int   scheduledOffMs = Integer.MAX_VALUE;

  float[] phase;
  double  noisePos;
  float   tSec = 0;
  float   vibPhase = 0, tremPhase = 0;
  boolean done = false;
  volatile boolean releasing = false;
  float releaseStartT = 0, releaseStartLevel = 0, releaseHoldWarpT = 0;
  float origDur, headT, loopLen;

  ResynthVoice(InstrModel model, int midi, float velocity, boolean simple){
    this.m = model; this.midiNote = midi;
    this.targetF0 = 440f * pow(2, (midi-69)/12.0f);
    this.gain = constrain(velocity, 0, 1.5f);
    this.simpleADSR = simple;
    phase = new float[m.N];
    for (int i=0;i<m.N;i++) phase[i] = m.harmPhase[i];
    origDur = m.origDurSec();
    headT   = m.loopStartSec;
    loopLen = max(m.loopEndSec - m.loopStartSec, 1e-3f);
  }
  float relSec(){ return max(m.releaseSec, 0.02f); }

  void noteOff(){
    if (releasing) return;
    releaseStartLevel = sustainBodyLevel(tSec);
    releaseHoldWarpT  = warpBody(tSec);
    releaseStartT     = tSec;
    releasing = true;
  }
  float sustainBodyLevel(float t){
    if (simpleADSR){
      float a=m.attackSec, d=m.decaySec, s=m.sustainLevel;
      if (t < a) return t/max(a,1e-4f);
      if (!m.sustaining){
        if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, 0.02f, u); }
        return 0.02f;
      }
      if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, s, u); }
      return s;
    }
    return sampleCurve(m.envValues, m.envRate, warpBody(t));
  }
  float warpBody(float t){
    if (!m.sustaining) return min(t, origDur);
    if (t < headT) return t;
    float u = (t - headT) % loopLen;
    return m.loopStartSec + u;
  }
  float ampAt(float t){
    if (!releasing) return sustainBodyLevel(t);
    float u = (t - releaseStartT) / relSec();
    if (u >= 1) return 0;
    float k = 1 - u;
    return releaseStartLevel * k * k;
  }
  float harmEnvAt(int k, float t){
    float[] he = m.harmEnv[k];
    float rate = (he.length-1)/max(origDur, 1e-3f);
    float warpT = releasing ? releaseHoldWarpT : warpBody(t);
    return sampleCurve(he, rate, warpT);
  }
  float noiseEnvAt(float t){
    float warpT = releasing ? releaseHoldWarpT : warpBody(t);
    return sampleCurve(m.noiseEnv, m.noiseEnvRate, warpT);
  }
  float sampleCurve(float[] c, float rate, float sec){
    if (c.length==1) return c[0];
    float idx = sec*rate;
    if (idx <= 0) return c[0];
    if (idx >= c.length-1) return c[c.length-1];
    int i0=(int)idx, i1=i0+1; float f=idx-i0;
    return c[i0]+(c[i1]-c[i0])*f;
  }
  protected void uGenerate(float[] channels){
    float sr = sampleRate();
    if (done){ for (int i=0;i<channels.length;i++) channels[i]=0; return; }
    float a = ampAt(tSec);
    float pitchMul = 1.0f;
    if (!simpleADSR && m.vibDepthCents > 0.01f && m.vibRateHz > 0.001f){
      float vg = m.vibOnsetSec > 0.001f ? min(1, tSec/m.vibOnsetSec) : 1;
      pitchMul = pow(2, (m.vibDepthCents*0.5f*vg*sin(vibPhase))/1200.0f);
      vibPhase += TWO_PI * m.vibRateHz / sr; if (vibPhase >= TWO_PI) vibPhase -= TWO_PI;
    }
    float s = 0;
    for (int k=0;k<m.N;k++){
      float amp = m.harmAmp[k]; if (amp<=0) continue;
      int   n1  = m.harmN[k];
      float f   = targetF0 * m.harmRatio[k] * sqrt(1 + m.inharmB*n1*n1) * pitchMul;
      if (f >= sr*0.5f) continue;
      phase[k] += TWO_PI * f / sr;
      if (phase[k] >= TWO_PI) phase[k] -= TWO_PI;
      s += amp * (simpleADSR ? 1.0f : harmEnvAt(k, tSec)) * sin(phase[k]);
    }
    s *= m.harmNorm;
    if (!simpleADSR && m.noiseLevel > 0 && m.noiseTable.length > 1){
      float relMul = releasing ? max(0, 1-(tSec-releaseStartT)/relSec()) : 1;
      float ne = noiseEnvAt(tSec) * m.noiseLevel * relMul;
      s += m.noiseTable[(int)noisePos] * ne;
      noisePos += 1; if (noisePos >= m.noiseTable.length) noisePos -= m.noiseTable.length;
    }
    if (!simpleADSR && m.tremDepth > 0.001f && m.tremRateHz > 0.001f){
      s *= 1.0f - m.tremDepth*0.5f + m.tremDepth*0.5f*sin(tremPhase);
      tremPhase += TWO_PI * m.tremRateHz / sr; if (tremPhase >= TWO_PI) tremPhase -= TWO_PI;
    }
    s *= a * gain * 0.9f;
    for (int i=0;i<channels.length;i++) channels[i] = s;
    tSec += 1.0f/sr;
    if (releasing && (tSec - releaseStartT) >= relSec()) done = true;
    else if (!done && a <= 1e-4f && tSec > 0.15f) done = true;
  }
}
