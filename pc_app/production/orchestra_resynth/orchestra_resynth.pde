/* ==========================================================================
   orchestra_resynth — production ゲームモード対応 PC 側プログラム (Processing)

   firmware/production の楽器ノード (Arduino UNO R4 WiFi) から USB Serial で送られて
   くる NOTE パケット (type=3, 20B) と UI 状態パケット (type=4, 20B) を受信し、
   NOTE は加算合成で発音、UI は画面を自動判定して描画する。

   production の主要変更点 (test_v2 からの差分):
     ・type=4 (PKT_UI) の解釈: 指揮者の state/mode/navCursor/targetBpm/score を受け取る
     ・役割自動判定: UIフレーム受信 or partId==0x02 → メイン操作UI、それ以外 → アナライザ
     ・データ駆動の画面遷移: (state, mode) から毎フレーム画面を再判定 (手動 Node 選択廃止)
     ・画面群: ポート選択→メニュー→自由演奏/ゲーム演奏→結果 + アナライザ
     ・メトロノームクリック: ゲーム画面で targetBpm から PC ローカル計算、フェード付き

   パケット仕様 (受信, 20 バイト固定, リトルエンディアン):
     0  magic       uint16  0x4F52 ("OR")
     2  version     uint8   0x01
     3  type        uint8   3=NOTE / 4=UI (1=CTRL / 2=BEAT は USB には流れない)
     --- type=3 (NOTE) ---
     12 partId      uint8   0x02-0x05
     13 noteNumber  uint8   MIDI ノート番号
     14 velocity    uint8   0-127
     15 gate        uint8   1=NoteOn
     16 durationMs  uint16
     18 instrumentId uint8
     19 reserved    uint8
     --- type=4 (UI) ---
     12 state       uint8   0-5 (Idle/Calibrating/Conducting/Fallback/Menu/Result)
     13 mode        uint8   0=自由演奏 / 1=ゲーム
     14 navCursor   uint8   メニューカーソル位置
     15 targetBpm   uint8   目標テンポ (生 BPM)
     16 score       uint8   0-100 / 0xFF=未確定
     17 partId      uint8   中継元ノード ID
     18 bpmQ8       uint16  実振り BPM ×8

   必要ライブラリ: Minim
   ========================================================================== */

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*;
import java.util.Iterator;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.io.File;

// ── 設定 ──────────────────────────────────────────────────
final int  SERIAL_BAUD   = 115200;
final int  PACKET_SIZE   = 20;
final byte MAGIC_LO      = (byte) 0x52;
final byte MAGIC_HI      = (byte) 0x4F;
final int  TYPE_CTRL     = 1;
final int  TYPE_BEAT     = 2;
final int  TYPE_NOTE     = 3;
final int  TYPE_UI       = 4;
final int  MAX_POLYPHONY = 24;

float   masterVolume  = 0.55f;
boolean useSimpleADSR = true;

// 指揮者の状態 (OrcProtocol.h と整合)
final int ST_IDLE        = 0;
final int ST_CALIBRATING = 1;
final int ST_CONDUCTING  = 2;
final int ST_FALLBACK    = 3;
final int ST_MENU        = 4;
final int ST_RESULT      = 5;

// ゲーム定数 (firmware ProjectConfig.h と整合)
final int GAME_LENGTH_BEATS      = 32;
final int GAME_GUIDE_FULL_BEATS  = 8;
final int GAME_GUIDE_ZERO_BEATS  = 16;
final int UI_TIMEOUT_MS          = 2000;

// 役割
final int ROLE_UNKNOWN  = 0;
final int ROLE_MAIN_UI  = 1;
final int ROLE_ANALYZER = 2;

// 画面
final int SCR_PORT_SELECT = 0;
final int SCR_WAITING     = 1;
final int SCR_MENU        = 2;
final int SCR_FREE_PLAY   = 3;
final int SCR_GAME_PLAY   = 4;
final int SCR_RESULT      = 5;
final int SCR_ANALYZER    = 6;

// メニュー項目 (説明文はメニュー画面のボックス内に表示)
final String[] MENU_ITEMS = { "自由演奏", "ゲーム" };
final String[] MENU_DESCS = { "振ったテンポで輪唱", "目標テンポ維持を採点" };

// ── オーディオ ────────────────────────────────────────────
Minim       minim;
AudioOutput out;

// ── 楽器定義 (data/*.json) ────────────────────────────────
ArrayList<File>        instrumentFiles = new ArrayList<File>();
ArrayList<InstrModel>  models          = new ArrayList<InstrModel>();
ArrayList<String>      modelLabels     = new ArrayList<String>();
boolean      forceSingleInstrument    = false;
final String FORCED_INSTRUMENT_FILE   = "0_trumpets.tweaked.instrument.json";
int          forcedInstrumentIdx      = -1;

// ── シリアルポート ────────────────────────────────────────
class PortConn {
  String  name;
  Serial  port;
  byte[]  rxBuf = new byte[PACKET_SIZE];
  int     rxIdx = 0;
  boolean inFrame = false;
  int     rxCount = 0;
  PortConn(String n) { name = n; }
}
String[]                  availablePorts = new String[0];
String[]                  displayPorts   = new String[0];
boolean                   usbOnly        = true;
float                     portScrollY    = 0;
HashMap<String,PortConn>  openByName     = new HashMap<String,PortConn>();
HashMap<Serial,PortConn>  bySerial       = new HashMap<Serial,PortConn>();
ConcurrentLinkedQueue<byte[]> packetQueue = new ConcurrentLinkedQueue<byte[]>();

// ── 発音中ボイス ──────────────────────────────────────────
ArrayList<ResynthVoice> activeVoices = new ArrayList<ResynthVoice>();

