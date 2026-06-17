/* ==========================================================================
   engine.js — sound_lab スタジオのリアルタイム再合成エンジン (Web Audio)

   解析結果(instrument 定義)を読み込み、押している間ずっと鳴らしながら、
   ビブラート・倍音バランス・ノイズ(息)・響き・各種エフェクトを *鳴らしたまま* いじれる。

   主な公開 API (SL.LiveSynth):
     await synth.ensureCtx()              … AudioContext を起こす(ユーザー操作後に呼ぶ)
     synth.load(instrument)               … 音色を読み込み、パラメータを既定値に
     synth.params                          … 現在の編集パラメータ(オブジェクト)
     synth.set(key, value)                … パラメータを 1 つ変更 → 鳴っている音に即反映
     synth.applyAll()                     … 全パラメータを現在のノードへ反映
     synth.resetAll() / resetSection(sec) … 既定値に戻す
     synth.noteOn(midi, vel) / noteOff(midi) / panic()
     synth.setDrone(on)                   … 現在の音を鳴らしっぱなしにする(ハンズフリー編集用)
     synth.setOriginalBuffer(buf) / playOriginal() / stopOriginal()   … 原音 A/B 比較
     synth.exportInstrument()             … 調整を畳み込んだ新しい instrument 定義を返す
     await synth.renderWav(midi, sec)     … 現在の音を WAV(Blob) に書き出す

   フォーマット: ../library_format.md
   ========================================================================== */
"use strict";
window.SL = window.SL || {};

