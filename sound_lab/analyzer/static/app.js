/* ==========================================================================
   app.js — sound_lab アナライザ/スタジオ の UI

   ・音源をアップロード → /analyze で解析 → 波形/スペクトル/エンベロープ/倍音/ピッチ揺れ を可視化
   ・解析結果を SL.LiveSynth に読み込み、鳴らしながら「ビブラート/倍音/ノイズ(息)/響き/各種FX」を編集
   ・調整後の instrument 定義(JSON)や、その音そのもの(WAV)を書き出し

   合成エンジンは engine.js (SL.LiveSynth)。フォーマットは ../library_format.md
   ========================================================================== */
"use strict";
(function () {
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const el = (tag, attrs, kids) => {
    const e = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      if (k === "class") e.className = attrs[k];
      else if (k === "html") e.innerHTML = attrs[k];
      else if (k === "text") e.textContent = attrs[k];
      else if (k.slice(0, 2) === "on") e.addEventListener(k.slice(2), attrs[k]);
      else e.setAttribute(k, attrs[k]);
    }
    if (kids) (Array.isArray(kids) ? kids : [kids]).forEach((c) => c != null && e.appendChild(typeof c === "string" ? document.createTextNode(c) : c));
    return e;
  };
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  // ── 状態 ─────────────────────────────────────────────────
  const synth = new SL.LiveSynth();
  let pickedFile = null;        // 解析にかけた音源ファイル(原音 A/B 用に保持)
  let instrument = null, preview = null;
  let ctlEls = {};              // key → input 要素(値表示の更新用に保持)
  let valEls = {};
  let kbBase = 48;              // 鍵盤左端の MIDI
  let curNote = 60;             // 現在選択中(ドローン/書き出し対象)の音
  let latch = false;            // クリックで保持モード
  const heldByEvent = new Set();// マウス/タッチ/PCキーで押している MIDI(離す用)
  let rafId = 0;

  // 解析プレビューが無いとき(JSON 直接読込)のためのダミー
  const DEMO_INSTRUMENT = {
    format: "sound_lab.instrument/1", name: "demo (内蔵デモ)", source_file: "(内蔵デモ音色)",
    created_at: "2026-01-01T00:00:00Z", sample_rate: 44100, fundamental_hz: 261.626, midi_note: 60,
    note_name: "C4", duration_sec: 2.0, sustaining: true,
    envelope: { rate_hz: 200, values: (function () { const v = []; for (let i = 0; i < 400; i++) { const t = i / 200; v.push(t < 0.03 ? t / 0.03 : t < 0.12 ? 1 - 0.18 * (t - 0.03) / 0.09 : t > 1.85 ? Math.max(0, (2.0 - t) / 0.15) * 0.82 : 0.82 + 0.03 * Math.sin(t * 9)); } return v.map((x) => +x.toFixed(4)); })(), attack_sec: 0.03, decay_sec: 0.09, sustain_level: 0.82, release_sec: 0.15, loop_start_sec: 0.3, loop_end_sec: 1.6 },
    inharmonicity_b: 0.0,
    modulation: { vibrato: { rate_hz: 0, depth_cents: 0, depth: 0, onset_sec: 0, regularity: 0, detected: false }, tremolo: { rate_hz: 0, depth: 0, depth_cents: 0, onset_sec: 0, regularity: 0, detected: false } },
    harmonics: [1, 0.6, 0.42, 0.22, 0.16, 0.09, 0.07, 0.04, 0.03, 0.02].map((a, i) => ({ n: i + 1, ratio: i + 1, amp: a, amp_db: +(20 * Math.log10(a)).toFixed(2), phase: 0, env: [1, 1] })),
    noise: { level: 0.04, rate_hz: 200, envelope: [1, 0.6, 0.4, 0.35, 0.3, 0.3], bands_hz: [0, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, 22050], band_levels: [0.05, 0.2, 0.4, 0.6, 0.8, 1.0, 0.7, 0.4, 0.2] },
    waveform: { one_cycle_points: 4, one_cycle: [0, 1, 0, -1] }, features: { harmonic_count: 10 },
  };

  // ===========================================================
  //  コントロールの定義(セクション = カード)
  // ===========================================================
  const fmtPct = (v) => Math.round(v * 100) + "%";
  const fmtHz = (v) => (v >= 1000 ? (v / 1000).toFixed(v >= 10000 ? 1 : 2) + " kHz" : Math.round(v) + " Hz");
  const fmtDb = (v) => (v > 0 ? "+" : "") + (Math.round(v * 10) / 10) + " dB";
  const SHAPES = [["sine", "サイン"], ["triangle", "三角"], ["sawtooth", "ノコギリ"], ["square", "矩形"]];
  const SECTIONS = [
    {
      id: "perf", icon: "🎛", title: "演奏 / マスター", keys: ["masterVol", "transposeSemis", "glideMs", "humanizeCents"], controls: [
        { type: "range", key: "masterVol", label: "マスター音量", min: 0, max: 1.1, step: 0.01, fmt: fmtPct },
        { type: "range", key: "transposeSemis", label: "移調", min: -24, max: 24, step: 1, fmt: (v) => (v > 0 ? "+" : "") + v + " 半音" },
        { type: "range", key: "glideMs", label: "グライド (ポルタメント)", min: 0, max: 400, step: 1, fmt: (v) => v + " ms" },
        { type: "range", key: "humanizeCents", label: "ヒューマナイズ (発音ごとのピッチ揺らぎ)", min: 0, max: 30, step: 0.5, fmt: (v) => "±" + v + " ¢" },
        { type: "scope" },
      ],
    },
    {
      id: "pitch", icon: "〰️", title: "ピッチ & ビブラート", keys: ["fineCents", "vibDepthCents", "vibRateHz", "vibOnsetSec", "vibShape"], controls: [
        { type: "modInfo" },
        { type: "range", key: "fineCents", label: "ファインチューン", min: -100, max: 100, step: 1, fmt: (v) => (v > 0 ? "+" : "") + v + " ¢" },
        { type: "range", key: "vibDepthCents", label: "ビブラート 深さ (全幅)", min: 0, max: 120, step: 0.5, fmt: (v) => (v === 0 ? "なし" : "±" + (v / 2).toFixed(1) + " ¢") },
        { type: "range", key: "vibRateHz", label: "ビブラート 速さ", min: 0.1, max: 12, step: 0.05, fmt: (v) => v.toFixed(2) + " Hz" },
        { type: "range", key: "vibOnsetSec", label: "ビブラート 始まりの遅れ", min: 0, max: 2, step: 0.01, fmt: (v) => v.toFixed(2) + " s" },
        { type: "select", key: "vibShape", label: "ビブラート 波形", options: SHAPES },
        { type: "buttons", items: [["ビブラートを消す (0 に)", () => setParam("vibDepthCents", 0)], ["検出値に合わせる", applyDetectedVibrato]] },
      ],
    },
    {
      id: "harm", icon: "🎚", title: "倍音 / 音色", keys: ["brightness", "harmRolloff", "oddEvenBal", "inharmMul", "harmLimit", "harmFollowEnv"], controls: [
        { type: "harmEdit" },
        { type: "range", key: "brightness", label: "明るさ (高次倍音の傾き)", min: -1.5, max: 1.5, step: 0.02, fmt: (v) => (v > 0 ? "+" : "") + v.toFixed(2) + (v > 0 ? " 明" : v < 0 ? " 暗" : "") },
        { type: "range", key: "harmRolloff", label: "倍音の落ち (高次ほど弱める)", min: -0.15, max: 0.6, step: 0.005, fmt: (v) => v.toFixed(3) },
        { type: "range", key: "oddEvenBal", label: "奇数 / 偶数 倍音バランス", min: -1, max: 1, step: 0.02, fmt: (v) => (v < 0 ? "偶数寄り " + v.toFixed(2) : v > 0 ? "奇数寄り +" + v.toFixed(2) : "中立") },
        { type: "range", key: "inharmMul", label: "非調和性 (きしみ・金属感)", min: 0, max: 4, step: 0.05, fmt: (v) => v.toFixed(2) + " ×" },
        { type: "range", key: "harmLimit", label: "使う倍音の数", min: 1, max: 40, step: 1, fmt: (v) => v + " 本" },
        { type: "check", key: "harmFollowEnv", label: "倍音ごとの時間変化を再現する" },
        { type: "buttons", items: [["倍音ゲインをリセット", () => { synth.params.harmGains = {}; for (const v of synth.voices) v.refreshLive(["harmGains"]); drawHarmEdit(); }]] },
      ],
    },
    {
      id: "trem", icon: "📈", title: "トレモロ / 音量の揺れ", keys: ["tremDepth", "tremRateHz", "tremShape"], controls: [
        { type: "range", key: "tremDepth", label: "トレモロ 深さ", min: 0, max: 0.9, step: 0.005, fmt: (v) => (v === 0 ? "なし" : fmtPct(v)) },
        { type: "range", key: "tremRateHz", label: "トレモロ 速さ", min: 0.1, max: 12, step: 0.05, fmt: (v) => v.toFixed(2) + " Hz" },
        { type: "select", key: "tremShape", label: "トレモロ 波形", options: SHAPES },
        { type: "buttons", items: [["トレモロを消す (0 に)", () => setParam("tremDepth", 0)]] },
      ],
    },
    {
      id: "noise", icon: "🌬", title: "ノイズ / 息成分", keys: ["noiseLevel", "breathAmount", "noiseHpHz", "noiseLpHz", "attackNoise", "noiseMode"], controls: [
        { type: "range", key: "noiseLevel", label: "残差ノイズ量 (録音から抽出した分)", min: 0, max: 3, step: 0.02, fmt: (v) => v.toFixed(2) + " ×" },
        { type: "range", key: "breathAmount", label: "息ノイズを足す (連続)", min: 0, max: 1, step: 0.01, fmt: (v) => (v === 0 ? "なし" : fmtPct(v)) },
        { type: "range", key: "noiseHpHz", label: "ノイズ ローカット (低域を削る)", min: 20, max: 3000, step: 5, fmt: fmtHz },
        { type: "range", key: "noiseLpHz", label: "ノイズ ハイカット (高域を削る = こもる)", min: 500, max: 18000, step: 50, fmt: fmtHz },
        { type: "range", key: "attackNoise", label: "アタックのノイズ (チフ・弓のひっかき)", min: 0, max: 3, step: 0.05, fmt: (v) => (v === 0 ? "なし" : "×" + (1 + v).toFixed(1)) },
        { type: "select", key: "noiseMode", label: "ノイズの出し方", options: [["recorded", "録音された形をなぞる"], ["constant", "押している間ずっと一定"], ["attack", "アタックだけ短く"]] },
      ],
    },
    {
      id: "env", icon: "⏱", title: "エンベロープ (ADSR)", keys: ["envMode", "attackMs", "decayMs", "sustainLvl", "releaseMs", "attackCurve", "decayStretch"], controls: [
        { type: "envEdit" },
        { type: "select", key: "envMode", label: "振幅の作り方", options: [["recorded", "録音された形 (忠実)"], ["adsr", "ADSR 4 値 (シンプル)"]] },
        { type: "range", key: "attackMs", label: "アタック A", min: 1, max: 2000, step: 1, fmt: (v) => v + " ms" },
        { type: "range", key: "decayMs", label: "ディケイ D", min: 1, max: 3000, step: 1, fmt: (v) => v + " ms" },
        { type: "range", key: "sustainLvl", label: "サステイン S", min: 0, max: 1, step: 0.01, fmt: fmtPct },
        { type: "range", key: "releaseMs", label: "リリース R (響きの尾。短く = 乾いた感じ)", min: 5, max: 4000, step: 1, fmt: (v) => v + " ms" },
        { type: "select", key: "attackCurve", label: "アタックの形", options: [["lin", "直線"], ["exp", "指数 (キレ重視)"]] },
        { type: "range", key: "decayStretch", label: "減衰音の長さ (伸ばす / 詰める)", min: 0.3, max: 3, step: 0.05, fmt: (v) => v.toFixed(2) + " ×" },
      ],
    },
    {
      id: "space", icon: "🏛", title: "空間 / 響き (リバーブ)", keys: ["reverbMix", "reverbSizeSec", "reverbDamping", "reverbPreMs", "reverbWidth"], controls: [
        { type: "note", html: "録音に染み込んだ残響そのものは消せませんが、響きを<b>足す</b>・リリースを<b>短くして乾かす</b>(エンベロープ欄の R)で調整できます。" },
        { type: "range", key: "reverbMix", label: "リバーブ 量", min: 0, max: 1, step: 0.01, fmt: (v) => (v === 0 ? "なし" : fmtPct(v)) },
        { type: "range", key: "reverbSizeSec", label: "空間の大きさ (残響時間)", min: 0.1, max: 6, step: 0.05, fmt: (v) => v.toFixed(2) + " s" },
        { type: "range", key: "reverbDamping", label: "響きの暗さ (高 = 高域が早く消える)", min: 0, max: 0.98, step: 0.01, fmt: fmtPct },
        { type: "range", key: "reverbPreMs", label: "プリディレイ", min: 0, max: 180, step: 1, fmt: (v) => v + " ms" },
        { type: "range", key: "reverbWidth", label: "ステレオ幅", min: 0, max: 1, step: 0.01, fmt: fmtPct },
      ],
    },
    {
      id: "fx", icon: "🎸", title: "エフェクト (ドライブ / コーラス / フィルタ)", keys: ["driveAmount", "driveToneHz", "chorusMix", "chorusRateHz", "chorusDepth", "chorusWidth", "filterMode", "filterCutoffHz", "filterQ", "filterLfoRateHz", "filterLfoDepth"], controls: [
        { type: "range", key: "driveAmount", label: "ドライブ / サチュレーション (倍音を足す)", min: 0, max: 1, step: 0.01, fmt: (v) => (v === 0 ? "なし" : fmtPct(v)) },
        { type: "range", key: "driveToneHz", label: "ドライブ後のトーン (高域カット)", min: 600, max: 18000, step: 100, fmt: fmtHz },
        { type: "range", key: "chorusMix", label: "コーラス / 厚み (ユニゾン感)", min: 0, max: 1, step: 0.01, fmt: (v) => (v === 0 ? "なし" : fmtPct(v)) },
        { type: "range", key: "chorusRateHz", label: "コーラス 速さ", min: 0.05, max: 3, step: 0.01, fmt: (v) => v.toFixed(2) + " Hz" },
        { type: "range", key: "chorusDepth", label: "コーラス 深さ", min: 0, max: 1, step: 0.01, fmt: fmtPct },
        { type: "range", key: "chorusWidth", label: "コーラス ステレオ幅", min: 0, max: 1, step: 0.01, fmt: fmtPct },
        { type: "select", key: "filterMode", label: "マスターフィルタ", options: [["off", "オフ"], ["lp", "ローパス"], ["hp", "ハイパス"], ["bp", "バンドパス"]] },
        { type: "range", key: "filterCutoffHz", label: "カットオフ", min: 30, max: 20000, step: 10, fmt: fmtHz },
        { type: "range", key: "filterQ", label: "レゾナンス Q", min: 0.1, max: 20, step: 0.1, fmt: (v) => v.toFixed(1) },
        { type: "range", key: "filterLfoRateHz", label: "フィルタ LFO 速さ (ワウ)", min: 0.05, max: 10, step: 0.05, fmt: (v) => v.toFixed(2) + " Hz" },
        { type: "range", key: "filterLfoDepth", label: "フィルタ LFO 深さ", min: 0, max: 1, step: 0.01, fmt: fmtPct },
      ],
    },
    {
      id: "eq", icon: "📊", title: "ボディ EQ (帯域の押し引き)", keys: ["eqLowGain", "eqMidFreq", "eqMidGain", "eqMidQ", "eqPresGain", "eqHighGain"], controls: [
        { type: "range", key: "eqLowGain", label: "低域シェルフ (160 Hz)", min: -15, max: 15, step: 0.5, fmt: fmtDb },
        { type: "range", key: "eqMidFreq", label: "ミッドピーク 周波数", min: 150, max: 6000, step: 10, fmt: fmtHz },
        { type: "range", key: "eqMidGain", label: "ミッドピーク ゲイン (箱鳴り / 抜け)", min: -15, max: 15, step: 0.5, fmt: fmtDb },
        { type: "range", key: "eqMidQ", label: "ミッドピーク Q (幅)", min: 0.3, max: 8, step: 0.1, fmt: (v) => v.toFixed(1) },
        { type: "range", key: "eqPresGain", label: "プレゼンス (3.8 kHz・存在感)", min: -15, max: 15, step: 0.5, fmt: fmtDb },
        { type: "range", key: "eqHighGain", label: "高域シェルフ (8 kHz・空気感)", min: -15, max: 15, step: 0.5, fmt: fmtDb },
      ],
    },
  ];
  const SECTION_BY_ID = {}; SECTIONS.forEach((s) => (SECTION_BY_ID[s.id] = s));

  // ===========================================================
  //  ファイル選択 / 解析
  // ===========================================================
  const drop = $("#drop"), fileInput = $("#file");
  function showNeedServer() { $("#curproto").textContent = location.protocol + (location.host ? "//" + location.host : ""); $("#needserver").style.display = ""; }
  if (location.protocol === "file:") showNeedServer();

  drop.addEventListener("click", () => fileInput.click());
  drop.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") fileInput.click(); });
  fileInput.addEventListener("change", () => { if (fileInput.files[0]) setFile(fileInput.files[0]); });
  ["dragenter", "dragover"].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add("hot"); }));
  ["dragleave", "drop"].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove("hot"); }));
  drop.addEventListener("drop", (e) => { const f = e.dataTransfer.files[0]; if (f) setFile(f); });
  $("#analyzeBtn").addEventListener("click", analyze);
  $("#demoBtn").addEventListener("click", () => { instrument = JSON.parse(JSON.stringify(DEMO_INSTRUMENT)); preview = null; pickedFile = null; setStatus("内蔵デモ音色を読み込みました（波形プレビューはありません）"); openStudio(); });
  $("#loadJsonBtn").addEventListener("click", () => $("#jsonFile").click());
  $("#jsonFile").addEventListener("change", () => { const f = $("#jsonFile").files[0]; if (f) loadJsonFile(f); });

  function setFile(f) {
    pickedFile = f; drop.querySelector(".big").textContent = "🎵 " + f.name;
    $("#analyzeBtn").disabled = false; setStatus(`${(f.size / 1048576).toFixed(2)} MB — 自動で解析します…`);
    analyze();
  }
  function setStatus(msg, isErr) { const s = $("#status"); s.textContent = msg || ""; s.className = isErr ? "err" : ""; }
  function setBusy(b) { const s = $("#status"); if (b) s.innerHTML = '<span class="spinner"></span>解析中… (librosa の処理に数秒)'; $("#analyzeBtn").disabled = b || !pickedFile; }

  async function analyze() {
    if (!pickedFile) return;
    setBusy(true);
    const fd = new FormData(); fd.append("file", pickedFile);
    try {
      const res = await fetch("/analyze", { method: "POST", body: fd });
      const data = await res.json();
      if (!res.ok) { setStatus(data.error || `エラー (${res.status})`, true); setBusy(false); return; }
      instrument = data.instrument; preview = data.preview;
      setStatus("解析完了 ✓  下のスタジオで鳴らしながら調整できます");
      openStudio();
    } catch (err) { showNeedServer(); setStatus("解析サーバに接続できません。start.command か python app.py を起動してください。", true); }
    setBusy(false);
  }
  async function loadJsonFile(f) {
    try {
      const txt = await f.text(); const I = JSON.parse(txt);
      if (!I.harmonics || !I.envelope) throw new Error("インストゥルメント定義ではありません(harmonics / envelope が無い)");
      instrument = I; preview = null; pickedFile = null;
      setStatus("JSON を読み込みました（波形プレビューは無し。鳴らして編集できます）");
      openStudio();
    } catch (e) { setStatus("JSON を読めませんでした: " + e.message, true); }
  }

  // ===========================================================
  //  スタジオを開く / 全体描画
  // ===========================================================
  let studioBuilt = false, decodeTried = false;
  function openStudio() {
    if (!instrument) return;
    synth.load(instrument);
    // 読み込んだ JSON に fx ブロックがあれば既知のキーを取り込む
    if (instrument.fx) applyFxBlock(instrument.fx);
    if (!studioBuilt) { buildStudio(); studioBuilt = true; }
    $("#studio").classList.remove("hidden");
    wireHarmEdit();
    syncControlsFromParams();
    setHarmLimitMax();
    updateSummary();
    updateModInfo();
    drawAll();
    synth.setOriginalBuffer(null); decodeTried = false;
    $("#playOrigBtn").disabled = !pickedFile;
    $("#curNoteLbl").textContent = SL.midiName(curNote) + " (" + curNote + ")";
    $("#tVol").value = synth.params.masterVol;
    if (!rafId) loopVisuals();
    $("#studio").scrollIntoView({ behavior: "smooth", block: "start" });
  }
  function applyFxBlock(fx) {
    const P = synth.params, set = (k, v) => { if (v != null && !Number.isNaN(v)) P[k] = v; };
    set("transposeSemis", fx.transpose_semis); set("fineCents", fx.fine_cents); set("glideMs", fx.glide_ms); set("humanizeCents", fx.humanize_cents);
    if (fx.env_mode) P.envMode = fx.env_mode; if (fx.harm_follow_env != null) P.harmFollowEnv = !!fx.harm_follow_env; set("decayStretch", fx.decay_stretch); if (fx.attack_curve) P.attackCurve = fx.attack_curve;
    if (fx.noise_mode) P.noiseMode = fx.noise_mode; set("noiseHpHz", fx.noise_hp_hz); set("noiseLpHz", fx.noise_lp_hz); set("attackNoise", fx.attack_noise); set("breathAmount", fx.breath_amount);
    const r = fx.reverb || {}; set("reverbMix", r.mix); set("reverbSizeSec", r.size_sec); set("reverbDamping", r.damping); set("reverbPreMs", r.pre_ms); set("reverbWidth", r.width);
    const d = fx.drive || {}; set("driveAmount", d.amount); set("driveToneHz", d.tone_hz);
    const ch = fx.chorus || {}; set("chorusMix", ch.mix); set("chorusRateHz", ch.rate_hz); set("chorusDepth", ch.depth); set("chorusWidth", ch.width);
    const fl = fx.filter || {}; if (fl.mode) P.filterMode = fl.mode; set("filterCutoffHz", fl.cutoff_hz); set("filterQ", fl.q); set("filterLfoRateHz", fl.lfo_rate_hz); set("filterLfoDepth", fl.lfo_depth);
    const eq = fx.body_eq || {}; set("eqLowGain", eq.low_gain); set("eqMidFreq", eq.mid_freq); set("eqMidGain", eq.mid_gain); set("eqMidQ", eq.mid_q); set("eqPresGain", eq.presence_gain); set("eqHighGain", eq.high_gain);
  }

  function updateSummary() {
    const i = instrument, f = i.features || {}, e = i.envelope;
    const trimmed = (f.trimmed_lead_sec || 0) + (f.trimmed_trail_sec || 0);
    $("#srcline").textContent =
      `${i.source_file || "(JSON)"} → ${i.note_name} / ${i.fundamental_hz} Hz / ${(i.duration_sec || 0).toFixed(2)} s`
      + (trimmed > 0.005 ? `（元 ${(f.source_duration_sec || 0).toFixed(2)} s から 先頭${(f.trimmed_lead_sec || 0).toFixed(2)}s・末尾${(f.trimmed_trail_sec || 0).toFixed(2)}s の無音をカット）` : "");
    const hc = f.harmonic_count != null ? f.harmonic_count : (i.harmonics || []).filter((h) => h.amp > 0).length;
    const mod = i.modulation || {}, vib = mod.vibrato || {}, trem = mod.tremolo || {};
    const cells = [
      ["基音", `${i.fundamental_hz}<small> Hz</small>`],
      ["MIDI ノート", `${i.note_name}<small> (${i.midi_note})</small>`],
      ["長さ", `${(i.duration_sec || 0).toFixed(2)}<small> s</small>`],
      ["タイプ", i.sustaining ? '<span class="pill">持続音</span>' : '<span class="pill">減衰音</span>'],
      ["倍音数", `${hc}`],
      ["非調和性 B", `${i.inharmonicity_b}`],
      ["ノイズ量", i.noise ? `${(i.noise.level * 100).toFixed(1)}<small> %</small>` : "—"],
      ["ビブラート", vib.detected ? `${vib.rate_hz}<small> Hz</small> ±${(vib.depth_cents / 2).toFixed(0)}<small> ¢</small>` : "—"],
      ["トレモロ", trem.detected ? `${trem.rate_hz}<small> Hz</small> ${(trem.depth * 100).toFixed(0)}<small> %</small>` : "—"],
      ["スペクトル重心", f.spectral_centroid_hz != null ? `${Math.round(f.spectral_centroid_hz)}<small> Hz</small>` : "—"],
    ];
    $("#stats").innerHTML = cells.map(([k, v]) => `<div class="stat"><div class="k">${k}</div><div class="v">${v}</div></div>`).join("");
    $("#adsrline").innerHTML =
      `ADSR近似 — A <b>${(e.attack_sec * 1000).toFixed(0)} ms</b> ／ D <b>${(e.decay_sec * 1000).toFixed(0)} ms</b> ／ ` +
      `S <b>${(e.sustain_level * 100).toFixed(0)} %</b> ／ R <b>${(e.release_sec * 1000).toFixed(0)} ms</b>　|　` +
      `ループ区間 <b>${(e.loop_start_sec || 0).toFixed(2)}–${(e.loop_end_sec || 0).toFixed(2)} s</b>` +
      (i.noise ? `　|　ノイズ色（低→高）${i.noise.band_levels.map((x) => x.toFixed(2)).join(" ")}` : "");
  }
  function updateModInfo() {
    const mod = instrument.modulation || {}, vib = mod.vibrato || {}, trem = mod.tremolo || {};
    const box = $("#modInfoBox"); if (!box) return;
    if (vib.detected || trem.detected) {
      const parts = [];
      if (vib.detected) parts.push(`<b>ビブラート検出</b>: ${vib.rate_hz} Hz / 全幅 ${vib.depth_cents} ¢ (±${(vib.depth_cents / 2).toFixed(1)} ¢)` + (vib.onset_sec > 0.02 ? ` / 約 ${vib.onset_sec.toFixed(2)} s で開始` : ""));
      if (trem.detected) parts.push(`<b>トレモロ検出</b>: ${trem.rate_hz} Hz / ${(trem.depth * 100).toFixed(0)} %`);
      box.innerHTML = parts.join("<br>") + `<br><span class="dim">スタジオには既定でこの値が入っています。深さを 0 にすれば「消す」、上げれば「強める」。元はフラットな音でも、深さを上げれば付けられます。</span>`;
      box.classList.remove("dim-empty");
    } else {
      box.innerHTML = "周期的なビブラート/トレモロは検出されませんでした。深さスライダーを上げれば付けられます。";
      box.classList.add("dim-empty");
    }
  }
  function applyDetectedVibrato() {
    const v = (instrument.modulation || {}).vibrato || {};
    if (v.depth_cents) { setParam("vibDepthCents", clamp(v.depth_cents, 0, 120)); setParam("vibRateHz", clamp(v.rate_hz || 5.5, 0.1, 12)); setParam("vibOnsetSec", clamp(v.onset_sec || 0, 0, 2)); }
    else setParam("vibDepthCents", 5);
  }
  function setHarmLimitMax() {
    const maxN = (instrument.harmonics || []).filter((h) => h.amp > 0).reduce((m, h) => Math.max(m, h.n), 1);
    const inp = ctlEls.harmLimit; if (inp) { inp.max = maxN; if (+inp.value > maxN) inp.value = maxN; }
  }

  // ===========================================================
  //  スタジオ UI の構築
  // ===========================================================
  function buildStudio() {
    const grid = $("#studioGrid"); grid.innerHTML = "";
    for (const sec of SECTIONS) grid.appendChild(buildSectionCard(sec));
  }
  function buildSectionCard(sec) {
    const body = el("div", { class: "card-body" });
    for (const c of sec.controls) {
      if (c.type === "range") body.appendChild(buildRange(c));
      else if (c.type === "select") body.appendChild(buildSelect(c));
      else if (c.type === "check") body.appendChild(buildCheck(c));
      else if (c.type === "buttons") body.appendChild(buildButtons(c));
      else if (c.type === "note") body.appendChild(el("p", { class: "note", html: c.html }));
      else if (c.type === "modInfo") body.appendChild(el("div", { class: "note modinfo dim", id: "modInfoBox", text: "" }));
      else if (c.type === "scope") body.appendChild(buildScope());
      else if (c.type === "harmEdit") body.appendChild(buildHarmEdit());
      else if (c.type === "envEdit") body.appendChild(buildEnvEdit());
    }
    const head = el("div", { class: "card-head" }, [
      el("h2", null, [el("span", { class: "dot" }), document.createTextNode(" "), el("span", { class: "icon", text: sec.icon }), document.createTextNode(" " + sec.title)]),
      el("button", { class: "mini-btn", title: "この欄を初期値に戻す", onclick: () => resetSection(sec) }, "↺"),
    ]);
    return el("section", { class: "card panel", "data-sec": sec.id }, [head, body]);
  }
  function buildRange(c) {
    const id = "ctl_" + c.key;
    const inp = el("input", { type: "range", id: id, min: c.min, max: c.max, step: c.step });
    const valEl = el("span", { class: "fldval" });
    inp.addEventListener("input", () => { const v = +inp.value; setParam(c.key, v, true); valEl.textContent = c.fmt(v); });
    ctlEls[c.key] = inp; valEls[c.key] = (v) => { valEl.textContent = c.fmt(v); }; c._valEl = valEl; c._fmt = c.fmt;
    return el("div", { class: "fld" }, [
      el("label", { for: id }, [document.createTextNode(c.label + "  "), valEl]),
      inp,
    ]);
  }
  function buildSelect(c) {
    const id = "ctl_" + c.key;
    const sel = el("select", { id: id });
    for (const [val, lab] of c.options) sel.appendChild(el("option", { value: val }, lab));
    sel.addEventListener("change", () => setParam(c.key, sel.value, true));
    ctlEls[c.key] = sel;
    return el("div", { class: "fld" }, [el("label", { for: id }, c.label), sel]);
  }
  function buildCheck(c) {
    const id = "ctl_" + c.key;
    const inp = el("input", { type: "checkbox", id: id });
    inp.addEventListener("change", () => setParam(c.key, inp.checked, true));
    ctlEls[c.key] = inp;
    return el("label", { class: "fld check", for: id }, [inp, document.createTextNode(" " + c.label)]);
  }
  function buildButtons(c) {
    const row = el("div", { class: "btnrow" });
    for (const [lab, fn] of c.items) row.appendChild(el("button", { class: "btn-ghost sm", onclick: () => { ensureAudio().then(fn); } }, lab));
    return row;
  }
  function buildScope() {
    const wrap = el("div", { class: "scope-wrap" }, [el("div", { class: "canvlabel", text: "出力モニタ（波形 + レベル）" }), el("canvas", { id: "cScope", height: 90 })]);
    return wrap;
  }
  function buildHarmEdit() {
    const cv = el("canvas", { id: "cHarmEdit", height: 130 });
    const wrap = el("div", { class: "harmedit-wrap" }, [
      el("div", { class: "canvlabel", text: "倍音ごとのゲイン（バーをドラッグ。中央の点線 = 等倍 1.0。リアルタイム反映）" }),
      cv,
    ]);
    return wrap;
  }
  function buildEnvEdit() { return el("div", null, [el("div", { class: "canvlabel", text: "振幅エンベロープ（橙=A/D ・ 緑=ループ ・ 赤=リリース ・ 青破線=サステイン）" }), el("canvas", { id: "cEnv", height: 110 })]); }

  // 値表示も含めて synth.params → UI を同期
  function syncControlsFromParams() {
    const P = synth.params;
    for (const sec of SECTIONS) for (const c of sec.controls) {
      if (!c.key) continue; const inp = ctlEls[c.key]; if (!inp) continue;
      if (inp.type === "checkbox") inp.checked = !!P[c.key];
      else { inp.value = P[c.key]; }
      if (c.fmt && c._valEl) c._valEl.textContent = c.fmt(+P[c.key]);
    }
    // 反映先（鳴っている音）にも一度流す
    if (synth.ctx) synth.applyAll();
    drawEnvEdit(); drawHarmEdit();
  }
  function setParam(key, value, fromUi) {
    synth.set(key, value);
    if (!fromUi) { // プログラムから変えた場合は UI も更新
      const inp = ctlEls[key];
      if (inp) { if (inp.type === "checkbox") inp.checked = !!value; else inp.value = value; }
      if (valEls[key]) valEls[key](+value);
    }
    if (key === "masterVol") { const tv = $("#tVol"); if (tv && +tv.value !== +value) tv.value = value; }
    if (["envMode", "attackMs", "decayMs", "sustainLvl", "releaseMs", "attackCurve", "decayStretch"].indexOf(key) >= 0) drawEnvEdit();
    if (["brightness", "harmRolloff", "oddEvenBal", "harmLimit"].indexOf(key) >= 0) drawHarmEdit();
  }
  function resetSection(sec) {
    synth.resetSection(sec.keys.slice());
    if (sec.id === "harm") synth.params.harmGains = {};
    syncControlsFromParams();
    if (synth.ctx) synth.applyAll();
  }

  // ===========================================================
  //  オーディオ起動(ユーザー操作後)
  // ===========================================================
  async function ensureAudio() {
    await synth.ensureCtx();
    const hint = $("#audioHint"); if (hint) hint.style.display = "none";
    if (pickedFile && !synth.origBuffer && !decodeTried) {
      decodeTried = true;
      try { const ab = await pickedFile.arrayBuffer(); const buf = await synth.ctx.decodeAudioData(ab); synth.setOriginalBuffer(buf); }
      catch (e) { /* このブラウザがデコードできない形式(m4a 等) */ const b = $("#playOrigBtn"); if (b) { b.disabled = true; b.title = "このブラウザでは原音(" + (pickedFile.name || "") + ")をデコードできません"; } }
    }
    return synth.ctx;
  }

  // ===========================================================
  //  鍵盤
  // ===========================================================
  const WHITE_PC = [0, 2, 4, 5, 7, 9, 11], NOTE_HAS_SHARP = { 0: 1, 2: 1, 5: 1, 7: 1, 9: 1 };
  function buildKeyboard() {
    const kb = $("#keyboard"); kb.innerHTML = "";
    const octaves = 3, whites = octaves * 7 + 1;
    const wlane = el("div", { class: "klane white" });
    for (let i = 0; i < whites; i++) {
      const midi = kbBase + Math.floor(i / 7) * 12 + WHITE_PC[i % 7];
      const k = el("div", { class: "key white", "data-m": midi, title: SL.midiName(midi) }, [el("span", { class: "kl", text: SL.midiName(midi) })]);
      bindKey(k, midi);
      wlane.appendChild(k);
    }
    kb.appendChild(wlane);
    const blane = el("div", { class: "klane black" });
    for (let i = 0; i < whites; i++) {
      const slot = el("div", { class: "bslot" });
      const pc = WHITE_PC[i % 7];
      if (NOTE_HAS_SHARP[pc] && i < whites - 1) {
        const midi = kbBase + Math.floor(i / 7) * 12 + pc + 1;
        const k = el("div", { class: "key black", "data-m": midi, title: SL.midiName(midi) });
        bindKey(k, midi);
        slot.appendChild(k);
      }
      blane.appendChild(slot);
    }
    kb.appendChild(blane);
    refreshKeyHighlights();
  }
  function bindKey(k, midi) {
    const down = (e) => { e.preventDefault(); onPlayDown(midi, e.pointerId != null ? "p" + e.pointerId : "m"); };
    const up = (e) => { onPlayUp(midi, e.pointerId != null ? "p" + e.pointerId : "m"); };
    if (window.PointerEvent) { k.addEventListener("pointerdown", down); k.addEventListener("pointerup", up); k.addEventListener("pointerleave", (e) => { if (e.buttons) up(e); }); k.addEventListener("pointercancel", up); }
    else { k.addEventListener("mousedown", down); k.addEventListener("mouseup", up); k.addEventListener("mouseleave", (e) => { if (e.buttons) up(e); }); }
  }
  function refreshKeyHighlights() {
    $$("#keyboard .key").forEach((k) => { const m = +k.dataset.m; k.classList.toggle("on", synth.held.has(m) || (synth.drone && synth.droneMidi === m)); k.classList.toggle("sel", m === curNote); });
  }
  function setCurNote(m) { curNote = clamp(m, 0, 120); $("#curNoteLbl").textContent = SL.midiName(curNote) + " (" + curNote + ")"; if (synth.drone) synth.setDroneNote(curNote); refreshKeyHighlights(); }

  // 演奏(押す/離す) — ラッチモードなら押すたびにトグル
  async function onPlayDown(midi, tag) {
    await ensureAudio();
    setCurNote(midi);
    if (latch) {
      if (synth.held.has(midi)) { synth.noteOff(midi); } else { synth.noteOn(midi, 0.92); }
    } else {
      if (!heldByEvent.has(midi + ":" + tag)) { heldByEvent.add(midi + ":" + tag); synth.noteOn(midi, 0.92); }
    }
    refreshKeyHighlights();
  }
  function onPlayUp(midi, tag) {
    if (latch) return;
    if (heldByEvent.delete(midi + ":" + tag)) {
      // 同じ midi を別タグで押していなければ離す
      let stillHeld = false; heldByEvent.forEach((s) => { if (s.indexOf(midi + ":") === 0) stillHeld = true; });
      if (!stillHeld) synth.noteOff(midi);
    }
    refreshKeyHighlights();
  }

  // PC キーボード
  const KEYMAP = (function () { const m = {}; "zsxdcvgbhnjm".split("").forEach((c, i) => m[c] = i); "q2w3er5t6y7ui".split("").forEach((c, i) => m[c] = 12 + i); return m; })();
  window.addEventListener("keydown", (e) => {
    if (e.target && /INPUT|TEXTAREA|SELECT/.test(e.target.tagName)) return;
    if (e.key === "ArrowUp") { e.preventDefault(); shiftOctave(+1); return; }
    if (e.key === "ArrowDown") { e.preventDefault(); shiftOctave(-1); return; }
    if (e.key === " ") { e.preventDefault(); synth.panic(); heldByEvent.clear(); refreshKeyHighlights(); return; }
    if (e.repeat) return;
    const off = KEYMAP[e.key.toLowerCase()]; if (off === undefined) return;
    e.preventDefault(); onPlayDown(kbBase + off, "k");
  });
  window.addEventListener("keyup", (e) => {
    if (e.target && /INPUT|TEXTAREA|SELECT/.test(e.target.tagName)) return;
    const off = KEYMAP[e.key.toLowerCase()]; if (off === undefined) return;
    onPlayUp(kbBase + off, "k");
  });
  function shiftOctave(dir) { synth.releaseAllHeld(); heldByEvent.clear(); kbBase = clamp(kbBase + dir * 12, 12, 96); buildKeyboard(); }

  // ===========================================================
  //  トランスポート(常駐バー) + 書き出し
  // ===========================================================
  function wireTransport() {
    $("#octDown").addEventListener("click", () => shiftOctave(-1));
    $("#octUp").addEventListener("click", () => shiftOctave(+1));
    $("#droneBtn").addEventListener("click", async () => { await ensureAudio(); const on = !synth.drone; synth.setDrone(on, curNote); $("#droneBtn").classList.toggle("active", on); refreshKeyHighlights(); });
    $("#latchBtn").addEventListener("click", () => { latch = !latch; $("#latchBtn").classList.toggle("active", latch); if (!latch) { /* ラッチ解除時は鳴っているものは残す */ } });
    $("#panicBtn").addEventListener("click", () => { synth.panic(); synth.setDrone(false); $("#droneBtn").classList.remove("active"); heldByEvent.clear(); refreshKeyHighlights(); });
    $("#playOrigBtn").addEventListener("click", async () => { await ensureAudio(); if (synth.origNode) { synth.stopOriginal(); $("#playOrigBtn").textContent = "🔊 原音を再生"; } else if (synth.origBuffer) { synth.playOriginal(false); $("#playOrigBtn").textContent = "■ 原音停止"; const b = synth.origBuffer; setTimeout(() => { if (!synth.origNode) $("#playOrigBtn").textContent = "🔊 原音を再生"; }, (b.duration + 0.2) * 1000); } });
    // マスター音量(トランスポート側) ↔ perf セクションのスライダーを同期
    $("#tVol").addEventListener("input", () => { const v = +$("#tVol").value; setParam("masterVol", v); });
    // 書き出し
    $("#dlJsonBtn").addEventListener("click", () => {
      const I = synth.exportInstrument();
      const blob = new Blob([JSON.stringify(I, null, 1)], { type: "application/json" });
      const a = el("a", { href: URL.createObjectURL(blob), download: (instrument.name || "instrument").replace(/[^\w\-]+/g, "_") + ".tweaked.instrument.json" });
      a.click(); URL.revokeObjectURL(a.href);
      setStatus("調整後のインストゥルメント JSON を書き出しました（Processing の data/ に置けば使えます）");
    });
    $("#dlWavBtn").addEventListener("click", async () => {
      await ensureAudio();
      $("#dlWavBtn").disabled = true; const old = $("#dlWavBtn").textContent; $("#dlWavBtn").textContent = "書き出し中…";
      try {
        const dur = clamp(+$("#wavDur").value || 2.5, 0.3, 12);
        const buf = await synth.renderWav(curNote, dur);
        const a = el("a", { href: URL.createObjectURL(buf), download: (instrument.name || "instrument").replace(/[^\w\-]+/g, "_") + "_" + SL.midiName(curNote) + ".wav" });
        a.click(); URL.revokeObjectURL(a.href);
        setStatus(`WAV を書き出しました（${SL.midiName(curNote)} / ${dur.toFixed(1)} s）`);
      } catch (e) { setStatus("WAV 書き出しに失敗しました: " + e.message, true); }
      $("#dlWavBtn").textContent = old; $("#dlWavBtn").disabled = false;
    });
    $("#resetAllBtn").addEventListener("click", () => { synth.resetAll(); syncControlsFromParams(); setHarmLimitMax(); if (synth.drone) synth.setDrone(true, curNote); });
    $("#reAnalyzeBtn").addEventListener("click", () => { if (pickedFile) analyze(); else setStatus("再解析するには音源ファイルから始めてください。", true); });
  }

  // ===========================================================
  //  キャンバス描画
  // ===========================================================
  const ACC1 = "#818CF8", ACC2 = "#C084FC", GRID = "rgba(99,102,241,.18)", INKMUT = "#6366F1";
  function ctxOf(id) {
    const c = $("#" + id); if (!c) return null;
    if (!c.dataset.cssh) c.dataset.cssh = "" + (+c.getAttribute("height") || 120);
    const dpr = window.devicePixelRatio || 1, cssw = c.clientWidth || 600, cssh = +c.dataset.cssh;
    c.style.height = cssh + "px";
    const bw = Math.round(cssw * dpr), bh = Math.round(cssh * dpr);
    if (c.width !== bw || c.height !== bh) { c.width = bw; c.height = bh; }
    const x = c.getContext("2d"); x.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { c, x, w: cssw, h: cssh };
  }

  function drawAll() { drawWave(); drawSpec(); drawF0(); drawAnalyzedHarm(); drawEnvEdit(); drawHarmEdit(); }

  function drawWave() {
    const g = ctxOf("cWave"); if (!g) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    if (!preview || !preview.waveform) { dimText(x, w, h, "（波形プレビューはありません）"); return; }
    const d = preview.waveform, mid = h / 2;
    x.strokeStyle = GRID; x.beginPath(); x.moveTo(0, mid); x.lineTo(w, mid); x.stroke();
    const grad = x.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, ACC1); grad.addColorStop(1, ACC2);
    x.strokeStyle = grad; x.lineWidth = 1; x.beginPath();
    for (let k = 0; k < d.length; k++) { const px = k / (d.length - 1) * w; x.moveTo(px, mid - d[k][1] * mid * 0.95); x.lineTo(px, mid - d[k][0] * mid * 0.95); }
    x.stroke();
  }
  function freqToX(fz, fmin, fmax, w) { return (Math.log(fz) - Math.log(fmin)) / (Math.log(fmax) - Math.log(fmin)) * w; }
  function drawSpec() {
    const g = ctxOf("cSpec"); if (!g) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    if (!preview || !preview.spectrum_freq) { dimText(x, w, h, "（スペクトルプレビューはありません）"); return; }
    const fr = preview.spectrum_freq, db = preview.spectrum_db, fmin = fr[0], fmax = fr[fr.length - 1];
    x.fillStyle = INKMUT; x.font = "9px 'JetBrains Mono', monospace";
    for (const lvl of [0, -20, -40, -60]) { const y = (-lvl / 72) * h; x.strokeStyle = GRID; x.beginPath(); x.moveTo(0, y); x.lineTo(w, y); x.stroke(); x.fillText(lvl + " dB", 3, y + 10); }
    for (const hm of instrument.harmonics) { if (hm.amp <= 0) continue; const fz = hm.ratio * instrument.fundamental_hz; if (fz < fmin || fz > fmax) continue; const px = freqToX(fz, fmin, fmax, w); x.strokeStyle = hm.n === 1 ? "rgba(192,132,252,.7)" : "rgba(129,140,248,.26)"; x.beginPath(); x.moveTo(px, 0); x.lineTo(px, h); x.stroke(); }
    for (const fz of [100, 200, 500, 1000, 2000, 5000, 10000]) { if (fz < fmin || fz > fmax) continue; const px = freqToX(fz, fmin, fmax, w); x.fillStyle = INKMUT; x.fillText(fz >= 1000 ? fz / 1000 + "k" : fz + "", px + 2, h - 3); }
    const grad = x.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, ACC1); grad.addColorStop(1, ACC2);
    x.strokeStyle = grad; x.lineWidth = 1.6; x.beginPath();
    for (let k = 0; k < fr.length; k++) { const px = freqToX(fr[k], fmin, fmax, w), y = Math.min(h, -db[k] / 72 * h); k === 0 ? x.moveTo(px, y) : x.lineTo(px, y); }
    x.stroke();
  }
  function drawF0() {
    const g = ctxOf("cF0"); if (!g) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    const cents = preview && preview.f0_cents; const mid = h / 2;
    x.strokeStyle = GRID; for (const c of [-50, 0, 50]) { const y = mid - c / 100 * (h * 0.42); x.beginPath(); x.moveTo(0, y); x.lineTo(w, y); x.stroke(); x.fillStyle = INKMUT; x.font = "9px 'JetBrains Mono',monospace"; x.fillText((c > 0 ? "+" : "") + c + "¢", 3, y - 2); }
    if (!cents || cents.length < 2) { dimText(x, w, h, "（ピッチトラックがありません）", true); return; }
    let lo = 1e9, hi = -1e9; for (const v of cents) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
    const span = Math.max(30, Math.max(Math.abs(lo), Math.abs(hi)) * 1.15);
    const grad = x.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, ACC1); grad.addColorStop(1, ACC2);
    x.strokeStyle = grad; x.lineWidth = 1.6; x.beginPath();
    for (let k = 0; k < cents.length; k++) { const px = k / (cents.length - 1) * w, y = mid - cents[k] / span * (h * 0.46); k === 0 ? x.moveTo(px, y) : x.lineTo(px, y); }
    x.stroke();
  }
  function drawAnalyzedHarm() {
    const g = ctxOf("cHarm"); if (!g) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    const hs = instrument.harmonics, floor = -60;
    x.strokeStyle = GRID; x.fillStyle = INKMUT; x.font = "9px 'JetBrains Mono',monospace";
    for (const lvl of [0, -20, -40]) { const y = -lvl / -floor * h; x.beginPath(); x.moveTo(0, y); x.lineTo(w, y); x.stroke(); x.fillText(lvl + "", 3, y + 10); }
    const n = hs.length, bw = w / Math.max(n, 1);
    for (let k = 0; k < n; k++) { const hm = hs[k]; if (hm.amp <= 0) continue; const db = Math.max(floor, hm.amp_db), bh = (1 - db / floor) * h; const gr = x.createLinearGradient(0, h - bh, 0, h); gr.addColorStop(0, ACC2); gr.addColorStop(1, ACC1); x.fillStyle = gr; x.fillRect(k * bw + 1, h - bh, bw - 2, bh); if (n <= 28) { x.fillStyle = INKMUT; x.fillText(hm.n + "", k * bw + bw / 2 - 3, h - 4); } }
  }
  function dimText(x, w, h, msg, small) { x.fillStyle = "rgba(99,102,241,.5)"; x.font = (small ? "10px" : "12px") + " 'DM Sans',sans-serif"; x.textAlign = "center"; x.fillText(msg, w / 2, h / 2); x.textAlign = "left"; }

  // 振幅エンベロープ(編集中の ADSR/録音 を反映したプレビュー)
  function drawEnvEdit() {
    const g = ctxOf("cEnv"); if (!g || !instrument) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    const P = synth.params, e = instrument.envelope, recorded = (P.envMode === "recorded");
    const margin = 6, H = h - margin * 2;
    x.strokeStyle = GRID; for (const ly of [0.25, 0.5, 0.75, 1]) { const y = h - margin - ly * H; x.beginPath(); x.moveTo(0, y); x.lineTo(w, y); x.stroke(); }
    // 横軸: 表示窓 = サステイン少し + リリース が見える長さ
    let pts = []; // {t, v}
    if (recorded) {
      const v = e.values, rate = e.rate_hz, origDur = (v.length - 1) / rate;
      const dur = instrument.sustaining ? Math.min(origDur, (e.loop_start_sec || origDur * 0.3) * 1.6 + 0.2) : origDur * (P.decayStretch || 1);
      const totT = dur + P.releaseMs / 1000 + 0.05;
      for (let k = 0; k <= 80; k++) { const t = k / 80 * dur; pts.push({ t: t, v: sampleArr(v, rate, instrument.sustaining ? Math.min(t, origDur) : t) }); }
      // リリース尾
      const lastV = pts[pts.length - 1].v;
      for (let k = 1; k <= 20; k++) { const u = k / 20; pts.push({ t: dur + u * (P.releaseMs / 1000), v: lastV * (1 - u) * (1 - u) }); }
      // 区間境界(描画用)
      drawEnvLine(x, w, h, margin, H, pts, totT, instrument.sustaining ? (e.loop_start_sec || origDur * 0.3) : origDur * 0.4 * (P.decayStretch || 1), dur);
      drawSusLine(x, w, h, margin, H, recordedSusLevel(), totT, dur);
    } else {
      const A = P.attackMs / 1000, D = P.decayMs / 1000, Sl = P.sustainLvl, R = P.releaseMs / 1000;
      const susShow = instrument.sustaining ? Math.max(0.25, (A + D) * 0.8) : 0;
      const totT = A + D + susShow + R + 0.02;
      pts.push({ t: 0, v: 0 });
      // attack
      for (let k = 1; k <= 16; k++) { const u = k / 16; pts.push({ t: u * A, v: P.attackCurve === "exp" ? u * u : u }); }
      // decay→sustain (持続音) / decay→~0 (減衰音)
      const sTarget = instrument.sustaining ? Sl : 0.02;
      for (let k = 1; k <= 16; k++) { const u = k / 16; pts.push({ t: A + u * D, v: 1 + (sTarget - 1) * (1 - Math.exp(-3 * u)) }); }
      if (instrument.sustaining) pts.push({ t: A + D + susShow, v: sTarget });
      const relStart = instrument.sustaining ? A + D + susShow : A + D;
      const relFrom = pts[pts.length - 1].v;
      for (let k = 1; k <= 16; k++) { const u = k / 16; pts.push({ t: relStart + u * R, v: relFrom * (1 - u) * (1 - u) }); }
      drawEnvLine(x, w, h, margin, H, pts, totT, A + D, relStart);
      if (instrument.sustaining) drawSusLine(x, w, h, margin, H, Sl, totT, relStart);
    }
  }
  function recordedSusLevel() { const v = instrument.envelope.values, rate = instrument.envelope.rate_hz; const a = Math.round((instrument.envelope.loop_start_sec || 0) * rate), b = Math.round((instrument.envelope.loop_end_sec || 0) * rate); let s = 0, c = 0; for (let k = Math.max(0, a); k <= Math.min(v.length - 1, b); k++) { s += v[k]; c++; } return c ? s / c : (instrument.envelope.sustain_level || 0.7); }
  function sampleArr(arr, rate, t) { if (!arr || arr.length === 0) return 0; const x = t * rate; if (x <= 0) return arr[0]; if (x >= arr.length - 1) return arr[arr.length - 1]; const i0 = Math.floor(x), i1 = i0 + 1; return arr[i0] + (arr[i1] - arr[i0]) * (x - i0); }
  function drawEnvLine(x, w, h, margin, H, pts, totT, adEnd, relStart) {
    const X = (t) => t / totT * w, Y = (v) => h - margin - clamp(v, 0, 1.05) * H;
    // 区間の塗り
    x.fillStyle = "rgba(74,222,128,.14)"; x.fillRect(X(adEnd), 0, X(relStart) - X(adEnd), h);
    x.fillStyle = "rgba(244,114,182,.13)"; x.fillRect(X(relStart), 0, w - X(relStart), h);
    // 折れ線(区間で色分け)
    const colOf = (t) => t < adEnd - 1e-6 ? "#F59E0B" : (t < relStart - 1e-6 ? "#22C55E" : "#EF4444");
    for (let k = 1; k < pts.length; k++) { x.strokeStyle = colOf(pts[k - 1].t); x.lineWidth = 2; x.beginPath(); x.moveTo(X(pts[k - 1].t), Y(pts[k - 1].v)); x.lineTo(X(pts[k].t), Y(pts[k].v)); x.stroke(); }
  }
  function drawSusLine(x, w, h, margin, H, lvl, totT, relStart) { x.strokeStyle = "rgba(99,102,241,.55)"; x.setLineDash([4, 3]); const y = h - margin - clamp(lvl, 0, 1.05) * H; x.beginPath(); x.moveTo(0, y); x.lineTo(w, y); x.stroke(); x.setLineDash([]); }

  // 倍音ごとのゲイン(ドラッグ編集)
  let harmEditDrag = false;
  function harmEditList() { return (instrument.harmonics || []).filter((h) => h.amp > 0); }
  function drawHarmEdit() {
    const g = ctxOf("cHarmEdit"); if (!g || !instrument) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    const P = synth.params, list = harmEditList(), n = list.length, bw = w / Math.max(n, 1);
    const maxMul = 2.0, base1 = h - (1 / maxMul) * h;  // ゲイン 1.0 のライン
    x.strokeStyle = GRID; for (const m of [0.5, 1.5]) { const y = h - m / maxMul * h; x.beginPath(); x.moveTo(0, y); x.lineTo(w, y); x.stroke(); }
    x.strokeStyle = "rgba(99,102,241,.5)"; x.setLineDash([4, 3]); x.beginPath(); x.moveTo(0, base1); x.lineTo(w, base1); x.stroke(); x.setLineDash([]);
    x.fillStyle = INKMUT; x.font = "9px 'JetBrains Mono',monospace"; x.fillText("1.0×", 3, base1 - 3);
    for (let k = 0; k < n; k++) {
      const hm = list[k]; const lim = (hm.n > (P.harmLimit || 999));
      const mul = clamp(P.harmGains && P.harmGains[hm.n] != null ? P.harmGains[hm.n] : 1, 0, maxMul);
      const bh = mul / maxMul * h;
      const gr = x.createLinearGradient(0, h - bh, 0, h); gr.addColorStop(0, lim ? "rgba(150,150,170,.5)" : ACC2); gr.addColorStop(1, lim ? "rgba(150,150,170,.3)" : ACC1);
      x.fillStyle = gr; x.fillRect(k * bw + 1.5, h - bh, bw - 3, bh);
      if (n <= 28) { x.fillStyle = lim ? "rgba(120,120,140,.7)" : INKMUT; x.fillText(hm.n + "", k * bw + bw / 2 - 3, h - 4); }
    }
  }
  function harmEditAt(ev) {
    const c = $("#cHarmEdit"); if (!c) return null; const r = c.getBoundingClientRect();
    const px = (ev.touches ? ev.touches[0].clientX : ev.clientX) - r.left, py = (ev.touches ? ev.touches[0].clientY : ev.clientY) - r.top;
    const list = harmEditList(), n = list.length, bw = r.width / Math.max(n, 1);
    const idx = clamp(Math.floor(px / bw), 0, n - 1); const mul = clamp((1 - py / r.height) * 2.0, 0, 2.0);
    return { n: list[idx].n, mul: Math.round(mul * 50) / 50 };
  }
  function wireHarmEdit() {
    const c = $("#cHarmEdit"); if (!c || c._wired) return; c._wired = true;
    const apply = (ev) => { const a = harmEditAt(ev); if (!a) return; ensureAudio().then(() => { synth.setHarmGain(a.n, a.mul); drawHarmEdit(); }); };
    c.addEventListener("pointerdown", (e) => { e.preventDefault(); harmEditDrag = true; apply(e); });
    c.addEventListener("pointermove", (e) => { if (harmEditDrag) { e.preventDefault(); apply(e); } });
    window.addEventListener("pointerup", () => { harmEditDrag = false; });
    c.addEventListener("dblclick", (e) => { const a = harmEditAt(e); if (a) { synth.setHarmGain(a.n, 1); drawHarmEdit(); } });
  }

  // ===========================================================
  //  リアルタイム可視化ループ(出力モニタ + 鍵盤ハイライト)
  // ===========================================================
  function loopVisuals() {
    rafId = requestAnimationFrame(loopVisuals);
    drawScope();
    // ボイス掃除の取りこぼし対策
    if (synth.ctx) synth._gc && synth._gc();
  }
  let scopeBuf = null;
  function drawScope() {
    const g = ctxOf("cScope"); if (!g) return; const { x, w, h } = g; x.clearRect(0, 0, w, h);
    const a = synth.analyser;
    x.fillStyle = "rgba(255,255,255,.35)"; x.fillRect(0, 0, w, h);
    x.strokeStyle = GRID; x.beginPath(); x.moveTo(0, h / 2); x.lineTo(w, h / 2); x.stroke();
    if (!a) { dimText(x, w, h, "音を鳴らすと波形が出ます", true); return; }
    const N = a.fftSize; if (!scopeBuf || scopeBuf.length !== N) scopeBuf = new Uint8Array(N);
    a.getByteTimeDomainData(scopeBuf);
    let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(scopeBuf[i] - 128));
    const grad = x.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, ACC1); grad.addColorStop(1, ACC2);
    x.strokeStyle = grad; x.lineWidth = 1.4; x.beginPath();
    for (let i = 0; i < N; i++) { const px = i / (N - 1) * w, y = h / 2 - (scopeBuf[i] - 128) / 128 * (h / 2 - 2); i === 0 ? x.moveTo(px, y) : x.lineTo(px, y); }
    x.stroke();
    // レベルバー(右端)
    const lvl = clamp(peak / 128, 0, 1); x.fillStyle = lvl > 0.95 ? "#EF4444" : "rgba(129,140,248,.55)"; x.fillRect(w - 6, h - lvl * h, 6, lvl * h);
    refreshKeyHighlights();
  }

  // ===========================================================
  //  起動時のセットアップ
  // ===========================================================
  let _inited = false;
  function init() {
    if (_inited) return; _inited = true;
    buildKeyboard();
    wireTransport();
    window.addEventListener("resize", () => { if (instrument && !$("#studio").classList.contains("hidden")) drawAll(); });
  }
  document.addEventListener("DOMContentLoaded", init);
  if (document.readyState !== "loading") init();
})();