// ── 表示用 ────────────────────────────────────────────────
int      totalReceived = 0;
String[] lastEventByPart = new String[256];
int[]    lastNoteMsByPart = new int[256];   // 声部別の最終 NOTE 受信時刻 (0=未受信。接続インジケータ用)
int      lastNoteAtMs   = 0;
PFont    uiFont;

// ── UI 状態 (type=4 から更新) ─────────────────────────────
int nodeRole     = ROLE_UNKNOWN;
int uiState      = ST_IDLE;
int uiMode       = 0;
int uiNavCursor  = 0;
int uiTargetBpm  = 0;
int uiScore      = 0xFF;
int uiBpmQ8      = 0;
int uiPartId     = 0;
int lastUiAtMs   = 0;
boolean masterResetDetected = false;

// ── メトロノーム (ゲーム画面でローカル計算) ────────────────
int   gameStartMs     = 0;
int   lastMetroBeat   = -1;
int   currentScreen   = SCR_PORT_SELECT;
int   prevScreen      = -1;
ArrayList<MetroClick> metroClicks = new ArrayList<MetroClick>();

final String[] NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
String noteName(int midi){ return NOTE_NAMES[((midi%12)+12)%12] + (midi/12 - 1); }

// ────────────────────────────────────────────────────────────
void settings(){ size(1000, 560); }

void setup(){
  frameRate(90);
  surface.setTitle("タクトーン — production ゲームモード");
  uiFont = loadJapaneseFont(13);
  if (uiFont != null) textFont(uiFont);
  else textFont(createFont("SansSerif", 13));

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 512, 44100);

  rescanInstruments();
  refreshPorts();

  println("=== orchestra_resynth (production ゲームモード) ===");
  println("楽器定義 " + models.size() + " 個ロード。");
  println("[click] ポート開閉  /  [r] ポート再列挙・画面リセット  /  [f] USBフィルタ  /  [t] テスト音  /  [Space] 停止");
}

PFont loadJapaneseFont(float sizePx){
  String[] candidates = {
    "Hiragino Sans", "Hiragino Kaku Gothic ProN", "HiraginoSans-W3",
    "Yu Gothic", "Yu Gothic Medium", "Meiryo",
    "Noto Sans CJK JP", "Noto Sans JP", "Arial Unicode MS"
  };
  String[] avail = PFont.list();
  for (String c : candidates)
    for (String a : avail)
      if (a.equalsIgnoreCase(c)){ println("UI font: " + c); return createFont(c, sizePx, true); }
  println("(!) 日本語対応フォントが見つかりませんでした。");
  return null;
}

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
  forcedInstrumentIdx = -1;
  for (int i = 0; i < instrumentFiles.size(); i++){
    if (instrumentFiles.get(i).getName().equalsIgnoreCase(FORCED_INSTRUMENT_FILE) && models.get(i) != null){
      forcedInstrumentIdx = i;
      break;
    }
  }
}

InstrModel modelForId(int id){
  if (models.isEmpty()) return null;
  int idx;
  if (forceSingleInstrument && forcedInstrumentIdx >= 0) idx = forcedInstrumentIdx;
  else                                                   idx = constrain(id, 0, models.size()-1);
  InstrModel m = models.get(idx);
  if (m != null) return m;
  for (InstrModel mm : models) if (mm != null) return mm;
  return null;
}

// ── シリアルポート 列挙 / 開閉 ─────────────────────────────
void refreshPorts(){
  availablePorts = Serial.list();
  rebuildDisplayPorts();
  println("Serial ports (usbOnly=" + usbOnly + "): " + availablePorts.length + " 個");
}
boolean isUsbSerialName(String name){
  if (name == null) return false;
  String n = name.toLowerCase();
  return n.contains("usbmodem") || n.contains("usbserial")
      || n.contains("ttyusb")   || n.contains("ttyacm")
      || n.startsWith("com")    || n.contains("/com");
}
void rebuildDisplayPorts(){
  if (!usbOnly){ displayPorts = availablePorts; }
  else {
    ArrayList<String> kept = new ArrayList<String>();
    for (String n : availablePorts)
      if (isUsbSerialName(n) || openByName.containsKey(n)) kept.add(n);
    displayPorts = kept.toArray(new String[0]);
  }
  if (displayPorts.length == 0) portScrollY = 0;
}
void togglePort(String name){
  if (openByName.containsKey(name)) closePort(name);
  else openPort(name);
}
void openPort(String name){
  if (openByName.containsKey(name)) return;
  try {
    PortConn pc = new PortConn(name);
    pc.port = new Serial(this, name, SERIAL_BAUD);
    pc.port.buffer(1);
    openByName.put(name, pc);
    bySerial.put(pc.port, pc);
    println("Opened: " + name);
  } catch (Exception e){
    println("(!) Failed to open " + name + ": " + e.getMessage());
  }
}
void closePort(String name){
  PortConn pc = openByName.remove(name);
  if (pc == null) return;
  if (pc.port != null){
    bySerial.remove(pc.port);
    try { pc.port.stop(); } catch (Exception e){ /* ignore */ }
  }
  println("Closed: " + name);
  if (openByName.isEmpty()){
    nodeRole = ROLE_UNKNOWN;
    uiState = ST_IDLE;
    uiScore = 0xFF;
    updateRoleTitle();
  }
}

// 役割の確定/リセットをウィンドウタイトルにも反映する (複数 Mac 運用時の取り違え防止)
void updateRoleTitle(){
  String role = (nodeRole == ROLE_MAIN_UI) ? "メイン操作UI"
              : (nodeRole == ROLE_ANALYZER) ? "アナライザ" : "ポート選択";
  surface.setTitle("タクトーン production — " + role);
}
void closeAllPorts(){
  for (String n : new ArrayList<String>(openByName.keySet())) closePort(n);
}