(function () {
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const midiToHz = (m) => 440 * Math.pow(2, (m - 69) / 12);
  const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  SL.midiName = (m) => NOTE_NAMES[((m % 12) + 12) % 12] + (Math.floor(m / 12) - 1);
  SL.midiToHz = midiToHz;

  // 1 次元カーブを n 点に線形リサンプル
  function resampleCurve(arr, n) {
    arr = Array.from(arr || [0]);
    if (arr.length === 0) arr = [0];
    if (arr.length === n) return Float32Array.from(arr);
    if (arr.length === 1) return new Float32Array(n).fill(arr[0]);
    const out = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      const x = (i / (n - 1)) * (arr.length - 1);
      const i0 = Math.floor(x), i1 = Math.min(arr.length - 1, i0 + 1);
      out[i] = arr[i0] + (arr[i1] - arr[i0]) * (x - i0);
    }
    return out;
  }
  // 時刻 sec の値を線形補間で取り出す(レート rateHz の配列)
  function sampleAt(arr, rateHz, sec) {
    if (!arr || arr.length === 0) return 0;
    if (arr.length === 1) return arr[0];
    const x = sec * rateHz;
    if (x <= 0) return arr[0];
    if (x >= arr.length - 1) return arr[arr.length - 1];
    const i0 = Math.floor(x), i1 = i0 + 1;
    return arr[i0] + (arr[i1] - arr[i0]) * (x - i0);
  }
  // 走行中の AudioParam を時刻 t で固定してから新しい自動化を載せる(setValueCurve 中でも安全)
  function holdParam(param, t) {
    try { param.cancelAndHoldAtTime(t); }
    catch (_) { const v = param.value; try { param.cancelScheduledValues(t); } catch (__) {} param.setValueAtTime(v, t); }
  }

  // ── リバーブ用インパルス応答(指数減衰ノイズ + ダンピング LPF) ──
  function makeImpulseResponse(ctx, seconds, decay, damping, width) {
    const rate = ctx.sampleRate, len = Math.max(8, Math.floor(rate * seconds));
    const ir = ctx.createBuffer(2, len, rate);
    const a = clamp(damping, 0, 0.985);          // 高いほど暗い(高域が早く減衰)
    for (let ch = 0; ch < 2; ch++) {
      const d = ir.getChannelData(ch);
      let last = 0;
      const seed = ch === 0 ? 1 : 2;             // 左右で違う乱数列(ステレオ感)
      let s = seed * 9301 + 49297;
      const rnd = () => { s = (s * 9301 + 49297) % 233280; return s / 233280 * 2 - 1; };
      for (let i = 0; i < len; i++) {
        const env = Math.pow(1 - i / len, Math.max(0.5, decay) * 3);
        const n = rnd() * env;
        last = last + (1 - a) * (n - last);      // 1 次 LPF
        d[i] = last * 6;                          // 軽く持ち上げ(後段の wet で調整)
      }
    }
    // ステレオ幅(0=モノ寄り, 1=フル) … 左右を少し混ぜる
    if (width < 0.999) {
      const L = ir.getChannelData(0), R = ir.getChannelData(1), mix = (1 - width) * 0.5;
      for (let i = 0; i < len; i++) { const l = L[i], r = R[i]; L[i] = l * (1 - mix) + r * mix; R[i] = r * (1 - mix) + l * mix; }
    }
    return ir;
  }

  // ── ドライブ(波形整形)カーブ ── soft saturation: tanh ベース。amount≈0 は完全に素通り ──
  function makeDriveCurve(amount) {
    const n = 2048, c = new Float32Array(n);
    if (amount < 0.001) { for (let i = 0; i < n; i++) c[i] = (i / (n - 1)) * 2 - 1; return c; }
    const k = 1 + amount * 28, norm = Math.tanh(k);
    for (let i = 0; i < n; i++) { const x = (i / (n - 1)) * 2 - 1; c[i] = Math.tanh(k * x) / norm; }
    return c;
  }

  // ============================================================
  //  Voice — 1 音ぶんの加算合成ボイス
  // ============================================================
  class Voice {
    constructor(synth, midi, vel) {
      const S = synth, ctx = S.ctx, P = S.params;
      this.S = S; this.midi = midi; this.vel = clamp(vel == null ? 0.92 : vel, 0.05, 1);
      this.releasing = false; this.dead = false; this.everFreq = false;
      const t0 = ctx.currentTime + 0.006;
      this.t0 = t0;
      this.baseF = midiToHz(midi);
      this.humCents = (Math.random() * 2 - 1) * (P.humanizeCents || 0);

      // 出力: 各倍音 → envGain(録音された時間形状) → ampGain(静的振幅・即編集) → amp(ADSR) → S.voiceMix
      this.amp = ctx.createGain(); this.amp.gain.value = 0;
      this.amp.connect(S.voiceMix);
      this.waveSrc = null; this.waveGain = null;
      this.attackSrc = null; this.attackGain = null;
      this.sustainSrc = null; this.sustainTone = null; this.sustainGain = null;
      this.drumSrc = null; this.drumGain = null;
      this.isTrumpet = (S.instrument && S.instrument.instrument_profile) === "trumpet";

      // ドラムは倍音合成よりも原音1打の非周期成分が本体なので、解析元サンプルを主音として鳴らす。
      const drumBuf = S._getDrumBuffer && S._getDrumBuffer();
      if (drumBuf && (P.drumSampleMix || 0) > 0.001) {
        const src = ctx.createBufferSource();
        const g = ctx.createGain();
        const smp = S.instrument.drum_sample || {};
        const root = smp.root_midi_note || S.instrument.midi_note || midi;
        const follow = !!P.drumPitchFollow;
        const rate = clamp(Math.pow(2, ((follow ? midi - root : 0) + (P.transposeSemis || 0)) / 12), 0.25, 4);
        const mix = clamp(P.drumSampleMix || 0, 0, 1.5) * this.vel * 0.9;
        src.buffer = drumBuf;
        src.playbackRate.setValueAtTime(rate, t0);
        g.gain.setValueAtTime(0, t0);
        g.gain.linearRampToValueAtTime(mix, t0 + 0.002);
        g.gain.setTargetAtTime(0.0001, t0 + Math.max(0.05, drumBuf.duration / rate * 0.98), 0.03);
        src.connect(g); g.connect(S.voiceMix);
        src.start(t0);
        try { src.stop(t0 + drumBuf.duration / rate + 0.08); } catch (_) {}
        this.drumSrc = src; this.drumGain = g;
      }

      // トランペットは倍音加算だけだと芯がサイン波寄りになりやすいので、
      // 解析した原音1周期波形を安定した主波形として薄く混ぜる。
      const wavBuf = S._getWaveCycleBuffer && S._getWaveCycleBuffer();
      if (wavBuf && (P.trumpetWaveMix || 0) > 0.001) {
        const src = ctx.createBufferSource();
        const g = ctx.createGain();
        const root = S.instrument.midi_note || midi;
        const rate = clamp(Math.pow(2, (midi - root + (P.transposeSemis || 0)) / 12), 0.25, 4);
        src.buffer = wavBuf;
        src.loop = true;
        src.playbackRate.setValueAtTime(rate, t0);
        src.connect(g); g.connect(this.amp);
        this.waveSrc = src; this.waveGain = g;
        this.applyWaveMix(true);
        src.start(t0);
      }

      // トランペットなどの立ち上がりはサイン波の倍音加算だけでは痩せやすいので、
      // 解析時に保存した原音アタックを短く重ねる。
      const atkBuf = S._getAttackBuffer && S._getAttackBuffer();
      if (atkBuf && (P.attackSampleMix || 0) > 0.001) {
        const src = ctx.createBufferSource();
        const g = ctx.createGain();
        const atk = S.instrument.attack_sample || {};
        const root = atk.root_midi_note || S.instrument.midi_note || midi;
        const semis = midi - root + (P.transposeSemis || 0);
        const rate = clamp(Math.pow(2, semis / 12), 0.25, 4);
        const pitchSafe = 1 / (1 + Math.abs(semis) * 0.08);
        const mix = clamp(P.attackSampleMix || 0, 0, 1.5) * this.vel * 0.55 * pitchSafe;
        src.buffer = atkBuf;
        src.playbackRate.setValueAtTime(rate, t0);
        g.gain.setValueAtTime(0, t0);
        g.gain.linearRampToValueAtTime(mix, t0 + 0.006);
        g.gain.setTargetAtTime(0.0001, t0 + Math.max(0.035, atkBuf.duration / rate * 0.62), 0.035);
        src.connect(g); g.connect(S.voiceMix);
        src.start(t0);
        try { src.stop(t0 + atkBuf.duration / rate + 0.08); } catch (_) {}
        this.attackSrc = src; this.attackGain = g;
      }

      // トランペットの伸びている部分に含まれる唇の細かいバズと管鳴りを薄くループして混ぜる。
      const susBuf = S._getSustainBuffer && S._getSustainBuffer();
      if (susBuf) {
        const src = ctx.createBufferSource();
        const tone = ctx.createBiquadFilter();
        const g = ctx.createGain();
        const smp = S.instrument.sustain_sample || {};
        const root = smp.root_midi_note || S.instrument.midi_note || midi;
        this.sustainPitchDelta = midi - root + (P.transposeSemis || 0);
        const rate = clamp(Math.pow(2, this.sustainPitchDelta / 12), 0.25, 4);
        src.buffer = susBuf;
        src.loop = true;
        src.loopStart = clamp(smp.loop_start_sec || 0, 0, Math.max(0, susBuf.duration - 0.002));
        src.loopEnd = clamp(smp.loop_end_sec || susBuf.duration, src.loopStart + 0.002, susBuf.duration);
        src.playbackRate.setValueAtTime(rate, t0);
        tone.type = "lowpass"; tone.frequency.value = S._sustainBufferIsFallback ? 3600 : 4800; tone.Q.value = 0.45;
        src.connect(tone); tone.connect(g); g.connect(this.amp);
        this.sustainSrc = src; this.sustainTone = tone; this.sustainGain = g;
        this.applySustainMix(true);
        src.start(t0);
      }

      // ビブラート用ゲート(onset で 0→1)
      this.vibGate = ctx.createGain(); this.vibGate.gain.value = 0;
      this.vibGate.gain.linearRampToValueAtTime(1, t0 + Math.max(0.0015, P.vibOnsetSec || 0));
      S.vibratoDepth.connect(this.vibGate);

      // 倍音(amp>0 のものだけ)
      this.harm = [];
      for (const h of S.instrument.harmonics) {
        if (!(h.amp > 0)) continue;
        const osc = ctx.createOscillator(); osc.type = "sine";
        const envGain = ctx.createGain();      // 0..1 録音の倍音エンベロープ
        const ampGain = ctx.createGain();      // 静的振幅(brightness 等を畳んだもの)
        osc.connect(envGain); envGain.connect(ampGain); ampGain.connect(this.amp);
        osc.detune.setValueAtTime((P.fineCents || 0) + this.humCents, t0);
        this.vibGate.connect(osc.detune);
        let layerOsc = null, layerEnvGain = null, layerAmpGain = null;
        if (this.isTrumpet) {
          layerOsc = ctx.createOscillator(); layerOsc.type = "sine";
          layerEnvGain = ctx.createGain();
          layerAmpGain = ctx.createGain(); layerAmpGain.gain.value = 0;
          layerOsc.connect(layerEnvGain); layerEnvGain.connect(layerAmpGain); layerAmpGain.connect(this.amp);
          this.vibGate.connect(layerOsc.detune);
        }
        this.harm.push({ n: h.n, ratio: h.ratio, ampBase: h.amp, env: (h.env && h.env.length ? h.env : [1, 1]), osc, envGain, ampGain, layerOsc, layerEnvGain, layerAmpGain });
      }
      this.origSumAmp = this.harm.reduce((s, h) => s + h.ampBase, 0) || 1;

      // ノイズ(残差 + 息)
      this.noiseSrc = ctx.createBufferSource(); this.noiseSrc.buffer = S.noiseBuffer; this.noiseSrc.loop = true;
      this.noiseHP = ctx.createBiquadFilter(); this.noiseHP.type = "highpass"; this.noiseHP.Q.value = 0.5;
      this.noiseLP = ctx.createBiquadFilter(); this.noiseLP.type = "lowpass"; this.noiseLP.Q.value = 0.5;
      this.noiseGain = ctx.createGain(); this.noiseGain.gain.value = 0;
      this.noiseSrc.connect(this.noiseHP); this.noiseHP.connect(this.noiseLP); this.noiseLP.connect(this.noiseGain); this.noiseGain.connect(this.amp);

      // 初期値を反映
      this.applyFrequencies(true);
      this.applyAmpGains(true);
      this.applyNoiseFilters(true);
      this.scheduleHarmEnvs(t0);
      this.scheduleNoiseEnv(t0);
      this.scheduleAmp(t0);

      for (const h of this.harm) {
        h.osc.start(t0);
        if (h.layerOsc) h.layerOsc.start(t0);
      }
      this.noiseSrc.start(t0);
    }

    // 倍音周波数(非調和性ミックスを反映)
    applyFrequencies(immediate) {
      const S = this.S, P = S.params, t = S.ctx.currentTime;
      const trFactor = Math.pow(2, (P.transposeSemis || 0) / 12);
      for (const h of this.harm) {
        const pure = h.n;
        const ratio = pure + (h.ratio - pure) * (P.inharmMul == null ? 1 : P.inharmMul);
        const f = clamp(this.baseF * trFactor * ratio, 1, S.ctx.sampleRate * 0.49);
        if (immediate || !this.everFreq || (P.glideMs || 0) < 6) h.osc.frequency.setValueAtTime(f, t);
        else h.osc.frequency.setTargetAtTime(f, t, Math.max(0.004, (P.glideMs || 0) / 1000 / 3));
        h.osc.detune.setValueAtTime((P.fineCents || 0) + this.humCents, t);
        if (h.layerOsc) {
          const spread = clamp(P.brassLayerDetuneCents || 0, 0, 18);
          const sign = h.n % 2 === 0 ? -0.72 : 1.0;
          const cents = spread * sign * (0.82 + Math.min(h.n, 12) * 0.018);
          if (immediate || !this.everFreq || (P.glideMs || 0) < 6) h.layerOsc.frequency.setValueAtTime(f, t);
          else h.layerOsc.frequency.setTargetAtTime(f, t, Math.max(0.004, (P.glideMs || 0) / 1000 / 3));
          h.layerOsc.detune.setValueAtTime((P.fineCents || 0) + this.humCents + cents, t);
        }
      }
      if (this.sustainSrc) {
        const smp = S.instrument.sustain_sample || {};
        const root = smp.root_midi_note || S.instrument.midi_note || this.midi;
        this.sustainPitchDelta = this.midi - root + (P.transposeSemis || 0);
        const rate = clamp(Math.pow(2, this.sustainPitchDelta / 12), 0.25, 4);
        if (immediate || !this.everFreq || (P.glideMs || 0) < 6) this.sustainSrc.playbackRate.setValueAtTime(rate, t);
        else this.sustainSrc.playbackRate.setTargetAtTime(rate, t, Math.max(0.004, (P.glideMs || 0) / 1000 / 3));
        this.applySustainMix(false);
      }
      if (this.waveSrc) {
        const root = S.instrument.midi_note || this.midi;
        const rate = clamp(Math.pow(2, (this.midi - root + (P.transposeSemis || 0)) / 12), 0.25, 4);
        if (immediate || !this.everFreq || (P.glideMs || 0) < 6) this.waveSrc.playbackRate.setValueAtTime(rate, t);
        else this.waveSrc.playbackRate.setTargetAtTime(rate, t, Math.max(0.004, (P.glideMs || 0) / 1000 / 3));
      }
      this.everFreq = true;
    }

    applyWaveMix(immediate) {
      if (!this.waveGain) return;
      const t = this.S.ctx.currentTime;
      const target = clamp(this.S.params.trumpetWaveMix || 0, 0, 1) * 0.34;
      if (immediate) this.waveGain.gain.setValueAtTime(target, t);
      else this.waveGain.gain.setTargetAtTime(target, t, 0.025);
    }

    applySustainMix(immediate) {
      if (!this.sustainGain) return;
      const t = this.S.ctx.currentTime;
      const semis = Math.abs(this.sustainPitchDelta || 0);
      const pitchSafe = 1 / (1 + semis * semis * 0.12);
      const mul = this.S._sustainBufferIsFallback ? 0.34 : 0.48;
      const target = clamp(this.S.params.sustainSampleMix || 0, 0, 0.9) * mul * pitchSafe;
      if (immediate) this.sustainGain.gain.setValueAtTime(target, t);
      else this.sustainGain.gain.setTargetAtTime(target, t, 0.025);
      if (this.sustainTone) {
        const baseCut = this.S._sustainBufferIsFallback ? 3600 : 4800;
        const cutoff = clamp(baseCut / (1 + semis * 0.08), 2200, baseCut);
        if (immediate) this.sustainTone.frequency.setValueAtTime(cutoff, t);
        else this.sustainTone.frequency.setTargetAtTime(cutoff, t, 0.03);
      }
    }

    // 倍音ごとの静的振幅: ampBase × n^brightness × exp(-rolloff(n-1)) × odd/even × 手動ゲイン × 倍音数制限
    ampScalar(h) {
      const P = this.S.params, n = h.n;
      let g = h.ampBase;
      g *= Math.pow(n, P.brightness || 0);
      g *= Math.exp(-(P.harmRolloff || 0) * (n - 1));
      if (n > 1) g *= (n % 2 === 1) ? clamp(1 + (P.oddEvenBal || 0), 0, 2) : clamp(1 - (P.oddEvenBal || 0), 0, 2);
      const man = P.harmGains && P.harmGains[n] != null ? P.harmGains[n] : 1;
      g *= clamp(man, 0, 4);
      if (n > (P.harmLimit || 999)) g = 0;
      return Math.max(0, g);
    }
    applyAmpGains(immediate) {
      const S = this.S, t = S.ctx.currentTime;
      const scal = this.harm.map((h) => this.ampScalar(h));
      const sum = scal.reduce((s, v) => s + v, 0) || 1;
      const brassLayerMix = this.isTrumpet ? clamp(S.params.brassLayerMix || 0, 0, 0.75) : 0;
      const waveMix = this.isTrumpet ? clamp(S.params.trumpetWaveMix || 0, 0, 1) : 0;
      for (let i = 0; i < this.harm.length; i++) {
        const h = this.harm[i];
        const target = (scal[i] / sum) * (S.params.harmonicGainTrim != null ? S.params.harmonicGainTrim : 1);
        const mainTarget = target * (1 - brassLayerMix * 0.16) * (1 - waveMix * 0.28);
        const layerTone = 0.5 + Math.min(h.n, 14) * 0.035;
        const layerTarget = target * brassLayerMix * layerTone;
        if (immediate) h.ampGain.gain.setValueAtTime(mainTarget, t);
        else h.ampGain.gain.setTargetAtTime(mainTarget, t, 0.02);
        if (h.layerAmpGain) {
          if (immediate) h.layerAmpGain.gain.setValueAtTime(layerTarget, t);
          else h.layerAmpGain.gain.setTargetAtTime(layerTarget, t, 0.02);
        }
      }
    }
    // 倍音ごとの時間エンベロープ: 録音された立ち上がり形 → サステイン中はループ域の平均値で保持
    scheduleHarmEnvs(t0) {
      const S = this.S, P = S.params, I = S.instrument;
      const origDur = Math.max(0.05, (I.envelope.values.length - 1) / I.envelope.rate_hz);
      const lsT = clamp(I.envelope.loop_start_sec || origDur * 0.3, 0.01, origDur * 0.95);
      const leT = clamp(I.envelope.loop_end_sec || origDur * 0.7, lsT + 1e-3, origDur);
      for (const h of this.harm) {
        const g = h.envGain.gain;
        const lg = h.layerEnvGain ? h.layerEnvGain.gain : null;
        if (!P.harmFollowEnv) { g.setValueAtTime(1, t0); continue; }
        const env = h.env, m = env.length;
        // env は origDur 全体に 32 点等間隔。head 部を切り出してリサンプル
        const headFrac = clamp(lsT / origDur, 0.02, 0.98);
        const headIdxEnd = Math.max(1, Math.round(headFrac * (m - 1)));
        const headPart = env.slice(0, headIdxEnd + 1);
        const curve = resampleCurve(headPart, Math.max(2, Math.min(64, headPart.length * 2)));
        curve[0] = Math.min(curve[0], 1);
        // サステイン値 = ループ域の平均
        const a = Math.round((lsT / origDur) * (m - 1)), b = Math.round((leT / origDur) * (m - 1));
        let s = 0, c = 0; for (let k = Math.max(0, a); k <= Math.min(m - 1, b); k++) { s += env[k]; c++; }
        const susV = c ? s / c : (env[m - 1] || 1);
        g.setValueCurveAtTime(curve, t0, Math.max(0.02, lsT));
        g.setValueAtTime(susV, t0 + Math.max(0.02, lsT));
        if (lg) {
          lg.setValueCurveAtTime(curve, t0, Math.max(0.02, lsT));
          lg.setValueAtTime(susV, t0 + Math.max(0.02, lsT));
        }
        h.susEnv = susV;
      }
    }
    // ノイズの時間エンベロープを 1 本のカーブで構築(録音形 + 立ち上がり強調 + 連続息)
    scheduleNoiseEnv(t0) {
      const S = this.S, P = S.params, I = S.instrument;
      const recEnv = I.noise && I.noise.envelope ? I.noise.envelope : [1, 1];
      const recRate = I.noise && I.noise.rate_hz ? I.noise.rate_hz : 200;
      const origDur = (I.envelope.values.length - 1) / I.envelope.rate_hz;
      const W = clamp(I.sustaining ? Math.max(origDur, 1.5) : origDur * (P.decayStretch || 1) + 0.2, 0.4, 6);
      const K = clamp(Math.round(W * 220), 64, 1600);
      const c = new Float32Array(K);
      const recLvl = (I.noise ? (I.noise.level || 0) : 0) * (P.noiseLevel == null ? 1 : P.noiseLevel);
      const atk = P.attackNoise || 0, breath = (P.breathAmount || 0) * 0.24, breathRamp = 0.03;
      for (let k = 0; k < K; k++) {
        const t = (k / (K - 1)) * W;
        let rec = sampleAt(recEnv, recRate, I.sustaining ? Math.min(t, origDur) : t);
        const ae = t < 0.12 ? 1 + atk * (1 - t / 0.12) : 1;
        const recPart = rec * ae * recLvl;
        const br = (t < breathRamp ? t / breathRamp : 1) * breath;
        c[k] = clamp((recPart + br) * this.vel, 0, 4);
      }
      c[0] = 0;
      this.noiseGain.gain.setValueCurveAtTime(c, t0, W);
      this.noiseGain.gain.setValueAtTime(c[K - 1], t0 + W);
    }
    applyNoiseFilters(immediate) {
      const S = this.S, P = S.params, t = S.ctx.currentTime, sr = S.ctx.sampleRate;
      const set = (param, v) => immediate ? param.setValueAtTime(v, t) : param.setTargetAtTime(v, t, 0.02);
      set(this.noiseHP.frequency, clamp(P.noiseHpHz || 20, 10, sr * 0.45));
      set(this.noiseLP.frequency, clamp(P.noiseLpHz || 12000, 200, sr * 0.49));
    }
    // マスター振幅 ADSR(またはADSR4値、または減衰音は録音カーブ)
    scheduleAmp(t0) {
      const S = this.S, P = S.params, I = S.instrument, g = this.amp.gain;
      const peak = this.vel;
      const useRecorded = (P.envMode === "recorded");
      if (useRecorded && I.sustaining) {
        const v = I.envelope.values, rate = I.envelope.rate_hz;
        const lsT = clamp(I.envelope.loop_start_sec || (v.length - 1) / rate * 0.3, 0.02, (v.length - 1) / rate * 0.9);
        const headIdx = Math.max(2, Math.round(lsT * rate));
        const curve = new Float32Array(headIdx + 1);
        for (let k = 0; k <= headIdx; k++) curve[k] = (v[Math.min(v.length - 1, k)] || 0) * peak;
        curve[0] = 0;
        g.setValueCurveAtTime(curve, t0, Math.max(0.02, lsT));
        const a = Math.round(lsT * rate), b = Math.round((I.envelope.loop_end_sec || (v.length - 1) / rate * 0.7) * rate);
        let s = 0, c = 0; for (let k = Math.max(0, a); k <= Math.min(v.length - 1, b); k++) { s += v[k]; c++; }
        const susV = (c ? s / c : (I.envelope.sustain_level || 0.7)) * peak;
        g.setValueAtTime(susV, t0 + Math.max(0.02, lsT));
        this.naturalEnd = Infinity; this.lastBodyLvl = susV;
      } else if (useRecorded && !I.sustaining) {
        const v = I.envelope.values, rate = I.envelope.rate_hz, origDur = (v.length - 1) / rate;
        const dur = Math.max(0.05, origDur * (P.decayStretch || 1));
        const N = clamp(Math.round(dur * 240), 64, 4000);
        const curve = new Float32Array(N);
        for (let k = 0; k < N; k++) { const tt = (k / (N - 1)) * origDur; curve[k] = sampleAt(v, rate, tt) * peak; }
        curve[0] = 0;
        g.setValueCurveAtTime(curve, t0, dur);
        g.setValueAtTime(curve[N - 1], t0 + dur);
        this.naturalEnd = t0 + dur + 0.05; this.lastBodyLvl = 0.02;
      } else {
        // ADSR 4 値
        const A = Math.max(0.001, (P.attackMs || 5) / 1000), D = Math.max(0.003, (P.decayMs || 60) / 1000);
        const Sl = clamp(P.sustainLvl == null ? 0.7 : P.sustainLvl, 0, 1);
        if (P.attackCurve === "exp") { g.setValueAtTime(0.0008, t0); g.exponentialRampToValueAtTime(Math.max(peak, 0.001), t0 + A); }
        else { g.setValueAtTime(0, t0); g.linearRampToValueAtTime(peak, t0 + A); }
        if (I.sustaining) {
          g.setTargetAtTime(Math.max(Sl * peak, 0.0001), t0 + A, D / 3);
          this.naturalEnd = Infinity; this.lastBodyLvl = Sl * peak;
        } else {
          const decTo = Math.max(0.0006, 0.02 * peak);
          g.setTargetAtTime(decTo, t0 + A, Math.max(D, (I.envelope.decay_sec || 0.4)) / 2.2 * (P.decayStretch || 1));
          this.naturalEnd = t0 + A + Math.max(D, 0.3) * 5 * (P.decayStretch || 1); this.lastBodyLvl = decTo;
        }
      }
    }

    // パラメータ変更が来たとき(構造を変えずに反映できるもの)
    refreshLive(keys) {
      const k = (n) => keys === "*" || (keys && keys.indexOf(n) >= 0);
      if (k("*") || k("fineCents") || k("transposeSemis") || k("inharmMul") || k("glideMs") || k("brassLayerDetuneCents")) this.applyFrequencies(false);
      if (k("*") || k("brightness") || k("harmRolloff") || k("oddEvenBal") || k("harmLimit") || k("harmGains") || k("brassLayerMix") || k("trumpetWaveMix")) this.applyAmpGains(false);
      if (k("*") || k("trumpetWaveMix")) this.applyWaveMix(false);
      if (k("*") || k("sustainSampleMix")) this.applySustainMix(false);
      if (k("*") || k("noiseHpHz") || k("noiseLpHz")) this.applyNoiseFilters(false);
    }

    noteOff(when) {
      if (this.releasing || this.dead) return;
      const S = this.S, P = S.params, ctx = S.ctx, t = (when != null ? when : ctx.currentTime);
      this.releasing = true; this.releaseStart = t;
      const relSec = Math.max(0.02, (P.releaseMs || 120) / 1000);
      holdParam(this.amp.gain, t);
      this.amp.gain.setTargetAtTime(0.0001, t, relSec / 3.5);
      this.amp.gain.setValueAtTime(0, t + relSec * 1.4);
      holdParam(this.noiseGain.gain, t);
      this.noiseGain.gain.setTargetAtTime(0.0001, t, relSec / 4);
      if (this.attackGain) {
        holdParam(this.attackGain.gain, t);
        this.attackGain.gain.setTargetAtTime(0.0001, t, 0.018);
      }
      if (this.waveGain) {
        holdParam(this.waveGain.gain, t);
        this.waveGain.gain.setTargetAtTime(0.0001, t, relSec / 4);
      }
      if (this.sustainGain) {
        holdParam(this.sustainGain.gain, t);
        this.sustainGain.gain.setTargetAtTime(0.0001, t, relSec / 4);
      }
      if (this.drumGain) {
        holdParam(this.drumGain.gain, t);
        this.drumGain.gain.setTargetAtTime(0.0001, t, relSec / 5);
      }
      this.releaseEnd = t + relSec * 1.5;
      // 倍音/ノイズの時間形状は離した時点で固定(setValueAtTime で十分。既に hold 済み)
    }
    // 表示用: いま生きてるか(掃除用)
    isFinished(now) {
      if (this.dead) return true;
      if (this.releasing) return now >= (this.releaseEnd || 0);
      if (this.naturalEnd !== Infinity && now >= (this.naturalEnd || Infinity)) return true;
      return false;
    }
    kill() {
      if (this.dead) return; this.dead = true;
      try {
        for (const h of this.harm) {
          try { h.osc.stop(); } catch (_) {}
          try { if (h.layerOsc) h.layerOsc.stop(); } catch (_) {}
          h.osc.disconnect(); h.envGain.disconnect(); h.ampGain.disconnect();
          if (h.layerOsc) h.layerOsc.disconnect();
          if (h.layerEnvGain) h.layerEnvGain.disconnect();
          if (h.layerAmpGain) h.layerAmpGain.disconnect();
        }
      } catch (_) {}
      try { this.noiseSrc.stop(); } catch (_) {}
      try { if (this.waveSrc) this.waveSrc.stop(); } catch (_) {}
      try { if (this.waveSrc) this.waveSrc.disconnect(); if (this.waveGain) this.waveGain.disconnect(); } catch (_) {}
      try { if (this.attackSrc) this.attackSrc.stop(); } catch (_) {}
      try { if (this.attackSrc) this.attackSrc.disconnect(); if (this.attackGain) this.attackGain.disconnect(); } catch (_) {}
      try { if (this.sustainSrc) this.sustainSrc.stop(); } catch (_) {}
      try { if (this.sustainSrc) this.sustainSrc.disconnect(); if (this.sustainTone) this.sustainTone.disconnect(); if (this.sustainGain) this.sustainGain.disconnect(); } catch (_) {}
      try { if (this.drumSrc) this.drumSrc.stop(); } catch (_) {}
      try { if (this.drumSrc) this.drumSrc.disconnect(); if (this.drumGain) this.drumGain.disconnect(); } catch (_) {}
      try { this.noiseSrc.disconnect(); this.noiseHP.disconnect(); this.noiseLP.disconnect(); this.noiseGain.disconnect(); this.amp.disconnect(); this.vibGate.disconnect(); } catch (_) {}
    }
  }

  // ============================================================
  //  LiveSynth — エフェクト一式 + ボイス管理
  // ============================================================
  SL.LiveSynth = class LiveSynth {
    constructor(ctx) {
      this.ctx = ctx || null;        // 与えられたら(オフライン書き出し用)それを使う
      this.offline = !!ctx;
      this.instrument = null;
      this.params = {};
      this.voices = [];
      this.held = new Map();          // midi → Voice
      this.drone = false; this.droneMidi = 60;
      this.origBuffer = null; this.origNode = null; this.origGain = null;
      this._irBuildTimer = null;
      this._graphBuilt = false;
      if (ctx) this._buildGraph();
    }

    async ensureCtx() {
      const fresh = !this.ctx;
      if (!this.ctx) { this.ctx = new (window.AudioContext || window.webkitAudioContext)(); this._buildGraph(); }
      if (this.ctx.state === "suspended") { try { await this.ctx.resume(); } catch (_) {} }
      if (fresh && this.instrument) { this._initNoiseBuffer(); this.applyAll(); }
      return this.ctx;
    }

    // ── マスターのエフェクトグラフ ──
    _buildGraph() {
      if (this._graphBuilt) return; this._graphBuilt = true;
      const ctx = this.ctx;
      this.voiceMix = ctx.createGain(); this.voiceMix.gain.value = 1;
      this.preGain = ctx.createGain(); this.preGain.gain.value = 1;

      // ドライブ(常時経路。amount 0 でほぼ素通り)
      this.driveShaper = ctx.createWaveShaper(); this.driveShaper.curve = makeDriveCurve(0); this.driveShaper.oversample = "2x";
      this.driveMakeup = ctx.createGain(); this.driveMakeup.gain.value = 1;
      this.driveTone = ctx.createBiquadFilter(); this.driveTone.type = "lowpass"; this.driveTone.frequency.value = 16000; this.driveTone.Q.value = 0.4;

      // ボディ EQ
      this.eqLow = ctx.createBiquadFilter(); this.eqLow.type = "lowshelf"; this.eqLow.frequency.value = 160; this.eqLow.gain.value = 0;
      this.eqMid = ctx.createBiquadFilter(); this.eqMid.type = "peaking"; this.eqMid.frequency.value = 900; this.eqMid.Q.value = 1; this.eqMid.gain.value = 0;
      this.eqPres = ctx.createBiquadFilter(); this.eqPres.type = "peaking"; this.eqPres.frequency.value = 3800; this.eqPres.Q.value = 1.2; this.eqPres.gain.value = 0;
      this.eqHigh = ctx.createBiquadFilter(); this.eqHigh.type = "highshelf"; this.eqHigh.frequency.value = 8000; this.eqHigh.gain.value = 0;
      this.trumpetBody = ctx.createBiquadFilter(); this.trumpetBody.type = "peaking"; this.trumpetBody.frequency.value = 980; this.trumpetBody.Q.value = 1.1; this.trumpetBody.gain.value = 0;
      this.trumpetBell = ctx.createBiquadFilter(); this.trumpetBell.type = "peaking"; this.trumpetBell.frequency.value = 3200; this.trumpetBell.Q.value = 1.0; this.trumpetBell.gain.value = 0;
      this.trumpetAir = ctx.createBiquadFilter(); this.trumpetAir.type = "peaking"; this.trumpetAir.frequency.value = 7200; this.trumpetAir.Q.value = 0.85; this.trumpetAir.gain.value = 0;

      // トーン(マスター)フィルタ + ワウ LFO
      this.toneFilter = ctx.createBiquadFilter(); this.toneFilter.type = "lowpass"; this.toneFilter.frequency.value = 20000; this.toneFilter.Q.value = 0.0001;
      this.filterLFO = ctx.createOscillator(); this.filterLFO.type = "sine"; this.filterLFO.frequency.value = 1.5;
      this.filterLfoDepth = ctx.createGain(); this.filterLfoDepth.gain.value = 0;
      this.filterLFO.connect(this.filterLfoDepth); this.filterLfoDepth.connect(this.toneFilter.frequency); this.filterLFO.start();

      // トレモロ(マスター振幅 LFO)
      this.tremGain = ctx.createGain(); this.tremGain.gain.value = 1;
      this.tremoloLFO = ctx.createOscillator(); this.tremoloLFO.type = "sine"; this.tremoloLFO.frequency.value = 5;
      this.tremoloDepth = ctx.createGain(); this.tremoloDepth.gain.value = 0;
      this.tremoloLFO.connect(this.tremoloDepth); this.tremoloDepth.connect(this.tremGain.gain); this.tremoloLFO.start();

      // ビブラート LFO(ボイスごとの vibGate へ分配)
      this.vibratoLFO = ctx.createOscillator(); this.vibratoLFO.type = "sine"; this.vibratoLFO.frequency.value = 5.5;
      this.vibratoDepth = ctx.createGain(); this.vibratoDepth.gain.value = 0;   // cents 単位
      this.vibratoLFO.connect(this.vibratoDepth); this.vibratoLFO.start();

      // 直列: voiceMix → preGain → drive(shaper→makeup→tone) → eq → toneFilter → tremGain
      this.voiceMix.connect(this.preGain);
      this.preGain.connect(this.driveShaper); this.driveShaper.connect(this.driveMakeup); this.driveMakeup.connect(this.driveTone);
      this.driveTone.connect(this.eqLow); this.eqLow.connect(this.eqMid); this.eqMid.connect(this.eqPres); this.eqPres.connect(this.eqHigh);
      this.eqHigh.connect(this.trumpetBody); this.trumpetBody.connect(this.trumpetBell); this.trumpetBell.connect(this.trumpetAir); this.trumpetAir.connect(this.toneFilter);
      this.toneFilter.connect(this.tremGain);

      // 分岐: ドライ / コーラス(send) / リバーブ(send) → sumIn
      this.sumIn = ctx.createGain(); this.sumIn.gain.value = 1;
      this.dryGain = ctx.createGain(); this.dryGain.gain.value = 1;
      this.tremGain.connect(this.dryGain); this.dryGain.connect(this.sumIn);

      // コーラス: 3 ボイス(遅延 + LFO で遅延時間を揺らす + L/C/R パン) → chorusMix(send)
      this.chorusIn = ctx.createGain(); this.chorusIn.gain.value = 1;
      this.tremGain.connect(this.chorusIn);
      this.chorusMix = ctx.createGain(); this.chorusMix.gain.value = 0;
      this.chorusMix.connect(this.sumIn);
      this.chorusVoices = [];
      const baseDelays = [0.013, 0.019, 0.026];
      for (let i = 0; i < 3; i++) {
        const dn = ctx.createDelay(0.08); dn.delayTime.value = baseDelays[i];
        const lfo = ctx.createOscillator(); lfo.type = "sine"; lfo.frequency.value = 0.25 + i * 0.13;
        const ld = ctx.createGain(); ld.gain.value = 0.002;
        lfo.connect(ld); ld.connect(dn.delayTime); lfo.start();
        const pan = ctx.createStereoPanner ? ctx.createStereoPanner() : null;
        if (pan) pan.pan.value = [-1, 0, 1][i] * 0.8;
        this.chorusIn.connect(dn);
        if (pan) { dn.connect(pan); pan.connect(this.chorusMix); } else dn.connect(this.chorusMix);
        this.chorusVoices.push({ dn, lfo, ld, pan });
      }

      // リバーブ: preDelay → convolver → wet
      this.reverbPre = ctx.createDelay(0.2); this.reverbPre.delayTime.value = 0.0;
      this.convolver = ctx.createConvolver();
      this.reverbWet = ctx.createGain(); this.reverbWet.gain.value = 0;
      this.tremGain.connect(this.reverbPre); this.reverbPre.connect(this.convolver); this.convolver.connect(this.reverbWet); this.reverbWet.connect(this.sumIn);
      this._rebuildIR(2.2, 1.0, 0.35, 0.8);   // 初期 IR

      // マスター: sumIn → masterGain → limiter → (analyser) → destination
      this.masterGain = ctx.createGain(); this.masterGain.gain.value = 0.6;
      this.limiter = ctx.createDynamicsCompressor();
      this.limiter.threshold.value = -3; this.limiter.knee.value = 6; this.limiter.ratio.value = 16;
      this.limiter.attack.value = 0.003; this.limiter.release.value = 0.18;
      this.sumIn.connect(this.masterGain); this.masterGain.connect(this.limiter);
      if (!this.offline) {
        this.analyser = ctx.createAnalyser(); this.analyser.fftSize = 2048; this.analyser.smoothingTimeConstant = 0.78;
        this.limiter.connect(this.analyser); this.analyser.connect(ctx.destination);
        this.origGain = ctx.createGain(); this.origGain.gain.value = 1; this.origGain.connect(this.masterGain);
      } else {
        this.limiter.connect(ctx.destination);
      }
    }
    _rebuildIR(seconds, decay, damping, width) {
      try { this.convolver.buffer = makeImpulseResponse(this.ctx, clamp(seconds, 0.1, 6), clamp(decay, 0.4, 3), clamp(damping, 0, 0.985), clamp(width, 0, 1)); } catch (_) {}
    }

    // ── 既定パラメータ(instrument から導出) ──
    defaultParams(I) {
      const e = I.envelope || {}, mod = I.modulation || {}, vib = mod.vibrato || {}, trem = mod.tremolo || {};
      const profile = I.instrument_profile || "auto";
      const isTrumpet = profile === "trumpet";
      const isViolin = profile === "violin";
      const isDrum = profile === "drum";
      const drumGuess = I.features && I.features.drum_type_guess || "";
      const isCymbal = drumGuess === "crash" || drumGuess === "hihat" || drumGuess === "cymbal";
      const isPlainDrumSample = drumGuess === "kick" || drumGuess === "hihat";
      const harmNs = (I.harmonics || []).filter((h) => h.amp > 0).map((h) => h.n);
      const maxN = harmNs.length ? Math.max.apply(null, harmNs) : 16;
      // ノイズの色: band_levels の重心からおおよその低域/高域カットを決める
      let nlp = 12000, nhp = 40;
      try {
        const bl = I.noise && I.noise.band_levels || [], bh = I.noise && I.noise.bands_hz || [];
        if (bl.length && bh.length === bl.length + 1) {
          let num = 0, den = 0; for (let i = 0; i < bl.length; i++) { const fc = (bh[i] + bh[i + 1]) / 2; num += fc * bl[i]; den += bl[i]; }
          if (den > 0) nlp = clamp((num / den) * 2.4, 800, 18000);
          // 低域: 最初に有意な帯域
          for (let i = 0; i < bl.length; i++) { if (bl[i] > 0.12) { nhp = clamp(bh[i] || 20, 20, 1200); break; } }
        }
      } catch (_) {}
      return {
        // 演奏
        masterVol: 0.6, transposeSemis: 0, glideMs: 0, humanizeCents: 0,
        // ピッチ & ビブラート
        fineCents: 0,
        // 解析値は表示と「検出値に合わせる」用に残すが、初期再生では揺れを足さない。
        // f0/振幅の微小な解析ゆらぎを LFO として再適用すると、元音より不安定に聴こえるため。
        vibDepthCents: 0,
        vibRateHz: vib.detected ? clamp(vib.rate_hz || 5.5, 0.1, 14) : 5.5,
        vibShape: "sine", vibOnsetSec: 0,
        // 倍音
        brightness: isDrum ? (isPlainDrumSample ? 0 : isCymbal ? 0.1 : -0.18) : isTrumpet ? 0.24 : isViolin ? -0.03 : 0,
        harmRolloff: isDrum ? (isPlainDrumSample ? 0 : isCymbal ? 0.02 : 0.12) : isTrumpet ? -0.012 : isViolin ? 0.032 : 0,
        oddEvenBal: isViolin ? 0.02 : 0,
        inharmMul: isDrum ? 1.0 : isViolin ? 0.50 : 1,
        harmLimit: isDrum ? Math.min(maxN, isCymbal ? 18 : 10) : maxN,
        // 解析した倍音包絡には録音ノイズ由来の細かい上下が乗るため、初期状態では固定倍音で安定させる。
        harmFollowEnv: false, harmGains: {}, harmonicGainTrim: isDrum ? (isPlainDrumSample ? 0 : 0.12) : 1,
        // トレモロ
        tremDepth: 0,
        tremRateHz: trem.detected ? clamp(trem.rate_hz || 5, 0.1, 14) : 5, tremShape: "sine",
        // ノイズ / 息
        // 残差ノイズは白色ノイズ再合成なので、初期状態では混ぜない。必要なときだけスライダーで足す。
        noiseLevel: isDrum ? (isPlainDrumSample ? 0 : isCymbal ? 0.08 : 0.06) : isViolin ? 0.26 : 0,
        noiseHpHz: isDrum ? (drumGuess === "kick" ? 35 : isCymbal ? 900 : 120) : isViolin ? 560 : nhp,
        noiseLpHz: isDrum ? (drumGuess === "kick" ? 5200 : isCymbal ? 18000 : 14500) : isViolin ? 9800 : nlp,
        attackNoise: isDrum ? 0 : isViolin ? 0.62 : 0,
        breathAmount: 0,
        noiseMode: isDrum ? "recorded" : "recorded",
        // トランペット/ドラム指定時は、合成だけでは抜けやすい原音アタックを短く重ねる。
        attackSampleMix: I.attack_sample ? (isDrum ? 0 : isTrumpet ? 0.75 : isViolin ? 0.52 : 0) : 0,
        // 解析した原音1周期波形を主成分として混ぜ、サイン波っぽさを減らす。
        trumpetWaveMix: isTrumpet && I.waveform && I.waveform.one_cycle ? 0.28 : 0,
        // トランペットの定常部にあるバズ/管鳴りを薄いループとして補う。
        sustainSampleMix: I.sustain_sample && (isTrumpet || isViolin) ? (isViolin ? 0.40 : 0.08) : 0,
        // トランペットの唇のバズ/管の反射に近い、わずかにずれた倍音レイヤー。
        brassLayerMix: isTrumpet ? 0.22 : 0,
        brassLayerDetuneCents: isTrumpet ? 5.5 : 0,
        // ドラム指定時は原音1打を主音として使う。これが各ドラム音の再現品質の土台。
        drumSampleMix: isDrum && I.drum_sample ? 1.0 : 0,
        drumPitchFollow: false,
        // エンベロープ
        // 録音RMSの微細な揺れではなく、まず ADSR で安定した包絡から始める。
        envMode: isDrum ? "recorded" : "adsr",
        attackMs: isDrum ? Math.max(1, Math.min(12, Math.round((e.attack_sec || 0.005) * 1000))) : isViolin ? Math.max(76, Math.round((e.attack_sec || 0.076) * 1000)) : Math.round((e.attack_sec || 0.01) * 1000),
        decayMs: isDrum ? (isCymbal ? 900 : drumGuess === "kick" ? 180 : 320) : isViolin ? Math.max(250, Math.round((e.decay_sec || 0.25) * 1000)) : Math.round((e.decay_sec || 0.1) * 1000),
        sustainLvl: isDrum ? 0.02 : isViolin ? clamp(Math.max(e.sustain_level == null ? 0.76 : e.sustain_level, 0.76), 0, 1) : clamp(e.sustain_level == null ? 0.7 : e.sustain_level, 0, 1),
        releaseMs: isDrum ? (drumGuess === "crash" ? 1500 : drumGuess === "hihat" ? 500 : drumGuess === "kick" ? 120 : 260) : isViolin ? Math.max(760, Math.round((e.release_sec || 0.76) * 1000)) : Math.round((e.release_sec || 0.12) * 1000),
        attackCurve: isDrum ? "exp" : "lin", decayStretch: 1,
        // 空間 / 響き
        reverbMix: isViolin ? 0.16 : 0, reverbSizeSec: isViolin ? 2.4 : 2.2, reverbDamping: isViolin ? 0.42 : 0.35, reverbPreMs: 0, reverbWidth: 0.85,
        // エフェクト
        driveAmount: isDrum ? (isPlainDrumSample ? 0 : 0.035) : isTrumpet ? 0.035 : isViolin ? 0.02 : 0,
        driveToneHz: isTrumpet ? 18000 : isViolin ? 13500 : 16000,
        chorusMix: isViolin ? 0.18 : 0, chorusRateHz: isViolin ? 0.2 : 0.25, chorusDepth: isViolin ? 0.54 : 0.4, chorusWidth: isViolin ? 0.78 : 0.8,
        filterMode: "off", filterCutoffHz: 6000, filterQ: 1, filterLfoRateHz: 1.5, filterLfoDepth: 0,
        trumpetResonance: isTrumpet ? 0.62 : 0,
        // ボディ EQ
        eqLowGain: isDrum ? (isPlainDrumSample ? 0 : isCymbal ? -4.0 : 0.5) : isTrumpet ? -2.0 : isViolin ? 0.7 : 0,
        eqMidFreq: isDrum ? (drumGuess === "kick" ? 180 : isCymbal ? 4200 : 950) : isTrumpet ? 780 : isViolin ? 560 : 900,
        eqMidGain: isDrum ? (isPlainDrumSample ? 0 : isCymbal ? 0.6 : 1.8) : isTrumpet ? -1.2 : isViolin ? 2.4 : 0,
        eqMidQ: isDrum ? 1.1 : isTrumpet ? 1.3 : 1,
        eqPresGain: isDrum ? (isPlainDrumSample ? 0 : 2.0) : isTrumpet ? 3.4 : isViolin ? 3.0 : 0,
        eqHighGain: isDrum ? (isPlainDrumSample ? 0 : isCymbal ? 2.0 : 1.2) : isTrumpet ? 2.4 : isViolin ? 0.45 : 0,
      };
    }

    load(I) {
      this.instrument = I;
      this._attackBuffer = null;
      this._attackBufferKey = "";
      this._waveCycleBuffer = null;
      this._waveCycleBufferKey = "";
      this._sustainBuffer = null;
      this._sustainBufferKey = "";
      this._drumBuffer = null;
      this._drumBufferKey = "";
      this._maxHarmN = (I.harmonics || []).filter((h) => h.amp > 0).reduce((m, h) => Math.max(m, h.n), 1);
      this.params = this.defaultParams(I);
      // ノイズ用の白色ノイズ(ループ)バッファ
      this._initNoiseBuffer();
      this.panic();
      if (this.ctx) this.applyAll();
    }
    _initNoiseBuffer() {
      const sr = (this.ctx ? this.ctx.sampleRate : 44100), len = Math.floor(sr * 1.0);
      // ctx が無いと createBuffer できないので、ある時だけ作る(無ければ ensureCtx 後に)
      if (!this.ctx) return;
      const b = this.ctx.createBuffer(1, len, sr), d = b.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      this.noiseBuffer = b;
    }
    _getAttackBuffer() {
      if (!this.ctx || !this.instrument || !this.instrument.attack_sample) return null;
      const a = this.instrument.attack_sample;
      const vals = a.values || [];
      if (!vals.length) return null;
      const sr = a.sample_rate || this.ctx.sampleRate;
      const key = vals.length + ":" + sr;
      if (this._attackBuffer && this._attackBufferKey === key) return this._attackBuffer;
      const b = this.ctx.createBuffer(1, vals.length, sr);
      const d = b.getChannelData(0);
      for (let i = 0; i < vals.length; i++) d[i] = vals[i] || 0;
      this._attackBuffer = b;
      this._attackBufferKey = key;
      return b;
    }
    _getWaveCycleBuffer() {
      if (!this.ctx || !this.instrument || !this.instrument.waveform || this.instrument.instrument_profile !== "trumpet") return null;
      const vals = this.instrument.waveform.one_cycle || [];
      const f0 = this.instrument.fundamental_hz || 440;
      if (vals.length < 8 || !(f0 > 0)) return null;
      const sr = clamp(Math.round(f0 * vals.length), 8000, 192000);
      const key = vals.length + ":" + sr + ":" + f0;
      if (this._waveCycleBuffer && this._waveCycleBufferKey === key) return this._waveCycleBuffer;
      const clean = this._cleanWaveCycle(vals);
      const b = this.ctx.createBuffer(1, clean.length, sr);
      const d = b.getChannelData(0);
      for (let i = 0; i < clean.length; i++) d[i] = clean[i] || 0;
      this._waveCycleBuffer = b;
      this._waveCycleBufferKey = key;
      return b;
    }
    _cleanWaveCycle(vals) {
      const N = vals.length;
      const mean = vals.reduce((s, v) => s + (v || 0), 0) / N;
      const maxH = Math.min(22, Math.floor(N / 2) - 1);
      const out = new Float32Array(N);
      for (let k = 1; k <= maxH; k++) {
        let re = 0, im = 0;
        for (let n = 0; n < N; n++) {
          const phase = 2 * Math.PI * k * n / N;
          const v = (vals[n] || 0) - mean;
          re += v * Math.cos(phase);
          im += v * Math.sin(phase);
        }
        re *= 2 / N; im *= 2 / N;
        const keep = Math.exp(-Math.max(0, k - 14) * 0.18);
        for (let n = 0; n < N; n++) {
          const phase = 2 * Math.PI * k * n / N;
          out[n] += keep * (re * Math.cos(phase) + im * Math.sin(phase));
        }
      }
      let peak = 0;
      for (let n = 0; n < N; n++) peak = Math.max(peak, Math.abs(out[n]));
      if (peak > 1e-9) for (let n = 0; n < N; n++) out[n] /= peak;
      return out;
    }
    _getSustainBuffer() {
      if (!this.ctx || !this.instrument) return null;
      const a = this.instrument.sustain_sample || {};
      let vals = a.values || [];
      let sr = a.sample_rate || this.ctx.sampleRate;
      this._sustainBufferIsFallback = false;
      if (!vals.length && (this.instrument.instrument_profile === "trumpet" || this.instrument.instrument_profile === "violin") && this.instrument.waveform && this.instrument.waveform.one_cycle) {
        const cyc = this.instrument.waveform.one_cycle || [];
        const repeats = Math.max(8, Math.ceil(0.18 * (this.instrument.fundamental_hz || 440)));
        vals = [];
        for (let r = 0; r < repeats; r++) vals.push.apply(vals, cyc);
        sr = Math.max(8000, Math.round((this.instrument.fundamental_hz || 440) * cyc.length));
        this._sustainBufferIsFallback = true;
      }
      if (!vals.length) return null;
      const key = vals.length + ":" + sr + ":" + (this.instrument.sustain_sample ? "recorded" : "cycle");
      if (this._sustainBuffer && this._sustainBufferKey === key) return this._sustainBuffer;
      const b = this.ctx.createBuffer(1, vals.length, sr);
      const d = b.getChannelData(0);
      for (let i = 0; i < vals.length; i++) d[i] = vals[i] || 0;
      this._sustainBuffer = b;
      this._sustainBufferKey = key;
      return b;
    }
    _getDrumBuffer() {
      if (!this.ctx || !this.instrument || !this.instrument.drum_sample) return null;
      const a = this.instrument.drum_sample;
      const vals = a.values || [];
      if (!vals.length) return null;
      const sr = a.sample_rate || this.ctx.sampleRate;
      const key = vals.length + ":" + sr;
      if (this._drumBuffer && this._drumBufferKey === key) return this._drumBuffer;
      const b = this.ctx.createBuffer(1, vals.length, sr);
      const d = b.getChannelData(0);
      for (let i = 0; i < vals.length; i++) d[i] = vals[i] || 0;
      this._drumBuffer = b;
      this._drumBufferKey = key;
      return b;
    }

    // ── パラメータ反映 ──
    set(key, value) {
      this.params[key] = value;
      this._apply([key]);
      // 「録音エンベロープ ↔ ADSR」など、鳴っている音に構造的に効くものは drone を貼り直し
      if (this.drone && (key === "envMode" || key === "noiseMode" || key === "harmFollowEnv" || key === "decayStretch" || key === "attackCurve" || key === "attackSampleMix" || key === "sustainSampleMix" || key === "drumSampleMix" || key === "drumPitchFollow")) {
        this._retriggerDrone();
      }
    }
    setHarmGain(n, mul) {
      if (!this.params.harmGains) this.params.harmGains = {};
      this.params.harmGains[n] = mul;
      for (const v of this.voices) v.refreshLive(["harmGains"]);
    }
    applyAll() { this._apply("*"); }
    _apply(keys) {
      if (!this.ctx) return;
      const P = this.params, ctx = this.ctx, t = ctx.currentTime, has = (k) => keys === "*" || keys.indexOf(k) >= 0;
      const ramp = (param, v, tc) => param.setTargetAtTime(v, t, tc || 0.02);
      if (has("masterVol")) ramp(this.masterGain.gain, clamp(P.masterVol, 0, 1.2), 0.03);
      // ビブラート
      if (has("vibDepthCents")) ramp(this.vibratoDepth.gain, clamp(P.vibDepthCents, 0, 300), 0.05);
      if (has("vibRateHz")) ramp(this.vibratoLFO.frequency, clamp(P.vibRateHz, 0.05, 14), 0.05);
      if (has("vibShape")) this.vibratoLFO.type = P.vibShape;
      // トレモロ: tremGain.gain.value = 1 - depth/2 ; 揺れ幅 = depth/2 → (1-depth)..1
      if (has("tremDepth")) { const d = clamp(P.tremDepth, 0, 0.95); ramp(this.tremGain.gain, 1 - d / 2, 0.05); ramp(this.tremoloDepth.gain, d / 2, 0.05); }
      if (has("tremRateHz")) ramp(this.tremoloLFO.frequency, clamp(P.tremRateHz, 0.05, 14), 0.05);
      if (has("tremShape")) this.tremoloLFO.type = P.tremShape;
      // ドライブ
      if (has("driveAmount")) { const a = clamp(P.driveAmount, 0, 1); this.driveShaper.curve = makeDriveCurve(a); ramp(this.driveMakeup.gain, 1 / (1 + a * 1.4), 0.03); }
      if (has("driveToneHz")) ramp(this.driveTone.frequency, clamp(P.driveToneHz, 400, 19000), 0.02);
      // ボディ EQ
      if (has("eqLowGain")) ramp(this.eqLow.gain, clamp(P.eqLowGain, -18, 18), 0.02);
      if (has("eqMidGain")) ramp(this.eqMid.gain, clamp(P.eqMidGain, -18, 18), 0.02);
      if (has("eqMidFreq")) ramp(this.eqMid.frequency, clamp(P.eqMidFreq, 120, 7000), 0.02);
      if (has("eqMidQ")) ramp(this.eqMid.Q, clamp(P.eqMidQ, 0.2, 8), 0.02);
      if (has("eqPresGain")) ramp(this.eqPres.gain, clamp(P.eqPresGain, -18, 18), 0.02);
      if (has("eqHighGain")) ramp(this.eqHigh.gain, clamp(P.eqHighGain, -18, 18), 0.02);
      if (has("trumpetResonance")) {
        const r = clamp(P.trumpetResonance || 0, 0, 1);
        ramp(this.trumpetBody.gain, r * 1.7, 0.03);
        ramp(this.trumpetBell.gain, r * 3.0, 0.03);
        ramp(this.trumpetAir.gain, r * 0.75, 0.03);
      }
      // トーンフィルタ + ワウ
      if (has("filterMode") || has("filterCutoffHz") || has("filterQ")) {
        if (P.filterMode === "off") { this.toneFilter.type = "lowpass"; this.toneFilter.frequency.setTargetAtTime(20000, t, 0.02); this.toneFilter.Q.setTargetAtTime(0.0001, t, 0.02); }
        else { this.toneFilter.type = (P.filterMode === "hp" ? "highpass" : P.filterMode === "bp" ? "bandpass" : "lowpass"); ramp(this.toneFilter.frequency, clamp(P.filterCutoffHz, 30, 20000), 0.02); ramp(this.toneFilter.Q, clamp(P.filterQ, 0.1, 20), 0.02); }
      }
      if (has("filterLfoRateHz")) ramp(this.filterLFO.frequency, clamp(P.filterLfoRateHz, 0.02, 12), 0.05);
      if (has("filterLfoDepth") || has("filterCutoffHz") || has("filterMode")) {
        const depthHz = P.filterMode === "off" ? 0 : clamp(P.filterLfoDepth, 0, 1) * Math.min(P.filterCutoffHz * 0.9, 6000);
        ramp(this.filterLfoDepth.gain, depthHz, 0.05);
      }
      // コーラス
      if (has("chorusMix")) ramp(this.chorusMix.gain, clamp(P.chorusMix, 0, 1), 0.04);
      if (has("chorusRateHz") || has("chorusDepth") || has("chorusWidth")) {
        for (let i = 0; i < this.chorusVoices.length; i++) {
          const cv = this.chorusVoices[i];
          ramp(cv.lfo.frequency, clamp(P.chorusRateHz, 0.02, 4) * (0.8 + i * 0.2), 0.05);
          ramp(cv.ld.gain, clamp(P.chorusDepth, 0, 1) * 0.005, 0.05);
          if (cv.pan) ramp(cv.pan.pan, [-1, 0, 1][i] * clamp(P.chorusWidth, 0, 1), 0.05);
        }
      }
      // リバーブ
      if (has("reverbMix")) ramp(this.reverbWet.gain, clamp(P.reverbMix, 0, 1) * 1.4, 0.05);
      if (has("reverbPreMs")) ramp(this.reverbPre.delayTime, clamp(P.reverbPreMs, 0, 180) / 1000, 0.03);
      if (has("reverbSizeSec") || has("reverbDamping") || has("reverbWidth")) {
        clearTimeout(this._irBuildTimer);
        this._irBuildTimer = setTimeout(() => this._rebuildIR(P.reverbSizeSec, 1.0, P.reverbDamping, P.reverbWidth), 90);
      }
      // 倍音 limit の上限値クランプ
      if (has("harmLimit")) this.params.harmLimit = clamp(Math.round(P.harmLimit), 1, this._maxHarmN);
      // 鳴っているボイスへ即反映できるもの
      const liveKeys = (keys === "*") ? "*" : keys.filter((k) => ["fineCents", "transposeSemis", "inharmMul", "glideMs", "brightness", "harmRolloff", "oddEvenBal", "harmLimit", "harmGains", "brassLayerMix", "brassLayerDetuneCents", "noiseHpHz", "noiseLpHz"].indexOf(k) >= 0);
      if (liveKeys === "*" || (liveKeys && liveKeys.length)) for (const v of this.voices) v.refreshLive(liveKeys);
    }

    resetAll() { const I = this.instrument; this.params = this.defaultParams(I); this.applyAll(); if (this.drone) this._retriggerDrone(); }
    resetSection(keys) { const d = this.defaultParams(this.instrument); for (const k of keys) this.params[k] = d[k]; this._apply(keys); if (this.drone && keys.indexOf("envMode") >= 0) this._retriggerDrone(); }

    // ── ノート ──
    noteOn(midi, vel) {
      if (!this.instrument || !this.ctx) return null;
      if (this.held.has(midi)) return this.held.get(midi);
      if (this.voices.length > 14) { const old = this.voices.find((v) => !this.held.has(v.midi)) || this.voices[0]; if (old) old.noteOff(); }
      const v = new Voice(this, midi, vel);
      this.voices.push(v); this.held.set(midi, v);
      this._gc();
      return v;
    }
    noteOff(midi) { const v = this.held.get(midi); if (v) { v.noteOff(); this.held.delete(midi); } }
    releaseAllHeld() { for (const m of Array.from(this.held.keys())) this.noteOff(m); }
    panic() { for (const v of this.voices) v.kill(); this.voices.length = 0; this.held.clear(); }
    _gc() {
      const now = this.ctx.currentTime;
      for (let i = this.voices.length - 1; i >= 0; i--) { const v = this.voices[i]; if (v.isFinished(now)) { v.kill(); this.voices.splice(i, 1); for (const [m, vv] of this.held) if (vv === v) this.held.delete(m); } }
      if (!this.offline) { clearTimeout(this._gcTimer); if (this.voices.length) this._gcTimer = setTimeout(() => this._gc(), 300); }
    }

    // ── ドローン(鳴らしっぱなし) ──
    setDrone(on, midi) {
      this.drone = !!on; if (midi != null) this.droneMidi = midi;
      if (this.drone) { this.releaseAllHeld(); this._droneVoice = this.noteOn(this.droneMidi, 0.85); }
      else if (this._droneVoice) { this._droneVoice.noteOff(); this._droneVoice = null; }
    }
    setDroneNote(midi) { this.droneMidi = midi; if (this.drone) this._retriggerDrone(); }
    _retriggerDrone() {
      if (!this.drone || !this.ctx) return;
      const old = this._droneVoice;
      if (old) { old.noteOff(); for (const [m, v] of this.held) if (v === old) this.held.delete(m); }
      this.held.delete(this.droneMidi);
      const v = new Voice(this, this.droneMidi, 0.85);
      this.voices.push(v); this.held.set(this.droneMidi, v); this._droneVoice = v;
      this._gc();
    }

    // ── 原音 A/B ──
    setOriginalBuffer(buf) { this.origBuffer = buf; }
    playOriginal(loop) {
      if (!this.ctx || !this.origBuffer) return;
      this.stopOriginal();
      const n = this.ctx.createBufferSource(); n.buffer = this.origBuffer; n.loop = !!loop;
      n.connect(this.origGain); n.start();
      this.origNode = n; n.onended = () => { if (this.origNode === n) this.origNode = null; };
    }
    stopOriginal() { if (this.origNode) { try { this.origNode.stop(); } catch (_) {} this.origNode = null; } }

    // ── 調整後の instrument 定義を書き出す ──
    exportInstrument() {
      const I = this.instrument, P = this.params;
      const out = JSON.parse(JSON.stringify(I));
      // 倍音: brightness / rolloff / odd-even / 手動ゲイン / 倍音数制限 / 非調和性ミックス を畳み込む
      const live = (out.harmonics || []).filter((h) => h.amp > 0);
      const scal = live.map((h) => {
        let g = h.amp; const n = h.n;
        g *= Math.pow(n, P.brightness || 0); g *= Math.exp(-(P.harmRolloff || 0) * (n - 1));
        if (n > 1) g *= (n % 2 === 1) ? clamp(1 + (P.oddEvenBal || 0), 0, 2) : clamp(1 - (P.oddEvenBal || 0), 0, 2);
        g *= clamp(P.harmGains && P.harmGains[n] != null ? P.harmGains[n] : 1, 0, 4);
        if (n > (P.harmLimit || 999)) g = 0;
        return Math.max(0, g);
      });
      const mx = Math.max.apply(null, scal.concat([1e-9]));
      for (let i = 0; i < live.length; i++) {
        const h = live[i], a = scal[i] / mx;
        h.amp = +a.toFixed(5); h.amp_db = +(20 * Math.log10(a + 1e-9)).toFixed(2);
        const pure = h.n; h.ratio = +(pure + (h.ratio - pure) * (P.inharmMul == null ? 1 : P.inharmMul)).toFixed(5);
      }
      out.harmonics = live; // amp=0 だった席は落とす
      // 振幅エンベロープ ADSR の上書き(値配列はそのまま。ADSR 4 値は編集後の値に)
      out.envelope.attack_sec = +(P.attackMs / 1000).toFixed(4);
      out.envelope.decay_sec = +(P.decayMs / 1000).toFixed(4);
      out.envelope.sustain_level = +clamp(P.sustainLvl, 0, 1).toFixed(4);
      out.envelope.release_sec = +(P.releaseMs / 1000).toFixed(4);
      // ノイズ: level に倍率を畳む(色は band_levels をそのまま残しつつ、調整値もメモ)
      if (out.noise) out.noise.level = +clamp((out.noise.level || 0) * (P.noiseLevel == null ? 1 : P.noiseLevel), 0, 1).toFixed(4);
      // モジュレーション(ビブラート / トレモロ): 現在のスライダー値を書き戻す
      out.modulation = {
        vibrato: { rate_hz: +P.vibRateHz.toFixed(2), depth_cents: +P.vibDepthCents.toFixed(1), depth: +(P.vibDepthCents / 100).toFixed(3), onset_sec: +P.vibOnsetSec.toFixed(3), shape: P.vibShape, regularity: (I.modulation && I.modulation.vibrato && I.modulation.vibrato.regularity) || 0, detected: P.vibDepthCents > 0.5 },
        tremolo: { rate_hz: +P.tremRateHz.toFixed(2), depth: +P.tremDepth.toFixed(3), depth_cents: 0.0, onset_sec: 0.0, shape: P.tremShape, regularity: (I.modulation && I.modulation.tremolo && I.modulation.tremolo.regularity) || 0, detected: P.tremDepth > 0.005 },
      };
      // ブラウザスタジオで足したエフェクト(Processing 現行版は無視する付加情報)
      out.fx = {
        note: "sound_lab スタジオで設定。再合成の本体合成には不要 / Processing 現行版は未対応",
        transpose_semis: P.transposeSemis, fine_cents: P.fineCents, glide_ms: P.glideMs, humanize_cents: P.humanizeCents,
        modulation: { vibrato_depth_cents: P.vibDepthCents, vibrato_rate_hz: P.vibRateHz, vibrato_onset_sec: P.vibOnsetSec, vibrato_shape: P.vibShape, tremolo_depth: P.tremDepth, tremolo_rate_hz: P.tremRateHz, tremolo_shape: P.tremShape },
        env_mode: P.envMode, harm_follow_env: P.harmFollowEnv, decay_stretch: P.decayStretch, attack_curve: P.attackCurve,
        attack_sample_mix: P.attackSampleMix, trumpet_wave_mix: P.trumpetWaveMix, sustain_sample_mix: P.sustainSampleMix, drum_sample_mix: P.drumSampleMix, drum_pitch_follow: P.drumPitchFollow,
        brass_layer: { mix: P.brassLayerMix, detune_cents: P.brassLayerDetuneCents },
        trumpet_resonance: P.trumpetResonance,
        noise_mode: P.noiseMode, noise_hp_hz: P.noiseHpHz, noise_lp_hz: P.noiseLpHz, attack_noise: P.attackNoise, breath_amount: P.breathAmount,
        reverb: { mix: P.reverbMix, size_sec: P.reverbSizeSec, damping: P.reverbDamping, pre_ms: P.reverbPreMs, width: P.reverbWidth },
        drive: { amount: P.driveAmount, tone_hz: P.driveToneHz },
        chorus: { mix: P.chorusMix, rate_hz: P.chorusRateHz, depth: P.chorusDepth, width: P.chorusWidth },
        filter: { mode: P.filterMode, cutoff_hz: P.filterCutoffHz, q: P.filterQ, lfo_rate_hz: P.filterLfoRateHz, lfo_depth: P.filterLfoDepth },
        body_eq: { low_gain: P.eqLowGain, mid_freq: P.eqMidFreq, mid_gain: P.eqMidGain, mid_q: P.eqMidQ, presence_gain: P.eqPresGain, high_gain: P.eqHighGain },
      };
      out.created_at = new Date().toISOString().replace(/\.\d+Z$/, "Z");
      out.name = (I.name || "instrument") + " (調整)";
      out.edited_by = "sound_lab studio";
      return out;
    }

    // ── 現在の音を WAV(Blob)に書き出す(オフラインレンダリング) ──
    async renderWav(midi, durSec) {
      durSec = clamp(durSec || 2.0, 0.2, 12);
      const sr = (this.ctx ? this.ctx.sampleRate : 44100);
      const tail = Math.max(0.2, this.params.reverbMix > 0.01 ? this.params.reverbSizeSec * 1.1 : 0.3) + (this.params.releaseMs / 1000) * 1.6;
      const total = durSec + tail;
      const off = new OfflineAudioContext(2, Math.ceil(sr * total), sr);
      const tmp = new SL.LiveSynth(off);
      tmp.instrument = this.instrument; tmp._maxHarmN = this._maxHarmN;
      tmp.params = JSON.parse(JSON.stringify(this.params));
      tmp._initNoiseBuffer();
      tmp.applyAll();
      tmp._rebuildIR(tmp.params.reverbSizeSec, 1.0, tmp.params.reverbDamping, tmp.params.reverbWidth); // setTimeout 経由を待たず即反映
      const v = new Voice(tmp, midi, 0.9);
      tmp.voices.push(v);
      // 持続音は durSec の 80% で離す、減衰音は鳴らし切る
      const holdT = tmp.instrument.sustaining ? durSec * 0.82 : durSec * 0.98;
      v.noteOff(holdT);
      const buf = await off.startRendering();
      return SL.encodeWav(buf);
    }
  };

  // ── AudioBuffer → 16bit WAV(Blob) ──
  SL.encodeWav = function (audioBuffer) {
    const ch = audioBuffer.numberOfChannels, len = audioBuffer.length, sr = audioBuffer.sampleRate;
    const bytesPerSample = 2, blockAlign = ch * bytesPerSample;
    const buf = new ArrayBuffer(44 + len * blockAlign), dv = new DataView(buf);
    const wstr = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
    wstr(0, "RIFF"); dv.setUint32(4, 36 + len * blockAlign, true); wstr(8, "WAVE");
    wstr(12, "fmt "); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, ch, true);
    dv.setUint32(24, sr, true); dv.setUint32(28, sr * blockAlign, true); dv.setUint16(32, blockAlign, true); dv.setUint16(34, 16, true);
    wstr(36, "data"); dv.setUint32(40, len * blockAlign, true);
    const chans = []; for (let c = 0; c < ch; c++) chans.push(audioBuffer.getChannelData(c));
    let off = 44;
    for (let i = 0; i < len; i++) for (let c = 0; c < ch; c++) { let s = Math.max(-1, Math.min(1, chans[c][i])); dv.setInt16(off, s < 0 ? s * 0x8000 : s * 0x7fff, true); off += 2; }
    return new Blob([buf], { type: "audio/wav" });
  };
})();
