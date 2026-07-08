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
  const stepDecimals = (step) => {
    const s = String(step == null ? "" : step);
    if (s.indexOf("e-") >= 0) return +(s.split("e-")[1] || 0);
    const i = s.indexOf(".");
    return i >= 0 ? s.length - i - 1 : 0;
  };
  const rawNumberText = (c, v) => {
    const n = +v;
    if (!Number.isFinite(n)) return "";
    const d = stepDecimals(c.step);
    return d > 0 ? n.toFixed(d) : String(Math.round(n));
  };
  const safeName = (s) => (s || "instrument").replace(/\.[^.]+$/, "").replace(/[^\w\-]+/g, "_");
  const deepCopy = (v) => JSON.parse(JSON.stringify(v));

  // ── 状態 ─────────────────────────────────────────────────
  const synth = new SL.LiveSynth();
  let workspaceMode = "single"; // single / compat / balance
  let pickedFile = null;        // 解析にかけた音源ファイル(原音 A/B 用に保持)
  let instrument = null, preview = null;
  let ctlEls = {};              // key → input 要素(値表示の更新用に保持)
  let numEls = {};              // key → 直接入力用 number 要素
  let valEls = {};
  let kbBase = 48;              // 鍵盤左端の MIDI
  let curNote = 60;             // 現在選択中(ドローン/書き出し対象)の音
  let latch = false;            // クリックで保持モード
  const heldByEvent = new Set();// マウス/タッチ/PCキーで押している MIDI(離す用)
  let rafId = 0;
  const BATCH_MAX_FILES = 12;
  const batch = { files: [], tracks: [], metalApplied: false };
  const compare = { A: null, B: null, active: "B", noteA: "初期値", noteB: "現在" };
  const NOTE_PC = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

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
      id: "metal", icon: "🔔", title: "金属楽器クオリティ向上", keys: ["brightness", "harmRolloff", "oddEvenBal", "inharmMul", "drumSampleMix", "attackSampleMix", "trumpetWaveMix", "sustainSampleMix", "brassLayerMix", "brassLayerDetuneCents", "trumpetResonance", "attackNoise", "noiseLevel", "reverbMix", "driveAmount", "eqPresGain", "eqHighGain"], controls: [
        { type: "note", html: "金属楽器・金属的な打楽器向けに、アタックの輪郭、明るい倍音、わずかな非調和性、抜ける帯域をまとめて整えます。" },
        { type: "range", key: "drumSampleMix", label: "原音1打を主音にする", min: 0, max: 1.2, step: 0.01, fmt: fmtPct },
        { type: "range", key: "attackSampleMix", label: "原音アタックを重ねる", min: 0, max: 1.2, step: 0.01, fmt: fmtPct },
        { type: "range", key: "trumpetWaveMix", label: "原音波形の芯を混ぜる", min: 0, max: 1, step: 0.01, fmt: fmtPct },
        { type: "range", key: "sustainSampleMix", label: "原音の伸びを重ねる", min: 0, max: 0.9, step: 0.01, fmt: fmtPct },
        { type: "range", key: "brassLayerMix", label: "トランペットの重なり", min: 0, max: 0.75, step: 0.01, fmt: fmtPct },
        { type: "range", key: "brassLayerDetuneCents", label: "重なりのピッチ差", min: 0, max: 18, step: 0.5, fmt: (v) => v.toFixed(1) + " ¢" },
        { type: "range", key: "trumpetResonance", label: "トランペット管の共鳴", min: 0, max: 1, step: 0.01, fmt: fmtPct },
        { type: "buttons", items: [["原音に近い", () => applyTrumpetPreset("natural")], ["明るく抜ける", () => applyTrumpetPreset("bright")], ["太く厚く", () => applyTrumpetPreset("thick")], ["ノイズ控えめ", () => applyTrumpetPreset("clean")], ["金管レイヤー強め", () => applyTrumpetPreset("layer")], ["ドラムを太く整える", applyDrumPunchPreset], ["金属楽器プリセットを適用", applyMetalQualityPreset], ["アタックを強める", applyMetalAttackPreset], ["明るさを少し戻す", softenMetalPreset]] },
      ],
    },
    {
      id: "strings", icon: "🎻", title: "弦楽器 / ヴァイオリン調整", keys: ["brightness", "harmRolloff", "oddEvenBal", "inharmMul", "attackSampleMix", "sustainSampleMix", "noiseLevel", "noiseHpHz", "noiseLpHz", "attackNoise", "vibDepthCents", "vibRateHz", "vibOnsetSec", "chorusMix", "chorusRateHz", "chorusDepth", "reverbMix", "eqLowGain", "eqMidFreq", "eqMidGain", "eqPresGain", "eqHighGain"], controls: [
        { type: "note", html: "C4〜A4 の主旋律をヴァイオリン相当として扱うための調整です。弓の立ち上がり、こすれるノイズ、少し暗めの倍音、細い揺れ、胴鳴りをまとめて整えます。" },
        { type: "buttons", items: [["ヴァイオリン向けに整える", applyStringQualityPreset], ["弦らしさ強め", () => applyStringPreset("bowed")], ["弓感最大", () => applyStringPreset("rosin")], ["やわらかめ", () => applyStringPreset("soft")], ["明るめ", () => applyStringPreset("bright")], ["弓ノイズ控えめ", () => applyStringPreset("clean")]] },
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

  $("#singleModeBtn").addEventListener("click", () => setMode("single"));
  $("#compatModeBtn").addEventListener("click", () => setMode("compat"));
  $("#balanceModeBtn").addEventListener("click", () => setMode("balance"));
  function setMode(mode) {
    const previous = workspaceMode;
    workspaceMode = mode;
    const single = mode !== "balance";
    const compat = mode === "compat";
    $("#singleMode").classList.toggle("hidden", !single);
    $("#balanceMode").classList.toggle("hidden", single);
    $("#singleModeBtn").classList.toggle("active", mode === "single");
    $("#compatModeBtn").classList.toggle("active", compat);
    $("#balanceModeBtn").classList.toggle("active", mode === "balance");
    $("#singleModeBtn").setAttribute("aria-selected", mode === "single" ? "true" : "false");
    $("#compatModeBtn").setAttribute("aria-selected", compat ? "true" : "false");
    $("#balanceModeBtn").setAttribute("aria-selected", mode === "balance" ? "true" : "false");
    $("#compatIntro").classList.toggle("hidden", !compat);
    document.body.classList.toggle("compat-mode", compat);
    updateCompatibilityUi();
    if (instrument && compat && previous !== "compat") {
      synth.load(instrument);
      if (instrument.fx) applyFxBlock(instrument.fx);
      applyTestMultiCompatibility(true);
      syncControlsFromParams();
      setHarmLimitMax();
      updateCompatibilityTarget();
      drawAll();
      setStatus("test_multi 互換値へ切り替えました。通常モードでの未保存の編集値はリセットされています。");
    } else if (instrument && mode !== "compat" && previous === "compat") {
      synth.load(instrument);
      if (instrument.fx) applyFxBlock(instrument.fx);
      syncControlsFromParams();
      setHarmLimitMax();
      drawAll();
      setStatus("通常の高機能スタジオへ戻しました。互換モードでの未保存の編集値はリセットされています。");
    }
  }

  function updateCompatibilityUi() {
    const compat = workspaceMode === "compat";
    const wb = $("#compatWorkbench"); if (wb) wb.classList.toggle("hidden", !compat || !instrument);
    $$(".standard-export-help").forEach((e) => e.classList.toggle("hidden", compat));
    $$(".compat-export-help").forEach((e) => e.classList.toggle("hidden", !compat));
    const dl = $("#dlJsonBtn"); if (dl) dl.textContent = compat ? "⬇ test_multi 用 JSON" : "⬇ 調整後のインストゥルメント JSON";
  }

  function applyTestMultiCompatibility(resetSupported) {
    const P = synth.params;
    Object.assign(P, {
      testMultiCompat: true,
      masterVol: 0.93,
      transposeSemis: 0, fineCents: 0, glideMs: 0, humanizeCents: 0,
      vibDepthCents: 0, tremDepth: 0,
      harmFollowEnv: true, harmonicGainTrim: 1,
      noiseLevel: 1, noiseHpHz: 20, noiseLpHz: 20000, breathAmount: 0, attackNoise: 0,
      attackSampleMix: 0, trumpetWaveMix: 0, sustainSampleMix: 0,
      brassLayerMix: 0, brassLayerDetuneCents: 0,
      drumSampleMix: 0,
      envMode: "adsr", attackCurve: "lin", decayStretch: 1,
      reverbMix: 0, driveAmount: 0, chorusMix: 0,
      filterMode: "off", filterLfoDepth: 0,
    });
    if (resetSupported) {
      P.brightness = 0;
      P.harmRolloff = 0;
      P.oddEvenBal = 0;
      P.inharmMul = 1;
      P.harmGains = {};
      const ns = (instrument.harmonics || []).filter((h) => h.amp > 0).map((h) => h.n);
      P.harmLimit = ns.length ? Math.max.apply(null, ns) : 1;
    }
    if (synth.ctx) synth.applyAll();
  }

  function updateCompatibilityTarget() {
    const select = $("#compatTarget"); if (!select || !instrument) return;
    const text = ((instrument.instrument_profile || "") + " " + (instrument.name || "") + " " + (instrument.source_file || "")).toLowerCase();
    select.value = /horn/.test(text) ? "horn" : "trumpet";
    renderCompatibilitySummary();
  }

  function renderCompatibilitySummary() {
    const box = $("#compatOutputSummary");
    if (!box || !instrument || workspaceMode !== "compat") return;
    const result = exportTestMultiInstrument();
    const out = result.out, env = out.envelope || {}, hs = out.harmonics || [];
    const dynamicCount = (instrument.harmonics || []).filter((h) => Array.isArray(h.env) && h.env.length >= 2).length;
    const noise = out.noise && Number.isFinite(+out.noise.level) ? +out.noise.level : 0;
    const fx = out.fx || {}, eq = fx.body_eq || {};
    const checkText = result.errors.length ? "⚠ " + result.errors.join(" / ")
      : dynamicCount === 0 ? "⚠ 元JSONに倍音envがありません（固定倍音になります）"
      : "✓ 改善版JSON検証OK";
    box.textContent = `${checkText} ｜ ${result.filename} ｜ 倍音 ${hs.length}本（解析env ${dynamicCount}本）` +
      ` ｜ ADSR ${Math.round((env.attack_sec || 0)*1000)}/${Math.round((env.decay_sec || 0)*1000)}/${(+env.sustain_level || 0).toFixed(2)}/${Math.round((env.release_sec || 0)*1000)}` +
      ` ｜ noise ${noise.toFixed(3)} ｜ EQ L${+eq.low_gain || 0} M${+eq.mid_gain || 0} P${+eq.presence_gain || 0} H${+eq.high_gain || 0} dB` +
      ` ｜ 管共鳴 ${Math.round((+fx.trumpet_resonance || 0)*100)}%`;
  }

  drop.addEventListener("click", () => fileInput.click());
  drop.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") fileInput.click(); });
  fileInput.addEventListener("change", () => { if (fileInput.files[0]) setFile(fileInput.files[0]); });
  ["dragenter", "dragover"].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add("hot"); }));
  ["dragleave", "drop"].forEach((ev) => drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove("hot"); }));
  drop.addEventListener("drop", (e) => { const f = e.dataTransfer.files[0]; if (f) setFile(f); });
  $("#analyzeBtn").addEventListener("click", analyze);
  $("#singleMetalBtn").addEventListener("click", async () => { await ensureAudio(); applyMetalQualityPreset(); });
  $("#singleStringBtn").addEventListener("click", async () => { await ensureAudio(); applyStringQualityPreset(); });
  $("#singleDrumBtn").addEventListener("click", async () => { await ensureAudio(); applyDrumPunchPreset(); });
  $("#demoBtn").addEventListener("click", () => { instrument = JSON.parse(JSON.stringify(DEMO_INSTRUMENT)); preview = null; pickedFile = null; setStatus("内蔵デモ音色を読み込みました（波形プレビューはありません）"); openStudio(); });
  $("#loadJsonBtn").addEventListener("click", () => $("#jsonFile").click());
  $("#jsonFile").addEventListener("change", () => { const f = $("#jsonFile").files[0]; if (f) loadJsonFile(f); });

  const batchDrop = $("#batchDrop"), batchFiles = $("#batchFiles");
  batchDrop.addEventListener("click", () => batchFiles.click());
  batchDrop.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") batchFiles.click(); });
  batchFiles.addEventListener("change", () => setBatchFiles(batchFiles.files));
  ["dragenter", "dragover"].forEach((ev) => batchDrop.addEventListener(ev, (e) => { e.preventDefault(); batchDrop.classList.add("hot"); }));
  ["dragleave", "drop"].forEach((ev) => batchDrop.addEventListener(ev, (e) => { e.preventDefault(); batchDrop.classList.remove("hot"); }));
  batchDrop.addEventListener("drop", (e) => { setBatchFiles(e.dataTransfer.files); });
  $("#analyzeBatchBtn").addEventListener("click", analyzeBatch);
  $("#batchMetalBtn").addEventListener("click", () => { applyMetalToBatch(); renderBatchList(); setBatchStatus("複数音源に金属楽器向け補正を適用しました"); });
  $("#autoBalanceBtn").addEventListener("click", () => { autoBalanceBatch(); renderBatchList(); setBatchStatus("解析ピークを目安に音量をそろえました"); });
  $("#exportMultiNoteBtn").addEventListener("click", exportMultiNoteJson);
  $("#exportRepresentativeBtn").addEventListener("click", exportRepresentativeJson);
  $("#exportBatchZipBtn").addEventListener("click", exportBatchZip);

  function setFile(f) {
    pickedFile = f; drop.querySelector(".big").textContent = "🎵 " + f.name;
    $("#analyzeBtn").disabled = false; setStatus(`${(f.size / 1048576).toFixed(2)} MB — 自動で解析します…`);
    analyze();
  }
  function setStatus(msg, isErr) { const s = $("#status"); s.textContent = msg || ""; s.className = isErr ? "err" : ""; }
  function setBatchStatus(msg, isErr) { const s = $("#batchStatus"); s.textContent = msg || ""; s.className = isErr ? "err" : ""; }
  function setBusy(b) { const s = $("#status"); if (b) s.innerHTML = '<span class="spinner"></span>解析中… (librosa の処理に数秒)'; $("#analyzeBtn").disabled = b || !pickedFile; }
  function setBatchBusy(b, msg) {
    if (b) $("#batchStatus").innerHTML = '<span class="spinner"></span>' + (msg || "解析中…");
    $("#analyzeBatchBtn").disabled = b || batch.files.length === 0;
    $("#exportBatchZipBtn").disabled = b || batch.tracks.length === 0;
    $("#exportMultiNoteBtn").disabled = b || batch.tracks.length === 0;
    $("#exportRepresentativeBtn").disabled = b || batch.tracks.length === 0;
    $("#autoBalanceBtn").disabled = b || batch.tracks.length === 0;
    $("#batchMetalBtn").disabled = b || batch.tracks.length === 0;
  }

  async function analyze() {
    if (!pickedFile) return;
    setBusy(true);
    try {
      const data = await analyzeOneFile(pickedFile);
      instrument = data.instrument; preview = data.preview;
      setStatus("解析完了 ✓  下のスタジオで鳴らしながら調整できます");
      openStudio();
      $("#singleMetalBtn").disabled = false;
      $("#singleStringBtn").disabled = false;
      $("#singleDrumBtn").disabled = false;
    } catch (err) {
      if (location.protocol === "file:" || /Failed to fetch|NetworkError/.test(err.message)) {
        showNeedServer(); setStatus("解析サーバに接続できません。start.command か python app.py を起動してください。", true);
      } else {
        setStatus(err.message || "解析に失敗しました。", true);
      }
    }
    setBusy(false);
  }
  async function analyzeOneFile(file) {
    const fd = new FormData(); fd.append("file", file);
    const prof = $("#instrumentProfile");
    if (prof) fd.append("profile", prof.value || "auto");
    const res = await fetch("/analyze", { method: "POST", body: fd });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `エラー (${res.status})`);
    return data;
  }
  async function loadJsonFile(f) {
    try {
      const txt = await f.text(); const I = JSON.parse(txt);
      if (!I.harmonics || !I.envelope) throw new Error("インストゥルメント定義ではありません(harmonics / envelope が無い)");
      instrument = I; preview = null; pickedFile = null;
      setStatus("JSON を読み込みました（波形プレビューは無し。鳴らして編集できます）");
      openStudio();
      $("#singleMetalBtn").disabled = false;
      $("#singleStringBtn").disabled = false;
      $("#singleDrumBtn").disabled = false;
    } catch (e) { setStatus("JSON を読めませんでした: " + e.message, true); }
  }

  function setBatchFiles(filesLike) {
    const selected = Array.from(filesLike || []);
    const files = selected.slice(0, BATCH_MAX_FILES);
    batch.files = files; batch.tracks = []; batch.metalApplied = false;
    batchDrop.querySelector(".big").textContent = files.length ? `🎚 ${files.length} 個の音源を選択中` : "🎚 複数の音源ファイルをまとめて選択";
    $("#analyzeBatchBtn").disabled = files.length === 0;
    $("#exportBatchZipBtn").disabled = true;
    $("#exportMultiNoteBtn").disabled = true;
    $("#exportRepresentativeBtn").disabled = true;
    $("#autoBalanceBtn").disabled = true;
    $("#batchMetalBtn").disabled = true;
    const clipped = selected.length > BATCH_MAX_FILES ? `（先頭 ${BATCH_MAX_FILES} 個だけ使います）` : "";
    setBatchStatus(files.length ? `${files.length} 個を選択しました。${clipped}` : "");
    renderBatchList();
  }
  async function analyzeBatch() {
    if (!batch.files.length) return;
    batch.tracks = []; batch.metalApplied = false; renderBatchList();
    setBatchBusy(true, `解析中… 0 / ${batch.files.length}`);
    try {
      for (let i = 0; i < batch.files.length; i++) {
        const file = batch.files[i];
        setBatchBusy(true, `解析中… ${i + 1} / ${batch.files.length} (${file.name})`);
        try {
          const data = await analyzeOneFile(file);
          const t = makeBatchTrack(file, data.instrument);
          batch.tracks.push(t);
        } catch (e) {
          batch.tracks.push({ file, error: e.message, volume: 0.6 });
        }
        renderBatchList();
      }
      autoBalanceBatch();
      renderBatchList();
      const ok = batch.tracks.filter((t) => !t.error).length;
      setBatchStatus(ok ? `解析完了 ✓ ${ok} 音源を調整できます` : "解析できた音源がありませんでした", ok === 0);
    } catch (e) {
      showNeedServer(); setBatchStatus("解析サーバに接続できません。start.command か python app.py を起動してください。", true);
    }
    setBatchBusy(false);
  }

  // ===========================================================
  //  スタジオを開く / 全体描画
  // ===========================================================
  let studioBuilt = false, decodeTried = false;
  function openStudio() {
    if (!instrument) return;
    synth.load(instrument);
    // 読み込んだ JSON に fx ブロックがあれば既知のキーを取り込む
    if (workspaceMode === "compat") {
      if (instrument.fx) applyFxBlock(instrument.fx);
      applyTestMultiCompatibility(true);
    }
    else if (instrument.fx) applyFxBlock(instrument.fx);
    if (!studioBuilt) { buildStudio(); studioBuilt = true; }
    $("#studio").classList.remove("hidden");
    updateCompatibilityUi();
    updateCompatibilityTarget();
    wireHarmEdit();
    syncControlsFromParams();
    setHarmLimitMax();
    initCompareSlots();
    updateSummary();
    updateModInfo();
    drawAll();
    synth.setOriginalBuffer(null); decodeTried = false;
    $("#playOrigBtn").disabled = !pickedFile;
    $("#singleMetalBtn").disabled = false;
    $("#singleStringBtn").disabled = false;
    $("#singleDrumBtn").disabled = false;
    $("#curNoteLbl").textContent = SL.midiName(curNote) + " (" + curNote + ")";
    $("#tVol").value = synth.params.masterVol;
    if (!rafId) loopVisuals();
    $("#studio").scrollIntoView({ behavior: "smooth", block: "start" });
  }
  function initCompareSlots() {
    const snap = deepCopy(synth.params);
    compare.A = deepCopy(snap);
    compare.B = deepCopy(snap);
    compare.active = "B";
    compare.noteA = "初期値";
    compare.noteB = "現在";
    updateCompareStatus("A: 初期値 / B: 現在");
  }
  function updateCompareStatus(msg) {
    const s = $("#abStatus");
    if (!s) return;
    const active = compare.active ? `再生中: ${compare.active}` : "";
    s.textContent = msg || `A: ${compare.noteA || "保存済み"} / B: ${compare.noteB || "保存済み"}${active ? " / " + active : ""}`;
  }
  function saveCompareSlot(slot, note) {
    if (!instrument) return;
    compare[slot] = deepCopy(synth.params);
    compare["note" + slot] = note || "手動保存";
    compare.active = slot;
    updateCompareStatus(`${slot}へ保存しました`);
  }
  function applyCompareSlot(slot) {
    const snap = compare[slot];
    if (!snap) { updateCompareStatus(`${slot}はまだ保存されていません`); return; }
    synth.params = deepCopy(snap);
    compare.active = slot;
    syncControlsFromParams();
    setHarmLimitMax();
    if (synth.drone) synth.setDrone(true, curNote);
    updateCompareStatus(`${slot}を適用しました`);
  }
  function toggleCompareSlot() {
    applyCompareSlot(compare.active === "A" ? "B" : "A");
  }
  function beginPresetCompare() {
    if (!instrument) return;
    compare.A = deepCopy(synth.params);
    compare.noteA = "プリセット前";
    compare.active = "A";
  }
  function finishPresetCompare(note) {
    if (!instrument) return;
    compare.B = deepCopy(synth.params);
    compare.noteB = note || "プリセット後";
    compare.active = "B";
    updateCompareStatus(`A: プリセット前 / B: ${compare.noteB}`);
  }
  function applyFxBlock(fx) {
    const P = synth.params, set = (k, v) => { if (v != null && !Number.isNaN(v)) P[k] = v; };
    set("masterVol", fx.master_volume != null ? fx.master_volume : fx.balance_master_volume);
    set("transposeSemis", fx.transpose_semis); set("fineCents", fx.fine_cents); set("glideMs", fx.glide_ms); set("humanizeCents", fx.humanize_cents);
    if (fx.env_mode) P.envMode = fx.env_mode; if (fx.harm_follow_env != null) P.harmFollowEnv = !!fx.harm_follow_env; set("decayStretch", fx.decay_stretch); if (fx.attack_curve) P.attackCurve = fx.attack_curve;
    set("attackSampleMix", fx.attack_sample_mix); set("trumpetWaveMix", fx.trumpet_wave_mix); set("sustainSampleMix", fx.sustain_sample_mix); set("drumSampleMix", fx.drum_sample_mix); if (fx.drum_pitch_follow != null) P.drumPitchFollow = !!fx.drum_pitch_follow;
    if (fx.noise_mode) P.noiseMode = fx.noise_mode; set("noiseHpHz", fx.noise_hp_hz); set("noiseLpHz", fx.noise_lp_hz); set("attackNoise", fx.attack_noise); set("breathAmount", fx.breath_amount);
    const r = fx.reverb || {}; set("reverbMix", r.mix); set("reverbSizeSec", r.size_sec); set("reverbDamping", r.damping); set("reverbPreMs", r.pre_ms); set("reverbWidth", r.width);
    const d = fx.drive || {}; set("driveAmount", d.amount); set("driveToneHz", d.tone_hz);
    const bl = fx.brass_layer || {}; set("brassLayerMix", bl.mix); set("brassLayerDetuneCents", bl.detune_cents);
    set("trumpetResonance", fx.trumpet_resonance);
    const ch = fx.chorus || {}; set("chorusMix", ch.mix); set("chorusRateHz", ch.rate_hz); set("chorusDepth", ch.depth); set("chorusWidth", ch.width);
    const fl = fx.filter || {}; if (fl.mode) P.filterMode = fl.mode; set("filterCutoffHz", fl.cutoff_hz); set("filterQ", fl.q); set("filterLfoRateHz", fl.lfo_rate_hz); set("filterLfoDepth", fl.lfo_depth);
    const eq = fx.body_eq || {}; set("eqLowGain", eq.low_gain); set("eqMidFreq", eq.mid_freq); set("eqMidGain", eq.mid_gain); set("eqMidQ", eq.mid_q); set("eqPresGain", eq.presence_gain); set("eqHighGain", eq.high_gain);
    const m = fx.modulation || {};
    set("vibDepthCents", m.vibrato_depth_cents); set("vibRateHz", m.vibrato_rate_hz); set("vibOnsetSec", m.vibrato_onset_sec); if (m.vibrato_shape) P.vibShape = m.vibrato_shape;
    set("tremDepth", m.tremolo_depth); set("tremRateHz", m.tremolo_rate_hz); if (m.tremolo_shape) P.tremShape = m.tremolo_shape;
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
      ["プロファイル", i.instrument_profile_label || i.instrument_profile || "自動"],
      ["ドラム種別", f.drum_type_label || "—"],
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
      box.innerHTML = parts.join("<br>") + `<br><span class="dim">検出値は参考として表示しています。初期再生では揺れを足さず、必要なときだけ「検出値に合わせる」や深さスライダーで付けられます。</span>`;
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
    const num = numEls.harmLimit; if (num) { num.max = maxN; if (+num.value > maxN) num.value = maxN; }
  }

  function applyMetalParams(P, I, strength) {
    strength = strength == null ? 1 : strength;
    const f0 = I && I.fundamental_hz ? +I.fundamental_hz : 440;
    P.brightness = clamp((P.brightness || 0) + 0.22 * strength, -1.5, 1.5);
    P.harmRolloff = clamp((P.harmRolloff || 0) + 0.018 * strength, -0.15, 0.6);
    P.oddEvenBal = clamp((P.oddEvenBal || 0) + 0.10 * strength, -1, 1);
    P.inharmMul = clamp(Math.max(P.inharmMul || 1, 1.18 + 0.28 * strength), 0, 4);
    P.attackNoise = clamp(Math.max(P.attackNoise || 0, 0.18 + 0.20 * strength), 0, 3);
    if (I && I.attack_sample) P.attackSampleMix = clamp(Math.max(P.attackSampleMix || 0, 0.55 + 0.15 * strength), 0, 1.2);
    P.noiseLevel = clamp((P.noiseLevel == null ? 1 : P.noiseLevel) * (0.86 + 0.04 * strength), 0, 3);
    P.noiseHpHz = clamp(Math.max(P.noiseHpHz || 20, 140), 20, 3000);
    P.noiseLpHz = clamp(Math.max(P.noiseLpHz || 12000, 9000), 500, 18000);
    P.driveAmount = clamp(Math.max(P.driveAmount || 0, 0.05 + 0.06 * strength), 0, 1);
    P.driveToneHz = clamp(Math.max(P.driveToneHz || 16000, 12500), 600, 18000);
    if (I && I.instrument_profile === "trumpet") {
      P.trumpetWaveMix = clamp(Math.max(P.trumpetWaveMix || 0, 0.30 + 0.06 * strength), 0, 1);
      P.sustainSampleMix = clamp(Math.max(P.sustainSampleMix || 0, 0.10 + 0.04 * strength), 0, 0.9);
      P.brassLayerMix = clamp(Math.max(P.brassLayerMix || 0, 0.22 + 0.08 * strength), 0, 0.75);
      P.brassLayerDetuneCents = clamp(Math.max(P.brassLayerDetuneCents || 0, 5.5 + 0.8 * strength), 0, 18);
      P.trumpetResonance = clamp(Math.max(P.trumpetResonance || 0, 0.62 + 0.08 * strength), 0, 1);
    }
    P.reverbMix = clamp(Math.max(P.reverbMix || 0, 0.09 + 0.04 * strength), 0, 1);
    P.reverbSizeSec = clamp(Math.max(P.reverbSizeSec || 2.2, 1.35), 0.1, 6);
    P.reverbDamping = clamp(Math.min(P.reverbDamping == null ? 0.35 : P.reverbDamping, 0.32), 0, 0.98);
    P.eqLowGain = clamp((P.eqLowGain || 0) - 1.8 * strength, -15, 15);
    P.eqMidFreq = clamp(f0 < 220 ? 720 : 980, 150, 6000);
    P.eqMidGain = clamp((P.eqMidGain || 0) - 1.4 * strength, -15, 15);
    P.eqMidQ = clamp(Math.max(P.eqMidQ || 1, 1.2), 0.3, 8);
    P.eqPresGain = clamp((P.eqPresGain || 0) + 2.8 * strength, -15, 15);
    P.eqHighGain = clamp((P.eqHighGain || 0) + 1.2 * strength, -15, 15);
    P.filterMode = "off";
    if ((P.releaseMs || 0) < 260) P.releaseMs = 260;
    return P;
  }
  function applyDrumParams(P, I, strength) {
    strength = strength == null ? 1 : strength;
    const guess = I && I.features && I.features.drum_type_guess || "drum";
    P.envMode = "recorded";
    P.attackCurve = "exp";
    P.attackMs = clamp(Math.min(P.attackMs || 8, 8), 1, 2000);
    P.sustainLvl = 0.02;
    P.drumSampleMix = clamp(Math.max(P.drumSampleMix || 0, 1.0), 0, 1.2);
    P.attackSampleMix = 0;
    P.attackNoise = 0;
    P.noiseMode = "recorded";
    const isCymbal = guess === "crash" || guess === "hihat" || guess === "cymbal";
    const isPlainDrumSample = guess === "kick" || guess === "hihat";
    P.noiseLevel = clamp(Math.max(P.noiseLevel || 0, isPlainDrumSample ? 0 : isCymbal ? 0.08 : 0.06), 0, 3);
    P.harmFollowEnv = false;
    P.harmonicGainTrim = isPlainDrumSample ? 0 : 0.12;
    P.inharmMul = 1;
    P.driveAmount = clamp(Math.max(P.driveAmount || 0, isPlainDrumSample ? 0 : 0.035), 0, 1);
    P.reverbMix = clamp(Math.max(P.reverbMix || 0, isPlainDrumSample ? 0 : isCymbal ? 0.05 : 0.02), 0, 1);
    if (guess === "kick") {
      P.decayMs = clamp(Math.max(P.decayMs || 0, 180), 1, 3000);
      P.releaseMs = clamp(Math.max(P.releaseMs || 0, 120), 5, 4000);
      P.noiseHpHz = 35; P.noiseLpHz = 5200;
      P.eqLowGain = 0;
      P.eqMidFreq = 180; P.eqMidGain = 0;
      P.eqPresGain = 0;
      P.eqHighGain = 0;
    } else if (isCymbal) {
      P.decayMs = clamp(Math.max(P.decayMs || 0, 900), 1, 3000);
      P.releaseMs = clamp(Math.max(P.releaseMs || 0, guess === "hihat" ? 500 : 1500), 5, 4000);
      P.noiseHpHz = 900; P.noiseLpHz = 18000;
      P.brightness = guess === "hihat" ? 0 : clamp(Math.max(P.brightness || 0, 0.1), -1.5, 1.5);
      P.harmRolloff = guess === "hihat" ? 0 : clamp(Math.max(P.harmRolloff || 0, 0.02), -0.15, 0.6);
      P.eqLowGain = guess === "hihat" ? 0 : clamp(Math.min(P.eqLowGain || 0, -4.0), -15, 15);
      P.eqMidFreq = 4200; P.eqMidGain = guess === "hihat" ? 0 : clamp(Math.max(P.eqMidGain || 0, 0.6), -15, 15);
      P.eqPresGain = guess === "hihat" ? 0 : clamp(Math.max(P.eqPresGain || 0, 2.0), -15, 15);
      P.eqHighGain = guess === "hihat" ? 0 : clamp(Math.max(P.eqHighGain || 0, 2.0), -15, 15);
    } else {
      P.decayMs = clamp(Math.max(P.decayMs || 0, 320), 1, 3000);
      P.releaseMs = clamp(Math.max(P.releaseMs || 0, 260), 5, 4000);
      P.noiseHpHz = 120; P.noiseLpHz = 14500;
      P.eqLowGain = clamp(Math.max(P.eqLowGain || 0, 0.5), -15, 15);
      P.eqMidFreq = 950; P.eqMidGain = clamp(Math.max(P.eqMidGain || 0, 1.8), -15, 15);
      P.eqPresGain = clamp(Math.max(P.eqPresGain || 0, 2.0), -15, 15);
      P.eqHighGain = clamp(Math.max(P.eqHighGain || 0, 1.2), -15, 15);
    }
    return P;
  }
  function applyStringParams(P, I, strength, tone) {
    strength = strength == null ? 1 : strength;
    tone = tone || "natural";
    const f0 = I && I.fundamental_hz ? +I.fundamental_hz : 440;
    const soft = tone === "soft";
    const bright = tone === "bright";
    const clean = tone === "clean";
    const bowed = tone === "bowed";
    const rosin = tone === "rosin";

    P.envMode = "adsr";
    P.attackCurve = "lin";
    P.attackMs = clamp(Math.max(P.attackMs || 0, soft ? 95 : rosin ? 90 : bowed ? 76 : 60), 1, 2000);
    P.decayMs = clamp(Math.max(P.decayMs || 0, soft ? 270 : rosin ? 300 : bowed ? 250 : 190), 1, 3000);
    P.sustainLvl = clamp(Math.max(P.sustainLvl == null ? 0.72 : P.sustainLvl, soft ? 0.78 : rosin ? 0.80 : bowed ? 0.76 : 0.72), 0, 1);
    P.releaseMs = clamp(Math.max(P.releaseMs || 0, soft ? 760 : rosin ? 920 : bowed ? 720 : 560), 5, 4000);

    P.brightness = clamp(bright ? 0.10 : soft ? -0.20 : rosin ? 0.02 : bowed ? -0.02 : -0.10, -1.5, 1.5);
    P.harmRolloff = clamp(bright ? 0.012 : soft ? 0.075 : rosin ? 0.022 : bowed ? 0.032 : 0.052, -0.15, 0.6);
    P.oddEvenBal = clamp(soft ? -0.12 : rosin ? 0.08 : bowed ? 0.04 : -0.05, -1, 1);
    P.inharmMul = clamp(clean ? 0.22 : rosin ? 0.62 : bowed ? 0.52 : 0.38, 0, 4);
    P.harmFollowEnv = rosin;

    if (I && I.attack_sample) P.attackSampleMix = clamp(clean ? 0.14 : soft ? 0.26 : rosin ? 0.68 : bowed ? 0.52 : 0.36, 0, 1.2);
    if (I && I.sustain_sample) P.sustainSampleMix = clamp(soft ? 0.28 : rosin ? 0.52 : bowed ? 0.40 : 0.24, 0, 0.9);
    P.trumpetWaveMix = 0;
    P.brassLayerMix = 0;
    P.brassLayerDetuneCents = 0;
    P.trumpetResonance = 0;

    P.noiseMode = "recorded";
    P.noiseLevel = clamp(clean ? 0.05 : soft ? 0.12 : rosin ? 0.42 : bowed ? 0.30 : 0.18, 0, 3);
    P.attackNoise = clamp(clean ? 0.10 : soft ? 0.22 : rosin ? 0.95 : bowed ? 0.70 : 0.36, 0, 3);
    P.noiseHpHz = clamp(rosin ? 650 : bowed ? 540 : Math.max(P.noiseHpHz || 20, 420), 20, 3000);
    P.noiseLpHz = clamp(bright ? 11000 : rosin ? 12000 : bowed ? 9800 : 8400, 500, 18000);
    P.breathAmount = 0;

    P.vibDepthCents = clamp(Math.max(P.vibDepthCents || 0, soft ? 12 : rosin ? 26 : bowed ? 22 : 16), 0, 120);
    P.vibRateHz = clamp(Math.max(P.vibRateHz || 0, rosin ? 5.9 : bowed ? 5.6 : 5.2), 0.1, 12);
    P.vibOnsetSec = clamp(Math.max(P.vibOnsetSec || 0, rosin ? 0.08 : bowed ? 0.12 : 0.18), 0, 2);
    P.vibShape = "sine";

    P.chorusMix = clamp(Math.max(P.chorusMix || 0, soft ? 0.14 : rosin ? 0.24 : bowed ? 0.18 : 0.10), 0, 1);
    P.chorusRateHz = clamp(rosin ? 0.18 : 0.22, 0.05, 3);
    P.chorusDepth = clamp(soft ? 0.42 : rosin ? 0.62 : bowed ? 0.52 : 0.34, 0, 1);
    P.chorusWidth = clamp(rosin ? 0.82 : 0.70, 0, 1);
    P.reverbMix = clamp(Math.max(P.reverbMix || 0, soft ? 0.16 : rosin ? 0.18 : bowed ? 0.15 : 0.12), 0, 1);
    P.reverbSizeSec = clamp(Math.max(P.reverbSizeSec || 2.2, 2.4), 0.1, 6);
    P.reverbDamping = clamp(Math.max(P.reverbDamping == null ? 0.35 : P.reverbDamping, 0.42), 0, 0.98);

    P.driveAmount = clamp(bright ? 0.025 : rosin ? 0.035 : bowed ? 0.022 : 0.01, 0, 1);
    P.driveToneHz = clamp(bright ? 15000 : rosin ? 14500 : bowed ? 13000 : 11500, 600, 18000);
    P.eqLowGain = clamp((f0 < 260 ? 1.0 : 0.3) + (soft ? 0.7 : rosin ? 0.45 : bowed ? 0.35 : 0), -15, 15);
    P.eqMidFreq = clamp(f0 < 330 ? 420 : rosin ? 620 : 540, 150, 6000);
    P.eqMidGain = clamp(soft ? 1.7 : rosin ? 2.8 : bowed ? 2.4 : 1.4, -15, 15);
    P.eqMidQ = clamp(rosin ? 1.2 : 1.0, 0.3, 8);
    P.eqPresGain = clamp(bright ? 2.6 : soft ? 0.7 : rosin ? 3.8 : bowed ? 2.7 : 1.7, -15, 15);
    P.eqHighGain = clamp(bright ? 1.2 : soft ? -1.0 : rosin ? 0.8 : bowed ? 0.25 : -0.4, -15, 15);
    P.filterMode = "off";
    return P;
  }
  function applyMetalQualityPreset() {
    if (!instrument) return;
    beginPresetCompare();
    applyMetalParams(synth.params, instrument, 1);
    syncControlsFromParams();
    if (synth.ctx) synth.applyAll();
    if (synth.drone) synth.setDrone(true, curNote);
    finishPresetCompare("金属楽器向け");
    setStatus("金属楽器向けのクオリティ向上を適用しました。鳴らしながら微調整できます。");
  }
  function applyDrumPunchPreset() {
    if (!instrument) return;
    beginPresetCompare();
    applyDrumParams(synth.params, instrument, 1);
    syncControlsFromParams();
    if (synth.ctx) synth.applyAll();
    if (synth.drone) synth.setDrone(true, curNote);
    const lab = instrument.features && instrument.features.drum_type_label || "ドラム";
    finishPresetCompare(`${lab}向け`);
    setStatus(`${lab} 向けにアタック・胴鳴り・ノイズ包絡を整えました。`);
  }
  function applyStringQualityPreset() {
    applyStringPreset("natural");
  }
  function applyStringPreset(kind) {
    if (!instrument) return;
    beginPresetCompare();
    applyStringParams(synth.params, instrument, 1, kind);
    syncControlsFromParams();
    if (synth.ctx) synth.applyAll();
    if (synth.drone) synth.setDrone(true, curNote);
    const labels = { natural: "ヴァイオリン向け", bowed: "弦らしさ強め", rosin: "弓感最大", soft: "やわらかめ", bright: "明るめ", clean: "弓ノイズ控えめ" };
    finishPresetCompare(labels[kind] || labels.natural);
    setStatus(`弦楽器調整プリセット「${labels[kind] || labels.natural}」を適用しました。A/Bで前後を比較できます。`);
  }
  function applyTrumpetPreset(kind) {
    if (!instrument) return;
    beginPresetCompare();
    const P = synth.params;
    const root = instrument.fundamental_hz || 440;
    const set = (k, v) => { P[k] = v; };
    const presets = {
      natural: {
        label: "原音に近い",
        values: {
          brightness: 0.18, harmRolloff: -0.006, driveAmount: 0.025,
          attackSampleMix: 0.62, trumpetWaveMix: 0.30, sustainSampleMix: 0.10,
          brassLayerMix: 0.22, brassLayerDetuneCents: 5.0, trumpetResonance: 0.58,
          eqLowGain: -1.4, eqMidFreq: root < 330 ? 720 : 820, eqMidGain: -0.8, eqMidQ: 1.2,
          eqPresGain: 2.8, eqHighGain: 1.8, noiseLevel: 0, attackNoise: 0,
        },
      },
      bright: {
        label: "明るく抜ける",
        values: {
          brightness: 0.36, harmRolloff: -0.02, driveAmount: 0.045,
          attackSampleMix: 0.75, trumpetWaveMix: 0.36, sustainSampleMix: 0.14,
          brassLayerMix: 0.32, brassLayerDetuneCents: 6.5, trumpetResonance: 0.70,
          eqLowGain: -2.5, eqMidFreq: 760, eqMidGain: -1.5, eqMidQ: 1.35,
          eqPresGain: 4.0, eqHighGain: 3.0, noiseLevel: 0, attackNoise: 0,
        },
      },
      thick: {
        label: "太く厚く",
        values: {
          brightness: 0.16, harmRolloff: 0.002, driveAmount: 0.055,
          attackSampleMix: 0.72, trumpetWaveMix: 0.38, sustainSampleMix: 0.16,
          brassLayerMix: 0.36, brassLayerDetuneCents: 6.5, trumpetResonance: 0.74,
          eqLowGain: -0.8, eqMidFreq: 680, eqMidGain: -0.6, eqMidQ: 1.15,
          eqPresGain: 3.0, eqHighGain: 1.6, noiseLevel: 0, attackNoise: 0,
        },
      },
      clean: {
        label: "ノイズ控えめ",
        values: {
          brightness: 0.20, harmRolloff: -0.004, driveAmount: 0.015,
          attackSampleMix: 0.55, trumpetWaveMix: 0.24, sustainSampleMix: 0.05,
          brassLayerMix: 0.18, brassLayerDetuneCents: 4.5, trumpetResonance: 0.50,
          eqLowGain: -2.0, eqMidFreq: 820, eqMidGain: -1.0, eqMidQ: 1.25,
          eqPresGain: 2.4, eqHighGain: 1.7, noiseLevel: 0, attackNoise: 0,
        },
      },
      layer: {
        label: "金管レイヤー強め",
        values: {
          brightness: 0.26, harmRolloff: -0.012, driveAmount: 0.045,
          attackSampleMix: 0.70, trumpetWaveMix: 0.34, sustainSampleMix: 0.14,
          brassLayerMix: 0.48, brassLayerDetuneCents: 8.5, trumpetResonance: 0.78,
          eqLowGain: -1.8, eqMidFreq: 780, eqMidGain: -1.2, eqMidQ: 1.35,
          eqPresGain: 3.6, eqHighGain: 2.4, noiseLevel: 0, attackNoise: 0,
        },
      },
    };
    const preset = presets[kind] || presets.natural;
    for (const k in preset.values) set(k, preset.values[k]);
    P.driveToneHz = 18000;
    P.harmFollowEnv = false;
    syncControlsFromParams();
    if (synth.ctx) synth.applyAll();
    if (synth.drone) synth.setDrone(true, curNote);
    finishPresetCompare(preset.label);
    setStatus(`トランペット調整プリセット「${preset.label}」を適用しました。A/Bで前後を比較できます。`);
  }
  function applyTrumpetClarityPreset() {
    applyTrumpetPreset("bright");
  }
  function applyMetalAttackPreset() {
    beginPresetCompare();
    setParam("attackNoise", clamp(Math.max(synth.params.attackNoise || 0, 0.75), 0, 3));
    setParam("attackMs", clamp(Math.min(synth.params.attackMs || 20, 18), 1, 2000));
    setParam("driveAmount", clamp(Math.max(synth.params.driveAmount || 0, 0.12), 0, 1));
    finishPresetCompare("アタック強め");
    setStatus("金属楽器の立ち上がりを強めました。");
  }
  function softenMetalPreset() {
    beginPresetCompare();
    setParam("brightness", clamp((synth.params.brightness || 0) - 0.18, -1.5, 1.5));
    setParam("eqPresGain", clamp((synth.params.eqPresGain || 0) - 1.5, -15, 15));
    setParam("driveAmount", clamp((synth.params.driveAmount || 0) * 0.65, 0, 1));
    finishPresetCompare("明るさ控えめ");
    setStatus("明るさと歪みを少し戻しました。");
  }

  function makeBatchTrack(file, I) {
    const tmp = new SL.LiveSynth();
    tmp.load(I);
    const filenameNote = midiFromFilename(file.name);
    return { file, instrument: I, params: deepCopy(tmp.params), volume: 0.6, note: filenameNote || I.midi_note || 60 };
  }
  function midiFromFilename(name) {
    const m = String(name || "").match(/(?:^|[_\-\s])([A-Ga-g])([#b♯♭]?)(-?\d)(?=\.|[_\-\s]|$)/);
    if (!m) return null;
    const pc0 = NOTE_PC[m[1].toUpperCase()];
    if (pc0 == null) return null;
    const acc = m[2];
    const pc = pc0 + (acc === "#" || acc === "♯" ? 1 : acc === "b" || acc === "♭" ? -1 : 0);
    const oct = parseInt(m[3], 10);
    return clamp((oct + 1) * 12 + pc, 0, 127);
  }
  function applyMetalToBatch() {
    for (const t of batch.tracks) if (!t.error) applyMetalParams(t.params, t.instrument, 0.95);
    batch.metalApplied = true;
  }
  function autoBalanceBatch() {
    const ok = batch.tracks.filter((t) => !t.error);
    const peaks = ok.map((t) => +(t.instrument.features && t.instrument.features.rms_peak || 0.25)).filter((v) => v > 0);
    if (!peaks.length) return;
    peaks.sort((a, b) => a - b);
    const target = peaks[Math.floor(peaks.length / 2)] || 0.25;
    for (const t of ok) {
      const peak = +(t.instrument.features && t.instrument.features.rms_peak || target);
      t.volume = +clamp(0.6 * target / Math.max(peak, 0.03), 0.25, 1.1).toFixed(2);
      t.params.masterVol = t.volume;
    }
  }
  function renderBatchList() {
    const box = $("#batchList"); if (!box) return;
    const rows = [];
    const files = batch.tracks.length ? batch.tracks : batch.files.map((file) => ({ file, pending: true, volume: 0.6 }));
    for (let i = 0; i < files.length; i++) {
      const t = files[i], I = t.instrument;
      const card = el("div", { class: "batch-track " + (t.error ? "err" : I ? "ready" : "pending") });
      card.appendChild(el("div", { class: "name", title: t.file.name, text: `${i + 1}. ${t.file.name}` }));
      if (t.error) {
        card.appendChild(el("div", { class: "meta", text: "解析エラー: " + t.error }));
      } else if (I) {
        const hc = I.features && I.features.harmonic_count != null ? I.features.harmonic_count : (I.harmonics || []).length;
        const mapped = t.note != null ? SL.midiName(t.note) : (I.note_name || "?");
        card.appendChild(el("div", { class: "meta", html: `パック音程 ${mapped} / 解析 ${I.note_name} / ${I.fundamental_hz} Hz<br>倍音 ${hc} 本 / RMS ${I.features && I.features.rms_peak != null ? I.features.rms_peak : "?"}` }));
        const val = el("span", { class: "volval", text: Math.round(t.volume * 100) + "%" });
        const inp = el("input", { type: "range", min: "0", max: "1.2", step: "0.01", value: t.volume });
        inp.addEventListener("input", () => { t.volume = +inp.value; t.params.masterVol = t.volume; val.textContent = Math.round(t.volume * 100) + "%"; });
        card.appendChild(el("label", null, [document.createTextNode("音量 "), val]));
        card.appendChild(inp);
      } else {
        card.appendChild(el("div", { class: "meta", text: "解析待ち" }));
      }
      rows.push(card);
    }
    box.innerHTML = ""; rows.forEach((r) => box.appendChild(r));
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
    const num = el("input", { type: "number", id: id + "_num", class: "numctl", min: c.min, max: c.max, step: c.step, inputmode: "decimal" });
    const valEl = el("span", { class: "fldval" });
    const applyValue = (v, source, clampNow) => {
      if (!Number.isFinite(v)) return;
      const next = clamp(v, +c.min, +c.max);
      setParam(c.key, next, true);
      valEl.textContent = c.fmt(next);
      if (source !== "range") inp.value = next;
      if (source !== "number") num.value = rawNumberText(c, next);
    };
    inp.addEventListener("input", () => applyValue(+inp.value, "range", false));
    num.addEventListener("input", () => {
      if (num.value === "") return;
      applyValue(+num.value, "number", false);
    });
    num.addEventListener("change", () => {
      const fallback = synth.params[c.key] == null ? c.min : synth.params[c.key];
      const next = clamp(Number.isFinite(+num.value) ? +num.value : +fallback, +c.min, +c.max);
      num.value = rawNumberText(c, next);
      applyValue(next, "number", true);
    });
    ctlEls[c.key] = inp; numEls[c.key] = num;
    valEls[c.key] = (v) => { valEl.textContent = c.fmt(v); num.value = rawNumberText(c, v); };
    c._valEl = valEl; c._fmt = c.fmt; c._numEl = num;
    return el("div", { class: "fld", "data-key": c.key }, [
      el("label", { for: id }, [document.createTextNode(c.label + "  "), valEl]),
      el("div", { class: "range-row" }, [inp, num]),
    ]);
  }
  function buildSelect(c) {
    const id = "ctl_" + c.key;
    const sel = el("select", { id: id });
    for (const [val, lab] of c.options) sel.appendChild(el("option", { value: val }, lab));
    sel.addEventListener("change", () => setParam(c.key, sel.value, true));
    ctlEls[c.key] = sel;
    return el("div", { class: "fld", "data-key": c.key }, [el("label", { for: id }, c.label), sel]);
  }
  function buildCheck(c) {
    const id = "ctl_" + c.key;
    const inp = el("input", { type: "checkbox", id: id });
    inp.addEventListener("change", () => setParam(c.key, inp.checked, true));
    ctlEls[c.key] = inp;
    return el("label", { class: "fld check", for: id, "data-key": c.key }, [inp, document.createTextNode(" " + c.label)]);
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
      if (numEls[c.key]) numEls[c.key].value = rawNumberText(c, P[c.key]);
      if (c.fmt && c._valEl) c._valEl.textContent = c.fmt(+P[c.key]);
    }
    // 反映先（鳴っている音）にも一度流す
    if (synth.ctx) synth.applyAll();
    const transportVolume = $("#tVol");
    if (transportVolume) transportVolume.value = P.masterVol;
    drawEnvEdit(); drawHarmEdit();
    renderCompatibilitySummary();
  }
  function setParam(key, value, fromUi) {
    const adsrKeys = ["attackMs", "decayMs", "sustainLvl", "attackCurve"];
    if (fromUi && adsrKeys.indexOf(key) >= 0 && synth.params.envMode !== "adsr") {
      synth.set("envMode", "adsr");
      const envSel = ctlEls.envMode;
      if (envSel) envSel.value = "adsr";
    }
    synth.set(key, value);
    if (!fromUi) { // プログラムから変えた場合は UI も更新
      const inp = ctlEls[key];
      if (inp) { if (inp.type === "checkbox") inp.checked = !!value; else inp.value = value; }
      const c = findControl(key);
      if (c && numEls[key]) numEls[key].value = rawNumberText(c, value);
      if (valEls[key]) valEls[key](+value);
    }
    if (key === "masterVol") { const tv = $("#tVol"); if (tv && +tv.value !== +value) tv.value = value; }
    if (["envMode", "attackMs", "decayMs", "sustainLvl", "releaseMs", "attackCurve", "decayStretch"].indexOf(key) >= 0) {
      drawEnvEdit();
      if (synth.drone && ["attackMs", "decayMs", "sustainLvl", "releaseMs", "attackCurve", "decayStretch"].indexOf(key) >= 0) synth.setDrone(true, curNote);
    }
    if (["brightness", "harmRolloff", "oddEvenBal", "harmLimit"].indexOf(key) >= 0) drawHarmEdit();
    if (workspaceMode === "compat") renderCompatibilitySummary();
  }
  function resetSection(sec) {
    synth.resetSection(sec.keys.slice());
    if (sec.id === "harm") synth.params.harmGains = {};
    if (workspaceMode === "compat" && sec.id === "harm") {
      synth.params.brightness = 0;
      synth.params.harmRolloff = 0;
      synth.params.oddEvenBal = 0;
      synth.params.inharmMul = 1;
      const ns = (instrument.harmonics || []).filter((h) => h.amp > 0).map((h) => h.n);
      synth.params.harmLimit = ns.length ? Math.max.apply(null, ns) : 1;
    }
    if (workspaceMode === "compat") applyTestMultiCompatibility(false);
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
  let compatAuditionRun = 0;
  async function playCompatAudition(notes) {
    await ensureAudio();
    const run = ++compatAuditionRun;
    synth.panic(); heldByEvent.clear(); refreshKeyHighlights();
    for (const midi of notes) {
      if (run !== compatAuditionRun || workspaceMode !== "compat") return;
      curNote = midi;
      $("#curNoteLbl").textContent = SL.midiName(midi) + " (" + midi + ")";
      synth.noteOn(midi, 0.92);
      refreshKeyHighlights();
      await new Promise((resolve) => setTimeout(resolve, 560));
      synth.noteOff(midi);
      await new Promise((resolve) => setTimeout(resolve, 130));
    }
  }

  function exportTestMultiInstrument() {
    const target = $("#compatTarget").value;
    const out = SL.toTestMultiInstrument(synth.exportInstrument(), target);
    const filename = target === "horn"
      ? "1_horns.tweaked.instrument.json"
      : "0_trumpets.tweaked.instrument.json";
    return { out, filename, errors: validateTestMultiInstrument(out) };
  }

  function validateTestMultiInstrument(out) {
    const errors = [], env = out && out.envelope, hs = out && out.harmonics;
    if (!env || !Array.isArray(env.values) || env.values.length < 2) errors.push("envelope.valuesがありません");
    for (const key of ["attack_sec", "decay_sec", "sustain_level", "release_sec"])
      if (!env || !Number.isFinite(+env[key])) errors.push(`envelope.${key}が数値ではありません`);
    if (!Array.isArray(hs) || !hs.length) errors.push("harmonicsが空です");
    else hs.forEach((h, i) => {
      if (![h.n, h.ratio, h.amp].every((v) => Number.isFinite(+v))) errors.push(`harmonics[${i}]の値が不正です`);
      if (!Array.isArray(h.env) || h.env.length < 2) errors.push(`harmonics[${i}].envがありません`);
    });
    if (!out.noise || !Array.isArray(out.noise.bands_hz) || !Array.isArray(out.noise.band_levels)) errors.push("noiseの帯域情報がありません");
    if (!out.fx || !out.fx.body_eq) errors.push("fx.body_eqがありません");
    if (!out.test_multi_compat || out.test_multi_compat.version !== 2) errors.push("test_multi_compat.versionが2ではありません");
    return errors;
  }

  function wireTransport() {
    $("#octDown").addEventListener("click", () => shiftOctave(-1));
    $("#octUp").addEventListener("click", () => shiftOctave(+1));
    $("#droneBtn").addEventListener("click", async () => { await ensureAudio(); const on = !synth.drone; synth.setDrone(on, curNote); $("#droneBtn").classList.toggle("active", on); refreshKeyHighlights(); });
    $("#latchBtn").addEventListener("click", () => { latch = !latch; $("#latchBtn").classList.toggle("active", latch); if (!latch) { /* ラッチ解除時は鳴っているものは残す */ } });
    $("#panicBtn").addEventListener("click", () => { compatAuditionRun++; synth.panic(); synth.setDrone(false); $("#droneBtn").classList.remove("active"); heldByEvent.clear(); refreshKeyHighlights(); });
    $("#playOrigBtn").addEventListener("click", async () => { await ensureAudio(); if (synth.origNode) { synth.stopOriginal(); $("#playOrigBtn").textContent = "🔊 原音を再生"; } else if (synth.origBuffer) { synth.playOriginal(false); $("#playOrigBtn").textContent = "■ 原音停止"; const b = synth.origBuffer; setTimeout(() => { if (!synth.origNode) $("#playOrigBtn").textContent = "🔊 原音を再生"; }, (b.duration + 0.2) * 1000); } });
    // マスター音量(トランスポート側) ↔ perf セクションのスライダーを同期
    $("#tVol").addEventListener("input", () => { const v = +$("#tVol").value; setParam("masterVol", v); });
    $("#qualityBtn").addEventListener("click", async () => { await ensureAudio(); applyMetalQualityPreset(); });
    $("#stringQualityBtn").addEventListener("click", async () => { await ensureAudio(); applyStringQualityPreset(); });
    $("#abSaveA").addEventListener("click", () => saveCompareSlot("A"));
    $("#abSaveB").addEventListener("click", () => saveCompareSlot("B"));
    $("#abApplyA").addEventListener("click", () => applyCompareSlot("A"));
    $("#abApplyB").addEventListener("click", () => applyCompareSlot("B"));
    $("#abToggleBtn").addEventListener("click", () => toggleCompareSlot());
    $("#compatTrumpetAudition").addEventListener("click", () => playCompatAudition([72, 76, 79, 81]));
    $("#compatHornAudition").addEventListener("click", () => playCompatAudition([60, 64, 67, 69]));
    $("#compatTarget").addEventListener("change", renderCompatibilitySummary);
    // 書き出し
    $("#dlJsonBtn").addEventListener("click", () => {
      if (workspaceMode === "compat") {
        const result = exportTestMultiInstrument();
        if (result.errors.length) {
          setStatus("JSONを書き出せません: " + result.errors.join(" / "), true);
          return;
        }
        const blob = new Blob([JSON.stringify(result.out, null, 1)], { type: "application/json" });
        downloadBlob(blob, result.filename);
        setStatus(result.filename + " をダウンロードしました。手動配置する場合は改善版の data/ に置いて再起動してください。");
      } else {
        const I = synth.exportInstrument();
        const blob = new Blob([JSON.stringify(I, null, 1)], { type: "application/json" });
        downloadBlob(blob, safeName(instrument.name) + ".tweaked.instrument.json");
        setStatus("調整後のインストゥルメント JSON を書き出しました（Processing の data/ に置けば使えます）");
      }
    });
    $("#dlWavBtn").addEventListener("click", async () => {
      await ensureAudio();
      $("#dlWavBtn").disabled = true; const old = $("#dlWavBtn").textContent; $("#dlWavBtn").textContent = "書き出し中…";
      try {
        const dur = clamp(+$("#wavDur").value || 2.5, 0.3, 12);
        const buf = await synth.renderWav(curNote, dur);
        downloadBlob(buf, safeName(instrument.name) + "_" + SL.midiName(curNote) + ".wav");
        setStatus(`WAV を書き出しました（${SL.midiName(curNote)} / ${dur.toFixed(1)} s）`);
      } catch (e) { setStatus("WAV 書き出しに失敗しました: " + e.message, true); }
      $("#dlWavBtn").textContent = old; $("#dlWavBtn").disabled = false;
    });
    $("#resetAllBtn").addEventListener("click", () => { synth.resetAll(); if (workspaceMode === "compat") applyTestMultiCompatibility(true); syncControlsFromParams(); setHarmLimitMax(); if (synth.drone) synth.setDrone(true, curNote); });
    $("#reAnalyzeBtn").addEventListener("click", () => { if (pickedFile) analyze(); else setStatus("再解析するには音源ファイルから始めてください。", true); });
  }

  function adjustedBatchInstrument(t) {
    const tmp = new SL.LiveSynth();
    tmp.load(t.instrument);
    tmp.params = deepCopy(t.params);
    tmp.params.masterVol = t.volume;
    const json = tmp.exportInstrument();
    json.fx = json.fx || {};
    json.fx.balance_master_volume = +t.volume.toFixed(3);
    json.fx.balance_export_note = SL.midiName(t.note || t.instrument.midi_note || 60);
    return json;
  }

  function batchReadyTracks() {
    return batch.tracks
      .filter((t) => !t.error)
      .slice()
      .sort((a, b) => (a.note || a.instrument.midi_note || 0) - (b.note || b.instrument.midi_note || 0));
  }

  function finiteNumbers(values) {
    return (values || []).filter((v) => v != null && v !== "").map((v) => +v).filter((v) => Number.isFinite(v));
  }

  function average(values, fallback) {
    const nums = finiteNumbers(values);
    if (!nums.length) return fallback == null ? 0 : fallback;
    return nums.reduce((s, v) => s + v, 0) / nums.length;
  }

  function resampleNumeric(values, n, fallback) {
    const src = finiteNumbers(values);
    const out = new Array(Math.max(1, n | 0));
    if (!src.length) return out.fill(fallback == null ? 0 : fallback);
    if (src.length === 1 || out.length === 1) return out.fill(src[0]);
    const scale = (src.length - 1) / (out.length - 1);
    for (let i = 0; i < out.length; i++) {
      const x = i * scale;
      const j = Math.floor(x);
      const f = x - j;
      out[i] = src[j] * (1 - f) + src[Math.min(src.length - 1, j + 1)] * f;
    }
    return out;
  }

  function roundList(values, digits) {
    const mul = Math.pow(10, digits == null ? 5 : digits);
    return (values || []).map((v) => Math.round((Number.isFinite(+v) ? +v : 0) * mul) / mul);
  }

  function normalizePeak(values, peak, absMode) {
    const nums = finiteNumbers(values);
    if (!nums.length) return [];
    const mx = nums.reduce((m, v) => Math.max(m, absMode ? Math.abs(v) : v), 0);
    if (mx <= 1e-9) return nums.map(() => 0);
    const scale = (peak == null ? 1 : peak) / mx;
    return nums.map((v) => v * scale);
  }

  function representativeHarmonics(instruments) {
    const maxN = Math.max(1, Math.min(96, ...instruments.map((I) => Math.max(0, ...(I.harmonics || []).map((h) => h.n || 0)))));
    const harmonics = [];
    for (let n = 1; n <= maxN; n++) {
      const present = instruments.map((I) => (I.harmonics || []).find((h) => h.n === n) || null);
      const avgAmp = average(present.map((h) => h ? h.amp : 0), 0);
      if (avgAmp <= 0.00002) continue;
      const ratio = average(present.map((h) => h ? h.ratio : null), n);
      const phase = average(present.map((h) => h ? h.phase : null), 0);
      const env = new Array(32).fill(0);
      for (const h of present) {
        const hv = h ? resampleNumeric(h.env || [1], 32, 0) : new Array(32).fill(0);
        for (let i = 0; i < env.length; i++) env[i] += hv[i] / instruments.length;
      }
      harmonics.push({ n, ratio, amp: avgAmp, phase, env });
    }
    const mx = Math.max(1e-9, ...harmonics.map((h) => h.amp));
    return harmonics.map((h) => {
      const amp = h.amp / mx;
      return {
        n: h.n,
        ratio: +h.ratio.toFixed(5),
        amp: +amp.toFixed(5),
        amp_db: +(20 * Math.log10(amp + 1e-9)).toFixed(2),
        phase: +h.phase.toFixed(5),
        env: roundList(h.env, 5),
      };
    });
  }

  function representativeEnvelope(instruments) {
    const rate = 200;
    const durations = instruments.map((I) => I.duration_sec || (I.envelope && I.envelope.values && I.envelope.rate_hz ? (I.envelope.values.length - 1) / I.envelope.rate_hz : 2.0));
    const duration = clamp(average(durations, 2.0), 0.3, 12);
    const len = clamp(Math.round(duration * rate) + 1, 80, 1600);
    const values = new Array(len).fill(0);
    for (const I of instruments) {
      const e = I.envelope || {};
      const ev = resampleNumeric(e.values || [0, 1, e.sustain_level || 0.7, 0], len, 0);
      for (let i = 0; i < len; i++) values[i] += ev[i] / instruments.length;
    }
    const norm = normalizePeak(values, 1, false);
    const loopStart = clamp(average(instruments.map((I) => I.envelope && I.envelope.loop_start_sec), duration * 0.28), 0, duration * 0.95);
    const loopEnd = clamp(average(instruments.map((I) => I.envelope && I.envelope.loop_end_sec), duration * 0.72), loopStart + 0.02, duration);
    return {
      rate_hz: rate,
      values: roundList(norm, 5),
      attack_sec: +average(instruments.map((I) => I.envelope && I.envelope.attack_sec), 0.03).toFixed(4),
      decay_sec: +average(instruments.map((I) => I.envelope && I.envelope.decay_sec), 0.18).toFixed(4),
      sustain_level: +clamp(average(instruments.map((I) => I.envelope && I.envelope.sustain_level), 0.7), 0, 1).toFixed(4),
      release_sec: +average(instruments.map((I) => I.envelope && I.envelope.release_sec), 0.2).toFixed(4),
      loop_start_sec: +loopStart.toFixed(4),
      loop_end_sec: +loopEnd.toFixed(4),
    };
  }

  function representativeNoise(instruments) {
    const noises = instruments.map((I) => I.noise || {});
    const envLen = 64;
    const envelope = new Array(envLen).fill(0);
    for (const n of noises) {
      const ev = resampleNumeric(n.envelope || [1, 0.4], envLen, 0);
      for (let i = 0; i < envLen; i++) envelope[i] += ev[i] / noises.length;
    }
    const maxBands = Math.max(2, ...noises.map((n) => (n.band_levels || []).length));
    const refBands = (noises.find((n) => (n.bands_hz || []).length === maxBands) || noises[0] || {}).bands_hz || [0, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, 22050];
    const bandLevels = new Array(maxBands).fill(0);
    for (const n of noises) {
      const lv = resampleNumeric(n.band_levels || [0], maxBands, 0);
      for (let i = 0; i < maxBands; i++) bandLevels[i] += lv[i] / noises.length;
    }
    return {
      level: +clamp(average(noises.map((n) => n.level), 0), 0, 1).toFixed(4),
      rate_hz: 200,
      envelope: roundList(normalizePeak(envelope, 1, false), 5),
      bands_hz: roundList(resampleNumeric(refBands, maxBands, 0), 1),
      band_levels: roundList(normalizePeak(bandLevels, 1, false), 5),
    };
  }

  function representativeWaveform(instruments) {
    const len = 1024;
    const cycles = instruments
      .map((I) => I.waveform && I.waveform.one_cycle ? normalizePeak(resampleNumeric(I.waveform.one_cycle, len, 0), 1, true) : null)
      .filter(Boolean);
    if (!cycles.length) return { one_cycle_points: 4, one_cycle: [0, 1, 0, -1] };
    const base = cycles[0];
    const sum = new Array(len).fill(0);
    for (const cyc of cycles) {
      let dot = 0;
      for (let i = 0; i < len; i++) dot += base[i] * cyc[i];
      const sign = dot < 0 ? -1 : 1;
      for (let i = 0; i < len; i++) sum[i] += sign * cyc[i] / cycles.length;
    }
    return { one_cycle_points: len, one_cycle: roundList(normalizePeak(sum, 1, true), 5) };
  }

  function representativeModulation(instruments) {
    const vib = instruments.map((I) => (I.modulation && I.modulation.vibrato) || {});
    const trem = instruments.map((I) => (I.modulation && I.modulation.tremolo) || {});
    const vibDepth = average(vib.map((v) => v.depth_cents), 0);
    const tremDepth = average(trem.map((v) => v.depth), 0);
    return {
      vibrato: {
        rate_hz: +average(vib.map((v) => v.rate_hz), 0).toFixed(2),
        depth_cents: +vibDepth.toFixed(1),
        depth: +(vibDepth / 100).toFixed(3),
        onset_sec: +average(vib.map((v) => v.onset_sec), 0).toFixed(3),
        shape: (vib.find((v) => v.shape) || {}).shape || "sine",
        regularity: +average(vib.map((v) => v.regularity), 0).toFixed(3),
        detected: vibDepth > 0.5,
      },
      tremolo: {
        rate_hz: +average(trem.map((v) => v.rate_hz), 0).toFixed(2),
        depth: +tremDepth.toFixed(3),
        depth_cents: 0.0,
        onset_sec: 0.0,
        shape: (trem.find((v) => v.shape) || {}).shape || "sine",
        regularity: +average(trem.map((v) => v.regularity), 0).toFixed(3),
        detected: tremDepth > 0.005,
      },
    };
  }

  function exportRepresentativeJson() {
    const tracks = batchReadyTracks();
    if (!tracks.length) { setBatchStatus("代表音色にできる解析済み音源がありません。", true); return; }
    const instruments = tracks.map((t) => adjustedBatchInstrument(t));
    const rootTrack = tracks[Math.floor((tracks.length - 1) / 2)];
    const rootInst = instruments[Math.floor((instruments.length - 1) / 2)] || rootTrack.instrument;
    const rootNote = rootTrack.note || rootInst.midi_note || 60;
    const profileSet = Array.from(new Set(instruments.map((I) => I.instrument_profile || "auto")));
    const first = instruments[0] || {};
    const harmonics = representativeHarmonics(instruments);
    const features = {};
    for (const key of ["spectral_centroid_hz", "spectral_rolloff_hz", "spectral_bandwidth_hz", "zero_crossing_rate", "spectral_flatness"]) {
      const nums = finiteNumbers(instruments.map((I) => I.features && I.features[key]));
      if (nums.length) features[key] = +(nums.reduce((s, v) => s + v, 0) / nums.length).toFixed(4);
    }
    features.harmonic_count = harmonics.length;
    features.representative_source_count = tracks.length;
    features.representative_sources = tracks.map((t) => {
      const note = t.note || t.instrument.midi_note || 60;
      return { source_file: t.file.name, note: SL.midiName(note), midi_note: note, volume: +t.volume.toFixed(3) };
    });

    const out = {
      format: "sound_lab.instrument/1",
      name: `${profileSet.length === 1 && profileSet[0] === "violin" ? "violin" : "representative"} average (調整)`,
      source_file: tracks.map((t) => t.file.name).join(" + "),
      created_at: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
      sample_rate: rootInst.sample_rate || first.sample_rate || 44100,
      fundamental_hz: +(rootInst.fundamental_hz || SL.midiToHz && SL.midiToHz(rootNote) || 440).toFixed(4),
      midi_note: rootNote,
      note_name: SL.midiName(rootNote),
      duration_sec: +average(instruments.map((I) => I.duration_sec), rootInst.duration_sec || 2).toFixed(4),
      sustaining: instruments.some((I) => I.sustaining !== false),
      envelope: representativeEnvelope(instruments),
      inharmonicity_b: +average(instruments.map((I) => I.inharmonicity_b), 0).toExponential(3),
      modulation: representativeModulation(instruments),
      harmonics,
      noise: representativeNoise(instruments),
      waveform: representativeWaveform(instruments),
      features,
      instrument_profile: profileSet.length === 1 ? profileSet[0] : "mixed",
      instrument_profile_label: profileSet.length === 1 ? (first.instrument_profile_label || profileSet[0]) : "混合",
      edited_by: "sound_lab studio",
    };
    out.fx = {
      note: "複数音源から作った代表音色。各音程を切り替える音色パックではなく、通常の単音インストゥルメント定義として扱う。",
      representative_mode: "average_harmonics_envelope_noise_waveform",
      source_notes: tracks.map((t) => SL.midiName(t.note || t.instrument.midi_note || 60)),
      source_count: tracks.length,
    };

    const blob = new Blob([JSON.stringify(out, null, 1)], { type: "application/json" });
    downloadBlob(blob, `${safeName(out.name)}.representative.instrument.json`);
    setBatchStatus(`代表音色JSONを書き出しました（${tracks.length} 音を平均 / 基準 ${SL.midiName(rootNote)}）`);
  }

  function exportMultiNoteJson() {
    const tracks = batchReadyTracks();
    if (!tracks.length) { setBatchStatus("書き出せる解析済み音源がありません。", true); return; }
    const sorted = tracks;
    const seen = new Set();
    for (const t of sorted) {
      const note = t.note || t.instrument.midi_note || 60;
      if (seen.has(note)) {
        setBatchStatus(`${SL.midiName(note)} が重複しています。ファイル名か解析結果を確認してください。`, true);
        return;
      }
      seen.add(note);
    }

    const first = sorted[0].instrument || {};
    const profileSet = Array.from(new Set(sorted.map((t) => t.instrument.instrument_profile || "auto")));
    const pack = {
      format: "sound_lab.multinote_instrument/1",
      name: `${profileSet.length === 1 && profileSet[0] === "violin" ? "violin" : "multi-note"} pack (調整)`,
      created_at: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
      instrument_profile: profileSet.length === 1 ? profileSet[0] : "mixed",
      instrument_profile_label: profileSet.length === 1 ? (first.instrument_profile_label || profileSet[0]) : "混合",
      note_order: sorted.map((t) => t.note || t.instrument.midi_note || 60),
      note_map: {},
      sounds: {},
      edited_by: "sound_lab studio",
    };

    for (const t of sorted) {
      const note = t.note || t.instrument.midi_note || 60;
      const key = String(note);
      const json = adjustedBatchInstrument(t);
      json.name = `${t.instrument.name || safeName(t.file.name)} (${SL.midiName(note)})`;
      pack.note_map[key] = {
        label: SL.midiName(note),
        source_file: t.file.name,
        instrument_name: t.instrument.name || safeName(t.file.name),
        detected_note: t.instrument.note_name || null,
        detected_midi_note: t.instrument.midi_note || null,
        volume: +t.volume.toFixed(3),
      };
      pack.sounds[key] = json;
    }

    const blob = new Blob([JSON.stringify(pack, null, 1)], { type: "application/json" });
    downloadBlob(blob, `${safeName(pack.name)}.multinote.instrument.json`);
    setBatchStatus(`1つの音色パックJSONを書き出しました（${sorted.length} 音 / ${sorted.map((t) => SL.midiName(t.note || t.instrument.midi_note || 60)).join(", ")}）`);
  }

  async function exportBatchZip() {
    const tracks = batch.tracks.filter((t) => !t.error);
    if (!tracks.length) { setBatchStatus("書き出せる解析済み音源がありません。", true); return; }
    $("#exportBatchZipBtn").disabled = true;
    const old = $("#exportBatchZipBtn").textContent;
    $("#exportBatchZipBtn").textContent = "ZIP 作成中…";
    try {
      const dur = clamp(+$("#batchWavDur").value || 2.5, 0.3, 12);
      const files = [];
      const manifest = {
        created_at: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
        mode: "sound_lab 複数音源バランス調整",
        metal_preset_applied: !!batch.metalApplied,
        wav_duration_sec: dur,
        tracks: [],
      };
      for (let i = 0; i < tracks.length; i++) {
        const t = tracks[i];
        setBatchStatus(`ZIP 作成中… ${i + 1} / ${tracks.length} (${t.file.name})`);
        const note = t.note || t.instrument.midi_note || 60;
        const base = `${String(i + 1).padStart(2, "0")}_${safeName(t.instrument.name || t.file.name)}`;
        const tmp = new SL.LiveSynth();
        tmp.load(t.instrument);
        tmp.params = deepCopy(t.params);
        tmp.params.masterVol = t.volume;
        const wav = await tmp.renderWav(note, dur);
        const json = adjustedBatchInstrument(t);
        json.name = (t.instrument.name || safeName(t.file.name)) + " (複数音源バランス調整)";
        files.push({ name: `${base}_${SL.midiName(note)}.wav`, blob: wav });
        files.push({ name: `${base}.tweaked.instrument.json`, blob: new Blob([JSON.stringify(json, null, 1)], { type: "application/json" }) });
        manifest.tracks.push({ index: i + 1, source_file: t.file.name, note: SL.midiName(note), midi_note: note, volume: +t.volume.toFixed(3), json: `${base}.tweaked.instrument.json`, wav: `${base}_${SL.midiName(note)}.wav` });
      }
      files.push({ name: "manifest.json", blob: new Blob([JSON.stringify(manifest, null, 2)], { type: "application/json" }) });
      const zip = await makeZip(files);
      downloadBlob(zip, "sound_lab_balance_export.zip");
      setBatchStatus(`ZIP を書き出しました（${tracks.length} 音源 / WAV + JSON + manifest）`);
    } catch (e) {
      setBatchStatus("ZIP 書き出しに失敗しました: " + e.message, true);
    }
    $("#exportBatchZipBtn").textContent = old;
    $("#exportBatchZipBtn").disabled = batch.tracks.length === 0;
  }

  function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = el("a", { href: url, download: filename });
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }

  const CRC_TABLE = (function () {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      table[n] = c >>> 0;
    }
    return table;
  })();
  function crc32(bytes) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }
  function u16(v) { const b = new Uint8Array(2); new DataView(b.buffer).setUint16(0, v, true); return b; }
  function u32(v) { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, v >>> 0, true); return b; }
  function concatBytes(parts) {
    const len = parts.reduce((s, p) => s + p.length, 0);
    const out = new Uint8Array(len);
    let off = 0;
    for (const p of parts) { out.set(p, off); off += p.length; }
    return out;
  }
  function dosTimeDate(date) {
    const time = (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2);
    const day = ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
    return { time, day };
  }
  async function makeZip(files) {
    const enc = new TextEncoder();
    const localParts = [], centralParts = [];
    let offset = 0;
    const dt = dosTimeDate(new Date());
    for (const f of files) {
      const data = new Uint8Array(await f.blob.arrayBuffer());
      const name = enc.encode(f.name);
      const crc = crc32(data);
      const local = concatBytes([
        u32(0x04034b50), u16(20), u16(0), u16(0), u16(dt.time), u16(dt.day),
        u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), name, data,
      ]);
      localParts.push(local);
      centralParts.push(concatBytes([
        u32(0x02014b50), u16(20), u16(20), u16(0), u16(0), u16(dt.time), u16(dt.day),
        u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), u16(0),
        u16(0), u16(0), u32(0), u32(offset), name,
      ]));
      offset += local.length;
    }
    const central = concatBytes(centralParts);
    const end = concatBytes([
      u32(0x06054b50), u16(0), u16(0), u16(files.length), u16(files.length),
      u32(central.length), u32(offset), u16(0),
    ]);
    return new Blob([concatBytes(localParts), central, end], { type: "application/zip" });
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
    const apply = (ev) => { const a = harmEditAt(ev); if (!a) return; ensureAudio().then(() => { synth.setHarmGain(a.n, a.mul); drawHarmEdit(); renderCompatibilitySummary(); }); };
    c.addEventListener("pointerdown", (e) => { e.preventDefault(); harmEditDrag = true; apply(e); });
    c.addEventListener("pointermove", (e) => { if (harmEditDrag) { e.preventDefault(); apply(e); } });
    window.addEventListener("pointerup", () => { harmEditDrag = false; });
    c.addEventListener("dblclick", (e) => { const a = harmEditAt(e); if (a) { synth.setHarmGain(a.n, 1); drawHarmEdit(); renderCompatibilitySummary(); } });
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