// ── シリアル受信 (Serial スレッド) ─────────────────────────
void serialEvent(Serial p){
  PortConn pc = bySerial.get(p);
  if (pc == null){ while (p.available() > 0) p.read(); return; }
  while (p.available() > 0){
    int b = p.read();
    if (!pc.inFrame){
      if (pc.rxIdx == 0){
        if ((byte)b == MAGIC_LO){ pc.rxBuf[0] = (byte)b; pc.rxIdx = 1; }
      } else {
        if ((byte)b == MAGIC_HI){ pc.rxBuf[1] = (byte)b; pc.rxIdx = 2; pc.inFrame = true; }
        else { pc.rxIdx = ((byte)b == MAGIC_LO) ? 1 : 0; if (pc.rxIdx == 1) pc.rxBuf[0] = (byte)b; }
      }
    } else {
      pc.rxBuf[pc.rxIdx++] = (byte)b;
      if (pc.rxIdx >= PACKET_SIZE){
        byte[] copy = new byte[PACKET_SIZE];
        System.arraycopy(pc.rxBuf, 0, copy, 0, PACKET_SIZE);
        packetQueue.offer(copy);
        pc.rxCount++;
        pc.rxIdx = 0; pc.inFrame = false;
      }
    }
  }
}

// ── パケット処理 (draw スレッド) ───────────────────────────
int u8(byte v){ return v & 0xFF; }
int u16le(byte lo, byte hi){ return u8(lo) | (u8(hi) << 8); }

void drainPackets(){
  byte[] pkt;
  while ((pkt = packetQueue.poll()) != null) handlePacket(pkt);
}
void handlePacket(byte[] buf){
  totalReceived++;
  if (u8(buf[2]) != 0x01) return;
  int type = u8(buf[3]);

  // type=4 (UI): 指揮者の状態を受信 → 役割をメイン操作UIに確定
  if (type == TYPE_UI){
    uiState     = u8(buf[12]);
    uiMode      = u8(buf[13]);
    uiNavCursor = u8(buf[14]);
    uiTargetBpm = u8(buf[15]);
    uiScore     = u8(buf[16]);
    uiPartId    = u8(buf[17]);
    uiBpmQ8     = u16le(buf[18], buf[19]);
    lastUiAtMs  = millis();
    if (nodeRole != ROLE_MAIN_UI){
      nodeRole = ROLE_MAIN_UI;
      updateRoleTitle();
      println("役割自動判定: メイン操作 UI (UIフレーム受信)");
    }
    masterResetDetected = false;
    return;
  }

  if (type != TYPE_NOTE) return;

  int partId       = u8(buf[12]);
  int noteNumber   = u8(buf[13]);
  int velocity     = u8(buf[14]);
  int gate         = u8(buf[15]);
  int durationMs   = u16le(buf[16], buf[17]);
  int instrumentId = u8(buf[18]);

  // 役割自動判定 (NOTE の partId から)
  if (nodeRole == ROLE_UNKNOWN){
    if (partId == 0x02){
      nodeRole = ROLE_MAIN_UI;
      println("役割自動判定: メイン操作 UI (partId=0x02)");
    } else {
      nodeRole = ROLE_ANALYZER;
      println("役割自動判定: アナライザ (partId=0x" + hex(partId, 2) + ")");
    }
    updateRoleTitle();
  }

  if (gate == 1){
    println("NOTE: part=0x" + hex(partId,2) + " note=" + noteNumber + "(" + noteName(noteNumber) + ") vel=" + velocity + " dur=" + durationMs + "ms gate=" + gate + " instr=" + instrumentId);
    triggerNote(partId, instrumentId, noteNumber, velocity, durationMs);
    lastEventByPart[partId] = noteName(noteNumber) + " v=" + velocity + " dur=" + durationMs + "ms";
    lastNoteMsByPart[partId] = millis();
    lastNoteAtMs = millis();
  } else {
    int releaseMidi = isDrumInstrument(instrumentId) ? noteNumber : noteNumber + brassOctaveShift(instrumentId);
    releaseMatching(partId, releaseMidi);
  }
}

// ── ドラム noteNumber → 音色インデックス変換 ─────────────
// GM ドラムマップ: noteNumber で打楽器音色を選ぶ (data/ のファイル名昇順 index)
//   36 (kick)  → 4  (4_kick.tweaked.instrument.json)
//   38 (snare) → 5  (5_snare.tweaked.instrument.json)
//   42 (hihat) → 6  (6_hi_hat.tweaked.instrument.json)
//   49 (crash) → 7  (7_crash.tweaked.instrument.json)
int drumInstrIndex(int noteNumber){
  switch (noteNumber){
    case 36: return 4;
    case 38: return 5;
    case 42: return 6;
    case 49: return 7;
    default: return 4;
  }
}
boolean isDrumInstrument(int instrumentId){ return instrumentId >= 4; }

// 齋藤版 (kaeru_score_debug) と同じオクターブ移調（楽譜は全声部 C4 基準）
int brassOctaveShift(int instrumentId){
  switch (instrumentId){
    case 0: return  12;   // トランペット → C5
    case 1: return   0;   // ホルン → C4
    case 2: return -12;   // トロンボーン → C3
    case 3: return -12;   // チューバ → C3（埋もれにくくするため1オクターブ上げる）
    default: return  0;
  }
}

// 齋藤版と同じパート別振幅
float brassPartAmplitude(int instrumentId){
  switch (instrumentId){
    case 0: return 0.20f;  // トランペット
    case 1: return 0.17f;  // ホルン
    case 2: return 0.18f;  // トロンボーン
    case 3: return 0.25f;  // チューバ（低域が埋もれないよう増量）
    default: return 0.18f;
  }
}

// ── 発音管理 ──────────────────────────────────────────────
void triggerNote(int partId, int instrumentId, int midi, int velocity, int durationMs){
  int effectiveId = isDrumInstrument(instrumentId) ? drumInstrIndex(midi) : instrumentId;
  InstrModel m = modelForId(effectiveId);
  if (m == null) return;
  int guard = 0;
  while (countNonReleasing() >= MAX_POLYPHONY && guard++ < MAX_POLYPHONY){
    for (ResynthVoice v : activeVoices){ if (!v.releasing){ v.noteOff(); break; } }
  }
  int effectiveMidi = midi;
  float g;
  if (isDrumInstrument(instrumentId)){
    g = constrain(velocity / 127.0f, 0.0f, 1.0f) * masterVolume;
  } else {
    effectiveMidi = midi + brassOctaveShift(instrumentId);
    g = constrain(velocity / 127.0f, 0.0f, 1.0f) * brassPartAmplitude(instrumentId);
  }
  ResynthVoice v = new ResynthVoice(m, effectiveMidi, g, useSimpleADSR);
  v.partId        = partId;
  v.instrumentIdx = constrain(instrumentId, 0, max(0, models.size()-1));
  v.scheduledOffMs = millis() + max(40, durationMs);
  v.patch(out);
  activeVoices.add(v);
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

// ── 画面判定 (データ駆動・毎フレーム) ─────────────────────
int determineScreen(){
  if (openByName.isEmpty()) return SCR_PORT_SELECT;
  if (nodeRole == ROLE_ANALYZER) return SCR_ANALYZER;
  if (nodeRole == ROLE_MAIN_UI){
    switch (uiState){
      case ST_MENU:        return SCR_MENU;
      case ST_CONDUCTING:  return uiMode == 1 ? SCR_GAME_PLAY : SCR_FREE_PLAY;
      case ST_RESULT:      return SCR_RESULT;
      default:             return SCR_WAITING;
    }
  }
  return SCR_WAITING;
}

void onScreenChange(int fromScr, int toScr){
  if (toScr == SCR_GAME_PLAY){
    gameStartMs = millis();
    lastMetroBeat = -1;
  }
  if (toScr == SCR_WAITING){
    gameStartMs = 0;
    lastMetroBeat = -1;
    uiScore = 0xFF;
    for (MetroClick mc : metroClicks) mc.unpatch(out);
    metroClicks.clear();
  }
}

// ── ガイド強度 (firmware と同じ式) ────────────────────────
float gameGuideIntensity(int beatCount){
  if (beatCount < GAME_GUIDE_FULL_BEATS) return 1.0f;
  if (beatCount >= GAME_GUIDE_ZERO_BEATS) return 0.0f;
  float span = (float)(GAME_GUIDE_ZERO_BEATS - GAME_GUIDE_FULL_BEATS);
  return 1.0f - (float)(beatCount - GAME_GUIDE_FULL_BEATS) / span;
}

// ── メトロノーム (ゲーム画面・PC ローカル計算) ────────────
void updateMetronome(){
  for (Iterator<MetroClick> it = metroClicks.iterator(); it.hasNext();){
    MetroClick mc = it.next();
    if (mc.done){ mc.unpatch(out); it.remove(); }
  }
  if (currentScreen != SCR_GAME_PLAY) return;
  if (uiTargetBpm <= 0) return;

  int elapsed = millis() - gameStartMs;
  float intervalMs = 60000.0f / (float)uiTargetBpm;
  int beatNum = (int)(elapsed / intervalMs);

  if (beatNum > lastMetroBeat && beatNum < GAME_LENGTH_BEATS){
    float guide = gameGuideIntensity(beatNum);
    if (guide > 0.01f){
      MetroClick mc = new MetroClick(guide * masterVolume);
      mc.patch(out);
      metroClicks.add(mc);
    }
    lastMetroBeat = beatNum;
  }
}

// ── 描画ループ ────────────────────────────────────────────
void draw(){
  drainPackets();

  // マスター ESP32 リセット検知 (UIパケット 5秒タイムアウト)
  if (lastUiAtMs > 0 && !openByName.isEmpty() && nodeRole == ROLE_MAIN_UI){
    if (millis() - lastUiAtMs > UI_TIMEOUT_MS){
      uiState = ST_IDLE;
      uiScore = 0xFF;
      gameStartMs = 0;
      lastMetroBeat = -1;
      stopAll();
      masterResetDetected = true;
      lastUiAtMs = 0;
      println("(!) マスターリセット検知: UIパケットタイムアウト (" + UI_TIMEOUT_MS + "ms)");
    }
  }

  int now = millis();
  for (ResynthVoice v : activeVoices) if (!v.releasing && now >= v.scheduledOffMs) v.noteOff();
  for (Iterator<ResynthVoice> it = activeVoices.iterator(); it.hasNext();){
    ResynthVoice v = it.next();
    if (v.done){ v.unpatch(out); it.remove(); }
  }

  updateMetronome();

  currentScreen = determineScreen();
  if (currentScreen != prevScreen){
    onScreenChange(prevScreen, currentScreen);
    prevScreen = currentScreen;
  }

  switch (currentScreen){
    case SCR_PORT_SELECT: drawPortSelectScreen(); break;
    case SCR_WAITING:     drawWaitingScreen();    break;
    case SCR_MENU:        drawMenuScreen();       break;
    case SCR_FREE_PLAY:   drawFreePlayScreen();   break;
    case SCR_GAME_PLAY:   drawGamePlayScreen();   break;
    case SCR_RESULT:      drawResultScreen();     break;
    case SCR_ANALYZER:    drawAnalyzerScreen();   break;
    default:              drawWaitingScreen();     break;
  }
}

// ── 共通 UI 部品 ─────────────────────────────────────────
void drawBackground(){
  background(238, 247, 255);
  noStroke();
  fill(255, 221, 100, 120); ellipse(72, 70, 150, 150);
  fill(82, 194, 255, 95);   ellipse(934, 92, 220, 220);
  fill(132, 224, 146, 95);  ellipse(884, 526, 260, 180);
  fill(255, 125, 132, 80);  ellipse(76, 520, 230, 160);
  stroke(210, 228, 240, 90); strokeWeight(1);
  for (int gx = 0; gx <= width; gx += 50) line(gx, 0, gx, height);
  for (int gy = 0; gy <= height; gy += 50) line(0, gy, width, gy);
  noStroke();
}
void drawPanel(float x, float y, float w, float h){
  noStroke();
  fill(23, 60, 95, 34); rect(x + 8, y + 10, w, h, 18);
  fill(255); rect(x, y, w, h, 18);
  stroke(134, 184, 218); strokeWeight(3); noFill();
  rect(x, y, w, h, 18);
  strokeWeight(1); noStroke();
}
boolean mouseOver(float x, float y, float w, float h){ return mouseX>=x && mouseX<=x+w && mouseY>=y && mouseY<=y+h; }
int lighten(int c, int amount){
  return color(min(255, red(c)+amount), min(255, green(c)+amount), min(255, blue(c)+amount));
}

void drawScope(float x, float y, float w, float h){
  drawPanel(x, y, w, h);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  text("出力波形", x + 22, y + 24);
  stroke(24, 111, 196); strokeWeight(2.5); noFill();
  float cy = y + h * 0.55f;
  beginShape();
  for (int i = 0; i < out.bufferSize(); i++)
    vertex(x + 20 + (w - 40) * i / (float)(out.bufferSize() - 1), cy - out.left.get(i) * (h * 0.35f));
  endShape();
  strokeWeight(1); noStroke();
}

void drawPageTitle(String title, String subtitle){
  fill(18, 54, 88); textSize(34); textAlign(LEFT, BASELINE);
  text(title, 168, 52);
  fill(61, 86, 111); textSize(15);
  text(subtitle, 170, 78);
}

// ── ポート選択画面 ────────────────────────────────────────
void drawPortSelectScreen(){
  drawBackground();
  drawPageTitle("タクトーン — production",
      "楽器定義 " + models.size() + " 個  /  [click]ポート開閉  [r]再列挙  [f]フィルタ  [t]テスト音  [p]音色切替");
  drawPortListAt(96);
}

// ── 接続待ち画面 ──────────────────────────────────────────
void drawWaitingScreen(){
  drawBackground();
  String title, desc;
  switch (uiState){
    case ST_CALIBRATING:
      title = "キャリブレーション中...";
      desc  = "指揮棒を静止させたまま約 2 秒待ってください";
      break;
    case ST_FALLBACK:
      title = "一時停止 (Fallback)";
      desc  = "指揮者の IMU / WiFi が止まっています。復帰すると自動で戻ります";
      break;
    default:
      title = nodeRole == ROLE_UNKNOWN ? "データ待ち..." : "待機中";
      desc  = "指揮者の起動とキャリブレーション完了を待っています";
      break;
  }
  drawPageTitle("タクトーン — production", "ポート " + openByName.size() + " 個接続中  /  " + title);

  drawPanel(width/2 - 220, height/2 - 80, 440, 160);
  fill(18, 54, 88); textSize(24); textAlign(CENTER, CENTER);
  text(title, width/2, height/2 - 30);
  fill(61, 86, 111); textSize(14);
  text(desc, width/2, height/2 + 10);
  if (masterResetDetected){
    fill(197, 83, 31); textSize(13);
    text("指揮者の再起動を検知しました。再接続中...", width/2, height/2 + 40);
  }
  textAlign(LEFT, BASELINE);

  drawHelpPanel("[r]ポート再選択  [t]テスト音  [+/-]音量  [Space]停止");
}

// ── メニュー画面 ──────────────────────────────────────────
void drawMenuScreen(){
  drawBackground();
  drawPageTitle("タクトーン — メニュー", "指揮者の IMU 操作でカーソルが動きます。縦振りで決定。");

  float modeW = 270, modeH = 135, modeY = 200;
  float gap = 60;
  float totalW = 2 * modeW + gap;
  float startX = width/2 - totalW/2;

  for (int i = 0; i < MENU_ITEMS.length; i++){
    float bx = startX + i * (modeW + gap);
    boolean selected = (uiNavCursor == i);
    int baseCol = (i == 0) ? color(64, 159, 255) : color(24, 156, 104);
    boolean hover = mouseOver(bx, modeY, modeW, modeH);
    noStroke();
    fill(23, 52, 84, 45); rect(bx + 8, modeY + 10, modeW, modeH, 18);
    fill(selected ? baseCol : (hover ? lighten(baseCol, 24) : color(226, 231, 236)));
    rect(bx, modeY, modeW, modeH, 18);
    stroke(selected ? color(255) : color(186, 196, 206));
    strokeWeight(3); noFill();
    rect(bx + 4, modeY + 4, modeW - 8, modeH - 8, 14);
    strokeWeight(1); noStroke();
    fill(selected ? color(255) : color(60, 70, 80));
    textAlign(CENTER, CENTER);
    textSize(selected ? 30 : 24);
    text((selected ? "▶ " : "") + MENU_ITEMS[i], bx + modeW/2, modeY + modeH/2 - 14);
    textSize(13);
    fill(selected ? color(235, 245, 255) : color(110, 120, 130));
    text(MENU_DESCS[i], bx + modeW/2, modeY + modeH/2 + 28);
  }
  textAlign(LEFT, BASELINE);

  fill(61, 86, 111); textSize(14); textAlign(CENTER, BASELINE);
  text("指揮棒を 左右に振る = 選択を移動  /  縦に振る = 決定", width/2, modeY + modeH + 40);
  textAlign(LEFT, BASELINE);

  drawHelpPanel("[r]ポート再選択  [t]テスト音  [p]音色切替  [+/-]音量");
}

// ── 自由演奏画面 ──────────────────────────────────────────
void drawFreePlayScreen(){
  drawBackground();
  float bpm = uiBpmQ8 / 8.0f;
  drawPageTitle("自由演奏",
      "BPM: " + nf(bpm, 1, 1) + "  /  発音中 " + activeVoices.size() + " / " + MAX_POLYPHONY +
      "  /  音量 " + nf(masterVolume, 1, 2));

  drawScope(28, 96, width - 56, 100);

  // 受信状況
  float sy = 206;
  drawPanel(28, sy, width - 56, 100);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  text("受信状況", 50, sy + 24);
  fill(28, 54, 80); textSize(12);
  text("受信パケット: " + totalReceived +
       (lastNoteAtMs > 0 ? "   (最後の NOTE から " + (millis()-lastNoteAtMs) + " ms)" : ""), 50, sy + 44);
  float ry = sy + 64; int col = 0;
  for (int p = 0x02; p <= 0x06; p++){
    String ev = lastEventByPart[p];
    String label = (p == 0x06) ? "ドラム" : "声部";
    fill(ev != null ? color(28, 54, 80) : color(150, 160, 180));
    text(label + " 0x" + hex(p, 2) + ": " + (ev != null ? ev : "(未受信)"), 50 + col * ((width - 120) / 2), ry);
    col++; if (col >= 2){ col = 0; ry += 18; }
  }

  // BPM 大表示
  drawPanel(28, 316, width - 56, 130);
  fill(18, 54, 88); textSize(60); textAlign(CENTER, CENTER);
  text(nf(bpm, 1, 1), width/2, 365);
  fill(61, 86, 111); textSize(16);
  text("BPM", width/2, 410);
  textAlign(LEFT, BASELINE);

  drawHelpPanel("[r]リセット  [t]テスト音  [p]音色切替  [+/-]音量  [Space]停止");
}

// ── ゲーム演奏画面 ────────────────────────────────────────
void drawGamePlayScreen(){
  drawBackground();
  float bpm = uiBpmQ8 / 8.0f;
  int elapsed = millis() - gameStartMs;
  float intervalMs = uiTargetBpm > 0 ? 60000.0f / (float)uiTargetBpm : 600;
  int elapsedBeats = min((int)(elapsed / intervalMs), GAME_LENGTH_BEATS);
  float guide = gameGuideIntensity(elapsedBeats);
  String scoreStr = (uiScore == 0xFF) ? "採点中" : "" + uiScore;

  drawPageTitle("ゲーム演奏",
      "目標: " + uiTargetBpm + " BPM  /  現在: " + nf(bpm, 1, 1) + " BPM  /  スコア: " + scoreStr);

  // ガイド強度バー
  float barX = 28, barY = 96, barW = width - 56, barH = 32;
  drawPanel(barX, barY, barW, barH);
  fill(64, 159, 255, (int)(guide * 200 + 55));
  noStroke();
  rect(barX + 6, barY + 6, (barW - 12) * guide, barH - 12, 10);
  fill(18, 54, 88); textSize(12); textAlign(LEFT, BASELINE);
  text("ガイド: " + nf(guide * 100, 1, 0) + "%", barX + 14, barY + 22);

  drawScope(28, 138, width - 56, 80);

  // ガイド進捗 (PC ローカルの目標テンポ基準。指揮者が実際に振った拍数とは別物で、
  // ゲームの終了 = 指揮者が 32 拍振った時点。ここはメトロノームの進行を示す)
  float py = 228;
  drawPanel(28, py, width - 56, 60);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  text("ガイド: " + elapsedBeats + " / " + GAME_LENGTH_BEATS + " 拍 (目標テンポ基準)", 50, py + 24);
  float dotStartX = 50, dotY = py + 44, dotR = 10, dotGap = 2;
  for (int i = 0; i < GAME_LENGTH_BEATS; i++){
    float dx = dotStartX + i * (dotR + dotGap);
    if (dx + dotR > width - 50) break;
    noStroke();
    if (i < elapsedBeats) fill(64, 159, 255);
    else if (i < GAME_GUIDE_FULL_BEATS) fill(64, 159, 255, 80);
    else if (i < GAME_GUIDE_ZERO_BEATS) fill(220, 180, 60, 80);
    else fill(200, 200, 200, 60);
    ellipse(dx + dotR/2, dotY, dotR, dotR);
  }

  // スコア表示 (ファームは曲終了まで 0xFF=採点中を送る。確定値は結果画面で出る)
  drawPanel(28, 298, width - 56, 130);
  fill(18, 54, 88); textSize(50); textAlign(CENTER, CENTER);
  text(scoreStr, width/2, 348);
  fill(61, 86, 111); textSize(16);
  text(uiScore == 0xFF ? "スコア (32 拍振り切ると結果画面へ)" : "スコア", width/2, 398);
  textAlign(LEFT, BASELINE);

  // 目標テンポ
  drawPanel(width/2 - 110, 438, 220, 40);
  fill(28, 54, 80); textSize(14); textAlign(CENTER, CENTER);
  text("目標: " + uiTargetBpm + " BPM", width/2, 458);
  textAlign(LEFT, BASELINE);

  drawHelpPanel("[Space]停止  [+/-]音量");
}

// ── 結果画面 ──────────────────────────────────────────────
void drawResultScreen(){
  drawBackground();
  drawPageTitle("ゲーム結果", "");

  drawPanel(width/2 - 200, height/2 - 120, 400, 240);
  fill(18, 54, 88); textSize(22); textAlign(CENTER, BASELINE);
  text("スコア", width/2, height/2 - 70);

  if (uiScore != 0xFF){
    textSize(80); textAlign(CENTER, CENTER);
    if (uiScore >= 80) fill(24, 156, 104);
    else if (uiScore >= 50) fill(220, 180, 40);
    else fill(220, 80, 60);
    text("" + uiScore, width/2, height/2 + 10);
    textSize(22); fill(61, 86, 111); textAlign(CENTER, BASELINE);
    text("/ 100", width/2, height/2 + 55);
  } else {
    textSize(40); fill(120, 130, 150); textAlign(CENTER, CENTER);
    text("---", width/2, height/2 + 10);
  }

  textSize(14); fill(61, 86, 111); textAlign(CENTER, BASELINE);
  text("指揮棒を縦に振るとメニューに戻ります", width/2, height/2 + 100);
  textAlign(LEFT, BASELINE);

  drawHelpPanel("[r]ポート再選択  [+/-]音量  [Space]停止");
}

// ── アナライザ画面 ────────────────────────────────────────
void drawAnalyzerScreen(){
  drawBackground();
  String status = (millis() - lastNoteAtMs < 2000) ? "演奏中" : "待機中";
  drawPageTitle("アナライザ", status + "  /  受信 " + totalReceived + "  /  発音中 " + activeVoices.size());

  drawScope(28, 96, width - 56, 200);

  // 受信状況
  float sy = 306;
  drawPanel(28, sy, width - 56, 100);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  text("直近イベント", 50, sy + 24);
  fill(28, 54, 80); textSize(12);
  float ry = sy + 44; int col = 0;
  for (int p = 0x02; p <= 0x06; p++){
    String ev = lastEventByPart[p];
    if (ev == null) continue;
    text("0x" + hex(p, 2) + ": " + ev, 50 + col * ((width - 120) / 2), ry);
    col++; if (col >= 2){ col = 0; ry += 18; }
  }

  drawHelpPanel("[t]テスト音  [p]音色切替  [+/-]音量  [Space]停止");
}

// 画面下部の共通パネル: 左にキー操作ガイド、右に接続ステータス。
// 接続ステータス = 役割 / UI リンク鮮度 (メイン UI のみ) / 声部別 NOTE 受信インジケータ。
// 「4 台のうちどれが鳴っていないか」「指揮者との UI 中継が生きているか」を常時見せる。
void drawHelpPanel(String helpText){
  float hx = 28, hy = height - 66, hw = width - 56, hh = 48;
  fill(255); noStroke();
  rect(hx, hy, hw, hh, 16);
  stroke(134, 184, 218); strokeWeight(2); noFill();
  rect(hx, hy, hw, hh, 16);
  strokeWeight(1); noStroke();
  fill(28, 54, 80); textSize(13); textAlign(LEFT, BASELINE);
  text(helpText, hx + 22, hy + 28);

  // ── 右側: 接続ステータス ──
  float sx = hx + hw - 22;   // 右端から左へ詰めて描く
  int now = millis();

  // 声部別 NOTE インジケータ (右端)。緑=2 秒以内に受信 / 灰=受信歴あり / 輪郭のみ=未受信
  for (int p = 0x06; p >= 0x02; p--){
    boolean seen   = lastNoteMsByPart[p] > 0;
    boolean active = seen && (now - lastNoteMsByPart[p] < 2000);
    float cxp = sx - 8;
    if (active)      { noStroke(); fill(24, 156, 104); }
    else if (seen)   { noStroke(); fill(170, 180, 190); }
    else             { stroke(170, 180, 190); strokeWeight(1.5f); noFill(); }
    ellipse(cxp, hy + 18, 11, 11);
    noStroke(); fill(110, 125, 140); textSize(9); textAlign(CENTER, BASELINE);
    text(hex(p, 1), cxp, hy + 38);
    sx -= 22;
  }
  fill(110, 125, 140); textSize(10); textAlign(RIGHT, BASELINE);
  text("声部", sx, hy + 22);
  sx -= 38;

  // 役割と UI リンク鮮度
  String roleStr = (nodeRole == ROLE_MAIN_UI) ? "メインUI"
                 : (nodeRole == ROLE_ANALYZER) ? "アナライザ" : "役割判定待ち";
  String linkStr = "";
  int linkCol = color(110, 125, 140);
  if (nodeRole == ROLE_MAIN_UI && lastUiAtMs > 0){
    int age = now - lastUiAtMs;
    if (age < 500){ linkStr = "UI同期OK";  linkCol = color(24, 156, 104); }
    else          { linkStr = "UI遅延 " + nf(age/1000.0f, 1, 1) + "s"; linkCol = color(214, 138, 24); }
  }
  textAlign(RIGHT, BASELINE); textSize(12);
  if (linkStr.length() > 0){
    fill(linkCol); text(linkStr, sx, hy + 28);
    sx -= textWidth(linkStr) + 16;
  }
  fill(61, 86, 111);
  text(roleStr + "  /  ポート " + openByName.size(), sx, hy + 28);
  textAlign(LEFT, BASELINE);
}

// ── ポート一覧 ───────────────────────────────────────────
float portRowX, portRowW, portRowY0, portRowH;
float portViewY, portViewH;
int   portRowCount;

void drawPortListAt(float startY){
  rebuildDisplayPorts();
  float x = 28, y = startY, w = width - 56, h = height - y - 16;
  drawPanel(x, y, w, h);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  String filterTag = usbOnly ? "USB のみ" : "全ポート";
  text("シリアルポート [" + filterTag + " / 表示 " + displayPorts.length + " / 全 " + availablePorts.length + "]",
       x + 22, y + 24);
  fill(61, 86, 111); textSize(12);
  text("クリックで開閉 / ホイールでスクロール / [f] フィルタ切替 / [r] 再列挙", x + 22, y + 42);
  text("node_02 を開くと操作画面、node_03/04 はアナライザ表示になります (受信データから自動判定)", x + 22, y + 58);

  portRowX = x + 16; portRowW = w - 32; portRowY0 = y + 70; portRowH = 40;
  portViewY = portRowY0; portViewH = (y + h) - portRowY0 - 8;
  portRowCount = displayPorts.length;

  if (availablePorts.length == 0){
    fill(197, 83, 31); textSize(13);
    text("シリアルポートが見つかりません。Arduino を USB 接続して 'r' で再列挙してください。", x + 22, y + 70);
    textAlign(LEFT, BASELINE); return;
  }
  if (displayPorts.length == 0){
    fill(197, 83, 31); textSize(13);
    text("USB-only フィルタで全部隠れています。'f' で全表示に切り替えてください。", x + 22, y + 70);
    textAlign(LEFT, BASELINE); return;
  }

  float totalH = portRowCount * portRowH;
  float maxScroll = max(0, totalH - portViewH);
  portScrollY = constrain(portScrollY, 0, maxScroll);

  clip(portRowX - 2, portViewY - 2, portRowW + 4, portViewH + 4);
  for (int i = 0; i < displayPorts.length; i++){
    float ry = portRowY0 + i * portRowH - portScrollY;
    if (ry + portRowH < portViewY) continue;
    if (ry > portViewY + portViewH)  break;
    boolean isOpen = openByName.containsKey(displayPorts[i]);
    boolean isHover = mouseOver(portRowX, ry, portRowW, portRowH - 4)
                   && mouseOver(portRowX, portViewY, portRowW, portViewH);
    int baseFill = isOpen ? color(24, 156, 104) : (isHover ? color(210, 240, 255) : color(255));
    fill(baseFill);
    stroke(isOpen ? color(17, 118, 78) : color(120, 183, 224));
    strokeWeight(2);
    rect(portRowX, ry, portRowW, portRowH - 4, 12);
    strokeWeight(1); noStroke();
    fill(isOpen ? color(255) : color(23, 52, 84)); textSize(14);
    String tag = isOpen ? ("● OPEN  受信 " + openByName.get(displayPorts[i]).rxCount + " 個") : "○ closed";
    text("[" + i + "] " + displayPorts[i] + "    " + tag, portRowX + 16, ry + 24);
  }
  noClip();

  if (maxScroll > 0){
    float sbX = portRowX + portRowW - 6;
    float sbW = 6;
    noStroke(); fill(0, 0, 0, 30);
    rect(sbX, portViewY, sbW, portViewH, 3);
    float thumbH = max(20, portViewH * (portViewH / totalH));
    float thumbY = portViewY + (portViewH - thumbH) * (portScrollY / maxScroll);
    fill(64, 159, 255, 180);
    rect(sbX, thumbY, sbW, thumbH, 3);
  }
  textAlign(LEFT, BASELINE);
}

// ── マウス / キーボード ───────────────────────────────────
void mousePressed(){
  if (currentScreen != SCR_PORT_SELECT) return;
  if (portRowCount <= 0) return;
  if (!mouseOver(portRowX, portViewY, portRowW, portViewH)) return;
  for (int i=0;i<portRowCount;i++){
    float ry = portRowY0 + i*portRowH - portScrollY;
    if (ry + portRowH < portViewY) continue;
    if (ry > portViewY + portViewH)  break;
    if (mouseOver(portRowX, ry, portRowW, portRowH-2)){ togglePort(displayPorts[i]); return; }
  }
}

void mouseWheel(processing.event.MouseEvent e){
  if (currentScreen != SCR_PORT_SELECT) return;
  if (portRowCount <= 0) return;
  portScrollY += e.getCount() * portRowH;
  float totalH = portRowCount * portRowH;
  float maxScroll = max(0, totalH - portViewH);
  portScrollY = constrain(portScrollY, 0, maxScroll);
}

void keyPressed(){
  char c = Character.toLowerCase(key);
  if (c=='r'){
    closeAllPorts();
    refreshPorts();
    println("ポートリセット。ポートを選択してください。");
    return;
  }
  if (c=='i'){ rescanInstruments(); return; }
  if (c=='p'){
    forceSingleInstrument = !forceSingleInstrument;
    println("single-instrument: " + (forceSingleInstrument ? "ON (" + FORCED_INSTRUMENT_FILE + ")" : "OFF"));
    return;
  }
  if (c=='t'){ playTestChord(); return; }
  if (c=='a'){ useSimpleADSR = !useSimpleADSR; println("包絡: " + (useSimpleADSR ? "ADSR4値" : "実エンベロープ")); return; }
  if (c=='+' || c=='='){ masterVolume = constrain(masterVolume + 0.05f, 0.05f, 1.5f); return; }
  if (c=='-' || c=='_'){ masterVolume = constrain(masterVolume - 0.05f, 0.05f, 1.5f); return; }
  if (c==' '){ stopAll(); return; }
  if (c>='0' && c<='3'){ playTestNoteOnInstrument(c - '0'); return; }
  if (c=='f'){
    usbOnly = !usbOnly;
    rebuildDisplayPorts();
    portScrollY = 0;
    println("ポートフィルタ: " + (usbOnly ? "USB のみ" : "全ポート"));
    return;
  }
}

void dispose(){
  closeAllPorts();
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}


/* ==========================================================================
   MetroClick — メトロノームの短いクリック音 (Minim UGen)
   880Hz の正弦波を 50ms だけ鳴らす。ゲーム画面でガイド強度に応じた音量で生成。
   ========================================================================== */
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


/* ==========================================================================
   InstrModel — sound_lab の JSON を解釈して合成に必要な配列を保持。
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


/* ==========================================================================
   ResynthVoice — 1 音ぶんの加算合成ボイス (Minim UGen)。
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
