/* ==========================================================================
   orchestra_test — マルチ Arduino テストダッシュボード (Processing)

   1 台の PC に全 Arduino (指揮者 + 楽器 4 + ドラム) を USB 接続し、
   全ノードの状態を 1 画面で俯瞰しながらテスト・デバッグする。

   共通ライブラリ (pc_app/common/) の共有タブを利用。
   音色データは production と共有 (data/ → production の data/ へ symlink)。

   起動: processing-java --sketch=<path>/orchestra_test --run
   ログ: stdout に [HH:MM:SS.mmm] [ノードID] [カテゴリ] 形式で出力

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
final int MAX_POLYPHONY = 32;

float   masterVolume  = 0.55f;
boolean useSimpleADSR = true;

// ── オーディオ (共通タブが参照) ──────────────────────────
Minim       minim;
AudioOutput out;

// ── 楽器定義 (共通タブが参照) ────────────────────────────
ArrayList<File>        instrumentFiles = new ArrayList<File>();
ArrayList<InstrModel>  models          = new ArrayList<InstrModel>();
ArrayList<String>      modelLabels     = new ArrayList<String>();

// ── 発音中ボイス (共通タブが参照) ────────────────────────
ArrayList<ResynthVoice> activeVoices = new ArrayList<ResynthVoice>();
DrumTimbreData[] drumTimbres;
AudioSample[] recordedDrumSamples;
ArrayList<ActiveDrumSynth> activeDrumSynths = new ArrayList<ActiveDrumSynth>();
ArrayList<MetroClick> metroClicks = new ArrayList<MetroClick>();

// ── シリアルポート (共通タブが参照) ──────────────────────
String[]                  availablePorts = new String[0];
String[]                  displayPorts   = new String[0];
boolean                   usbOnly        = true;
float                     portScrollY    = 0;
HashMap<String,PortConn>  openByName     = new HashMap<String,PortConn>();
HashMap<Serial,PortConn>  bySerial       = new HashMap<Serial,PortConn>();
ConcurrentLinkedQueue<byte[]> packetQueue = new ConcurrentLinkedQueue<byte[]>();

// ── ノード別状態 ─────────────────────────────────────────
final int NODE_COUNT = 6;  // node_01〜06
final String[] NODE_NAMES = {"指揮者", "Trumpet", "Horn", "Trombone", "Tuba", "Drum"};
final int[] NODE_PART_IDS  = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06};
final int[] NODE_COLORS    = {
  0xFF3C8FFF,  // 指揮者: 青
  0xFFFF6B4A,  // Trumpet: 赤
  0xFF4CAF50,  // Horn: 緑
  0xFFFF9800,  // Trombone: オレンジ
  0xFF9C27B0,  // Tuba: 紫
  0xFF795548   // Drum: 茶
};

int[]    nodePacketCount = new int[NODE_COUNT];
int[]    nodeLastNoteMs  = new int[NODE_COUNT];
String[] nodeLastEvent   = new String[NODE_COUNT];
int[]    nodeNoteNumber  = new int[NODE_COUNT];
int[]    nodeVelocity    = new int[NODE_COUNT];

// ── 全体状態 ─────────────────────────────────────────────
int uiState;
int uiMode;
int uiNavCursor;
int uiTargetBpm;
int uiScore    = 0xFF;
int uiBpmQ8;
int lastUiAtMs;
int totalReceived;
boolean uiReceived = false;

// ── 画面制御 ─────────────────────────────────────────────
final int MODE_PORT_SELECT = 0;
final int MODE_DASHBOARD   = 1;
int displayMode;  // = MODE_PORT_SELECT (0)
float logScrollY = 0;
PFont uiFont;
boolean autoConnect = false;

// ── ゲーム UI 状態 (指揮者パネル用) ────────────────────────
int   gameStartMs           = 0;
int   lastMetroBeat         = -1;
int   conductorScreen       = 1;  // SCR_WAITING
int   prevConductorScreen   = -1;
boolean masterResetDetected = false;

// ────────────────────────────────────────────────────────────
void settings(){ size(1280, 800); }

void setup(){
  frameRate(60);
  surface.setTitle("タクトーン テストダッシュボード");
  uiFont = loadJapaneseFont(13);
  if (uiFont != null) textFont(uiFont);
  else textFont(createFont("SansSerif", 13));

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 512, 44100);

  rescanInstruments();
  loadDrumTimbres();
  refreshPorts();

  orcLogSystem("orchestra_test (マルチ Arduino テスト) 起動");
  orcLogSystem("楽器定義 " + models.size() + " 個、ドラム音色 " + drumTimbres.length + " 個");
  orcLogSystem("操作: [a]自動接続  [r]再列挙  [t]テスト音  [d]ダッシュボード  [+/-]音量  [Space]停止");
}

// ── パケット処理 ─────────────────────────────────────────
void drainPackets(){
  byte[] pkt;
  while ((pkt = packetQueue.poll()) != null) handlePacket(pkt);
}

void handlePacket(byte[] buf){
  totalReceived++;
  int type = packetType(buf);

  if (type == TYPE_UI){
    UiEvent ui = new UiEvent(buf);
    uiState     = ui.state;
    uiMode      = ui.mode;
    uiNavCursor = ui.navCursor;
    uiTargetBpm = ui.targetBpm;
    uiScore     = ui.score;
    uiBpmQ8     = ui.bpmQ8;
    lastUiAtMs  = millis();
    uiReceived  = true;
    masterResetDetected = false;
    orcLogUi(uiState, uiMode, uiTargetBpm, uiScore, uiBpmQ8);
    return;
  }

  if (type != TYPE_NOTE) return;

  NoteEvent n = new NoteEvent(buf);
  int nodeIdx = partIdToNodeIndex(n.partId);

  if (nodeIdx >= 0){
    nodePacketCount[nodeIdx]++;
    nodeLastNoteMs[nodeIdx] = millis();
    nodeNoteNumber[nodeIdx] = n.noteNumber;
    nodeVelocity[nodeIdx]   = n.velocity;
    nodeLastEvent[nodeIdx]  = noteName(n.noteNumber) + " v=" + n.velocity + " " + n.durationMs + "ms";
  }

  if (n.gate == 1){
    orcLogNote(n.partId, n.noteNumber, n.velocity, n.durationMs, n.instrumentId);
    triggerNote(n.partId, n.instrumentId, n.noteNumber, n.velocity, n.durationMs);
  } else {
    if (!isDrumInstrument(n.instrumentId)){
      int releaseMidi = n.noteNumber + brassOctaveShift(n.instrumentId);
      releaseMatching(n.partId, releaseMidi);
    }
  }
}

int partIdToNodeIndex(int partId){
  for (int i = 0; i < NODE_COUNT; i++)
    if (NODE_PART_IDS[i] == partId) return i;
  return -1;
}

// ── 自動接続 ─────────────────────────────────────────────
void autoConnectPorts(){
  refreshPorts();
  int connected = 0;
  for (String name : availablePorts){
    if (isUsbSerialName(name) && !openByName.containsKey(name)){
      openPort(name);
      orcLogSerial(name, "自動接続");
      connected++;
    }
  }
  if (connected > 0){
    orcLogSystem(connected + " ポート自動接続完了 (合計 " + openByName.size() + ")");
    displayMode = MODE_DASHBOARD;
  } else {
    orcLogSystem("USB シリアルポートが見つかりません");
  }
}

// ── 描画ループ ───────────────────────────────────────────
void draw(){
  drainPackets();
  updateVoiceLifecycle();

  // UIパケットタイムアウト検知
  if (uiReceived && lastUiAtMs > 0 && millis() - lastUiAtMs > UI_TIMEOUT_MS){
    orcLogError("CTRL", "UIパケットタイムアウト (" + UI_TIMEOUT_MS + "ms) — マスターリセットの可能性");
    uiState = ST_IDLE;
    uiScore = 0xFF;
    lastUiAtMs = 0;
    masterResetDetected = true;
    gameStartMs = 0;
    lastMetroBeat = -1;
    stopAll();
  }

  // 指揮者画面判定とメトロノーム
  conductorScreen = determineConductorScreen();
  if (conductorScreen != prevConductorScreen){
    onConductorScreenChange(prevConductorScreen, conductorScreen);
    prevConductorScreen = conductorScreen;
  }
  updateMetronome();

  if (displayMode == MODE_PORT_SELECT) drawPortSelectMode();
  else drawDashboard();
}

// ── ポート選択モード ─────────────────────────────────────
void drawPortSelectMode(){
  drawBackground();
  drawPageTitle("テストダッシュボード",
      "Arduino を USB 接続して選択  /  [a]全自動接続  [r]再列挙  [d]ダッシュボード表示");
  drawPortListAt(96);
}

// ── ポート一覧 (production と同じ) ──────────────────────
float portRowX, portRowW, portRowY0, portRowH;
float portViewY, portViewH;
int   portRowCount;

void drawPortListAt(float startY){
  rebuildDisplayPorts();
  float x = 28, y = startY, w = width - 56, h = height - y - 16;
  drawPanel(x, y, w, h);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  String filterTag = usbOnly ? "USB のみ" : "全ポート";
  text("シリアルポート [" + filterTag + " / 表示 " + displayPorts.length + " / 全 " + availablePorts.length
       + " / 接続中 " + openByName.size() + "]", x + 22, y + 24);
  fill(61, 86, 111); textSize(12);
  text("[click]開閉 / [a]全自動接続 / [f]フィルタ / [r]再列挙 / [d]ダッシュボード", x + 22, y + 42);

  portRowX = x + 16; portRowW = w - 32; portRowY0 = y + 56; portRowH = 40;
  portViewY = portRowY0; portViewH = (y + h) - portRowY0 - 8;
  portRowCount = displayPorts.length;

  if (displayPorts.length == 0){
    fill(197, 83, 31); textSize(13);
    text("USB シリアルが見つかりません。Arduino を接続して [r] で再列挙してください。", x + 22, y + 70);
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
  textAlign(LEFT, BASELINE);
}

// ── ダッシュボード画面 ──────────────────────────────────
void drawDashboard(){
  background(232, 238, 245);

  // ヘッダー
  noStroke(); fill(255, 255, 255, 200);
  rect(0, 0, width, 56);
  stroke(180, 200, 220); strokeWeight(1); line(0, 56, width, 56); noStroke();

  fill(18, 54, 88); textSize(22); textAlign(LEFT, BASELINE);
  text("タクトーン テストダッシュボード", 20, 36);

  textSize(13); fill(61, 86, 111); textAlign(RIGHT, BASELINE);
  text("ポート: " + openByName.size() + "  |  受信: " + totalReceived
       + "  |  発音: " + activeVoices.size(), width - 20, 36);
  textAlign(LEFT, BASELINE);

  // UIリンク鮮度インジケータ
  if (uiReceived && lastUiAtMs > 0){
    int age = millis() - lastUiAtMs;
    float cx = width - 20;
    if (age < 500) fill(24, 156, 104);
    else if (age < 2000) fill(214, 138, 24);
    else fill(220, 60, 60);
    noStroke(); ellipse(cx, 22, 10, 10);
  }

  // 指揮者ゲーム UI パネル (フル幅)
  float condX = 20, condY = 66;
  float condW = width - 40, condH = 240;
  drawConductorGamePanel(condX, condY, condW, condH);

  // 楽器ノードパネル (5台横一列)
  float instrGap = 12;
  float instrStartY = condY + condH + 10;
  float instrPanelW = (width - 40 - (NODE_COUNT - 2) * instrGap) / (float)(NODE_COUNT - 1);
  float instrPanelH = 150;
  for (int i = 1; i < NODE_COUNT; i++){
    float px = 20 + (i - 1) * (instrPanelW + instrGap);
    drawNodePanel(i, px, instrStartY, instrPanelW, instrPanelH);
  }

  // 波形
  float scopeY = instrStartY + instrPanelH + 10;
  drawScope(20, scopeY, width / 2 - 30, 80);

  // 音量コントロール
  float volX = width / 2 + 10, volY = scopeY;
  float volW = width / 2 - 30, volH = 80;
  drawPanel(volX, volY, volW, volH);
  fill(18, 54, 88); textSize(13); textAlign(LEFT, BASELINE);
  text("音量: " + nf(masterVolume, 1, 2) + "  [+/-]  |  発音中: "
       + activeVoices.size() + "/" + MAX_POLYPHONY + "  |  [t]テスト音  [Space]停止", volX + 16, volY + 24);
  float barX = volX + 16, barY = volY + 36, barW = (volW - 32), barH = 14;
  noStroke(); fill(220, 225, 235); rect(barX, barY, barW, barH, 6);
  fill(64, 159, 255); rect(barX, barY, barW * constrain(masterVolume / 1.5f, 0, 1), barH, 6);
  float bpmVal = uiBpmQ8 / 8.0f;
  fill(18, 54, 88); textSize(28); textAlign(CENTER, BASELINE);
  text(nf(bpmVal, 1, 1) + " BPM", volX + volW/2, volY + 72);
  textAlign(LEFT, BASELINE);

  // ログパネル
  float logY = scopeY + 90;
  float logH = height - logY - 10;
  int maxLogLines = (int)((logH - 30) / 13);
  drawLogPanel(20, logY, width - 40, logH, maxLogLines);
}

// ── ノードパネル ─────────────────────────────────────────
void drawNodePanel(int idx, float x, float y, float w, float h){
  int now = millis();
  boolean active = nodeLastNoteMs[idx] > 0 && (now - nodeLastNoteMs[idx] < 2000);
  boolean seen   = nodeLastNoteMs[idx] > 0;
  boolean isCtrl = (idx == 0);
  boolean ctrlActive = isCtrl && uiReceived && lastUiAtMs > 0 && (now - lastUiAtMs < 2000);

  // パネル背景
  noStroke();
  fill(23, 60, 95, 20); rect(x + 4, y + 5, w, h, 14);
  fill(255); rect(x, y, w, h, 14);

  // 左端にノード色のアクセントライン
  noStroke(); fill(NODE_COLORS[idx]);
  rect(x, y, 5, h, 14, 0, 0, 14);

  // ヘッダー
  fill(NODE_COLORS[idx]); textSize(14); textAlign(LEFT, BASELINE);
  text(NODE_NAMES[idx], x + 14, y + 20);
  fill(100, 110, 130); textSize(11);
  text("node_" + nf(idx + 1, 2) + "  (0x" + hex(NODE_PART_IDS[idx], 2) + ")", x + 14, y + 36);

  // 接続インジケータ
  float indX = x + w - 16;
  if (active || ctrlActive){
    noStroke(); fill(24, 156, 104);
    ellipse(indX, y + 16, 12, 12);
  } else if (seen || (isCtrl && uiReceived)){
    noStroke(); fill(200, 200, 200);
    ellipse(indX, y + 16, 12, 12);
  } else {
    stroke(180); strokeWeight(1.5f); noFill();
    ellipse(indX, y + 16, 12, 12);
    noStroke();
  }

  // 区切り線
  stroke(220, 228, 240); strokeWeight(1);
  line(x + 10, y + 42, x + w - 10, y + 42);
  noStroke();

  float ty = y + 58;

  if (isCtrl){
    // 指揮者パネル: UIパケット情報
    fill(40, 50, 70); textSize(11); textAlign(LEFT, BASELINE);
    String st = uiReceived ? stateName(uiState) : "未受信";
    text("状態: " + st, x + 14, ty);
    ty += 16;
    text("モード: " + (uiMode == 0 ? "自由演奏" : "ゲーム"), x + 14, ty);
    ty += 16;
    float bpm = uiBpmQ8 / 8.0f;
    text("BPM: " + nf(bpm, 1, 1) + "  (目標: " + uiTargetBpm + ")", x + 14, ty);
    ty += 16;
    String sc = (uiScore == 0xFF) ? "---" : "" + uiScore + "/100";
    text("スコア: " + sc, x + 14, ty);
    ty += 16;
    if (uiReceived && lastUiAtMs > 0){
      int age = now - lastUiAtMs;
      fill(age < 500 ? color(24, 156, 104) : (age < 2000 ? color(214, 138, 24) : color(220, 60, 60)));
      text("UI: " + age + "ms 前", x + 14, ty);
    } else {
      fill(180); text("UI: ---", x + 14, ty);
    }
  } else {
    // 楽器パネル
    fill(40, 50, 70); textSize(11); textAlign(LEFT, BASELINE);
    text("受信: " + nodePacketCount[idx] + " パケット", x + 14, ty);
    ty += 16;

    if (seen){
      int age = now - nodeLastNoteMs[idx];
      fill(active ? color(24, 156, 104) : color(150, 160, 175));
      text("最終: " + age + "ms 前", x + 14, ty);
      ty += 16;

      fill(40, 50, 70);
      String ev = nodeLastEvent[idx];
      if (ev != null){
        text("NOTE: " + ev, x + 14, ty);
        ty += 16;
      }

      // ミニ鍵盤表示 (最後のノート番号)
      if (nodeNoteNumber[idx] > 0){
        drawMiniKeyboard(x + 14, ty, w - 28, 20, nodeNoteNumber[idx]);
        ty += 24;
      }

      // ベロシティバー
      float velRatio = nodeVelocity[idx] / 127.0f;
      noStroke(); fill(230, 235, 242); rect(x + 14, ty, w - 28, 8, 4);
      fill(NODE_COLORS[idx]); rect(x + 14, ty, (w - 28) * velRatio, 8, 4);
      fill(100, 110, 130); textSize(9);
      text("vel " + nodeVelocity[idx], x + 14, ty + 18);
    } else {
      fill(180); text("データ未受信", x + 14, ty);
    }
  }
  textAlign(LEFT, BASELINE);
}

// ── ミニ鍵盤 ────────────────────────────────────────────
void drawMiniKeyboard(float x, float y, float w, float h, int activeNote){
  int startOctave = max(0, (activeNote / 12) - 1);
  int startMidi = startOctave * 12;
  int keyCount = min(36, 127 - startMidi);
  float keyW = w / keyCount;

  for (int i = 0; i < keyCount; i++){
    int midi = startMidi + i;
    int pc = midi % 12;
    boolean isBlack = (pc==1||pc==3||pc==6||pc==8||pc==10);
    boolean isActive = (midi == activeNote);

    if (isBlack){
      noStroke();
      fill(isActive ? color(255, 80, 80) : color(60, 60, 70));
      rect(x + i * keyW, y, keyW, h * 0.65f, 1);
    } else {
      stroke(200); strokeWeight(0.5f);
      fill(isActive ? color(64, 159, 255) : color(255));
      rect(x + i * keyW, y, keyW, h, 1);
      noStroke();
    }
  }
}

// ── 指揮者画面判定 ──────────────────────────────────────────
int determineConductorScreen(){
  if (!uiReceived) return SCR_WAITING;
  switch (uiState){
    case ST_MENU:       return SCR_MENU;
    case ST_CONDUCTING: return uiMode == 1 ? SCR_GAME_PLAY : SCR_FREE_PLAY;
    case ST_RESULT:     return SCR_RESULT;
    default:            return SCR_WAITING;
  }
}

void onConductorScreenChange(int fromScr, int toScr){
  if (toScr == SCR_GAME_PLAY){
    gameStartMs = millis();
    lastMetroBeat = -1;
  }
  if (toScr == SCR_MENU || toScr == SCR_WAITING){
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
  if (conductorScreen != SCR_GAME_PLAY) return;
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

// ── 指揮者ゲーム UI パネル ──────────────────────────────────
void drawConductorGamePanel(float x, float y, float w, float h){
  int now = millis();
  boolean ctrlActive = uiReceived && lastUiAtMs > 0 && (now - lastUiAtMs < 2000);

  // パネル背景
  noStroke();
  fill(23, 60, 95, 20); rect(x + 4, y + 5, w, h, 14);
  fill(255); rect(x, y, w, h, 14);

  // 左端ノード色アクセントライン
  noStroke(); fill(NODE_COLORS[0]);
  rect(x, y, 5, h, 14, 0, 0, 14);

  // 接続インジケータ (右上)
  float indX = x + w - 16;
  if (ctrlActive){ noStroke(); fill(24, 156, 104); ellipse(indX, y + 16, 12, 12); }
  else if (uiReceived){ noStroke(); fill(200, 200, 200); ellipse(indX, y + 16, 12, 12); }
  else { stroke(180); strokeWeight(1.5f); noFill(); ellipse(indX, y + 16, 12, 12); noStroke(); }

  // UI 鮮度表示
  if (uiReceived && lastUiAtMs > 0){
    int age = now - lastUiAtMs;
    textSize(10); textAlign(RIGHT, BASELINE);
    fill(age < 500 ? color(24, 156, 104) : (age < 2000 ? color(214, 138, 24) : color(220, 60, 60)));
    text("UI: " + age + "ms", indX - 18, y + 20);
    textAlign(LEFT, BASELINE);
  }

  // コンテンツ領域
  float cx = x + 14, cy = y + 6, cw = w - 28, ch = h - 16;

  switch (conductorScreen){
    case SCR_MENU:      drawCondMenu(cx, cy, cw, ch);      break;
    case SCR_FREE_PLAY: drawCondFreePlay(cx, cy, cw, ch);  break;
    case SCR_GAME_PLAY: drawCondGamePlay(cx, cy, cw, ch);  break;
    case SCR_RESULT:    drawCondResult(cx, cy, cw, ch);    break;
    default:            drawCondWaiting(cx, cy, cw, ch);   break;
  }
}

// ── 待機画面 ────────────────────────────────────────────────
void drawCondWaiting(float x, float y, float w, float h){
  fill(NODE_COLORS[0]); textSize(14); textAlign(LEFT, BASELINE);
  text("指揮者", x, y + 18);
  fill(100, 110, 130); textSize(11);
  text("node_01 (0x01)", x + 60, y + 18);
  stroke(220, 228, 240); strokeWeight(1);
  line(x, y + 26, x + w, y + 26); noStroke();

  String title, desc;
  switch (uiState){
    case ST_CALIBRATING:
      title = "キャリブレーション中...";
      desc  = "指揮棒を静止させたまま約 2 秒待ってください";
      break;
    case ST_FALLBACK:
      title = "一時停止 (Fallback)";
      desc  = "指揮者の IMU / WiFi が停止しています";
      break;
    default:
      title = uiReceived ? "待機中" : "データ待ち...";
      desc  = "指揮者の起動とキャリブレーション完了を待っています";
      break;
  }

  float centerX = x + w / 2;
  float centerY = y + h / 2 + 10;
  float panW = 400, panH = 100;
  noStroke(); fill(240, 245, 252);
  rect(centerX - panW/2, centerY - panH/2, panW, panH, 14);
  stroke(200, 215, 230); strokeWeight(1.5f); noFill();
  rect(centerX - panW/2, centerY - panH/2, panW, panH, 14);
  strokeWeight(1); noStroke();

  fill(18, 54, 88); textSize(22); textAlign(CENTER, CENTER);
  text(title, centerX, centerY - 15);
  fill(61, 86, 111); textSize(13);
  text(desc, centerX, centerY + 15);
  if (masterResetDetected){
    fill(197, 83, 31); textSize(12);
    text("指揮者の再起動を検知しました", centerX, centerY + 42);
  }
  textAlign(LEFT, BASELINE);
}

// ── メニュー画面 ────────────────────────────────────────────
void drawCondMenu(float x, float y, float w, float h){
  fill(NODE_COLORS[0]); textSize(14); textAlign(LEFT, BASELINE);
  text("指揮者 — メニュー", x, y + 18);
  fill(61, 86, 111); textSize(11);
  text("IMU 操作でカーソルが動きます", x + 145, y + 18);
  stroke(220, 228, 240); strokeWeight(1);
  line(x, y + 26, x + w, y + 26); noStroke();

  float modeW = 220, modeH = min(130, h - 70);
  float gap = 50;
  float totalW = 2 * modeW + gap;
  float startX = x + (w - totalW) / 2;
  float modeY = y + 38;

  for (int i = 0; i < MENU_ITEMS.length; i++){
    float bx = startX + i * (modeW + gap);
    boolean selected = (uiNavCursor == i);
    int baseCol = (i == 0) ? color(64, 159, 255) : color(24, 156, 104);

    noStroke();
    fill(23, 52, 84, 45); rect(bx + 6, modeY + 8, modeW, modeH, 16);
    fill(selected ? baseCol : color(226, 231, 236));
    rect(bx, modeY, modeW, modeH, 16);
    stroke(selected ? color(255) : color(186, 196, 206));
    strokeWeight(2.5f); noFill();
    rect(bx + 3, modeY + 3, modeW - 6, modeH - 6, 13);
    strokeWeight(1); noStroke();

    fill(selected ? color(255) : color(60, 70, 80));
    textAlign(CENTER, CENTER);
    textSize(selected ? 26 : 20);
    text((selected ? "▶ " : "") + MENU_ITEMS[i], bx + modeW/2, modeY + modeH/2 - 12);
    textSize(12);
    fill(selected ? color(235, 245, 255) : color(110, 120, 130));
    text(MENU_DESCS[i], bx + modeW/2, modeY + modeH/2 + 18);
  }

  fill(61, 86, 111); textSize(12); textAlign(CENTER, BASELINE);
  text("左右に振る = 選択移動  /  縦に振る = 決定", x + w/2, y + h - 6);
  textAlign(LEFT, BASELINE);
}

// ── 自由演奏画面 ────────────────────────────────────────────
void drawCondFreePlay(float x, float y, float w, float h){
  float bpm = uiBpmQ8 / 8.0f;

  fill(NODE_COLORS[0]); textSize(14); textAlign(LEFT, BASELINE);
  text("指揮者 — 自由演奏", x, y + 18);
  fill(61, 86, 111); textSize(11);
  text("発音中 " + activeVoices.size() + " / " + MAX_POLYPHONY
       + "  |  音量 " + nf(masterVolume, 1, 2), x + 150, y + 18);
  stroke(220, 228, 240); strokeWeight(1);
  line(x, y + 26, x + w, y + 26); noStroke();

  // BPM 大表示 (中央)
  float centerX = x + w / 2;
  float panW = 300, panH = min(130, h - 50);
  float panY = y + 36;
  noStroke(); fill(240, 245, 252);
  rect(centerX - panW/2, panY, panW, panH, 14);
  stroke(200, 215, 230); strokeWeight(1.5f); noFill();
  rect(centerX - panW/2, panY, panW, panH, 14);
  strokeWeight(1); noStroke();

  fill(18, 54, 88); textSize(56); textAlign(CENTER, CENTER);
  text(nf(bpm, 1, 1), centerX, panY + panH/2 - 10);
  fill(61, 86, 111); textSize(16);
  text("BPM", centerX, panY + panH/2 + 30);

  // 左側: 受信状況
  float infoX = x + 20;
  float iy = panY + 14;
  fill(18, 54, 88); textSize(12); textAlign(LEFT, BASELINE);
  text("受信状況", infoX, iy); iy += 18;
  fill(28, 54, 80); textSize(11);
  text("合計: " + totalReceived + " パケット", infoX, iy); iy += 18;
  int now = millis();
  for (int p = 0x02; p <= 0x06; p++){
    int ni = partIdToNodeIndex(p);
    if (ni < 0) continue;
    boolean active = nodeLastNoteMs[ni] > 0 && (now - nodeLastNoteMs[ni] < 2000);
    noStroke();
    fill(active ? color(24, 156, 104) : color(200, 210, 220));
    ellipse(infoX + 4, iy - 4, 7, 7);
    fill(active ? color(28, 54, 80) : color(150, 160, 180));
    text(NODE_NAMES[ni], infoX + 14, iy);
    iy += 15;
  }

  // 右側: 直近イベント
  float rInfoX = centerX + panW/2 + 40;
  float riy = panY + 14;
  fill(18, 54, 88); textSize(12); textAlign(LEFT, BASELINE);
  text("直近イベント", rInfoX, riy); riy += 18;
  fill(28, 54, 80); textSize(11);
  for (int p = 0x02; p <= 0x06; p++){
    int ni = partIdToNodeIndex(p);
    if (ni < 0) continue;
    String ev = nodeLastEvent[ni];
    if (ev == null) continue;
    fill(28, 54, 80);
    text(NODE_NAMES[ni] + ": " + ev, rInfoX, riy);
    riy += 15;
  }

  textAlign(LEFT, BASELINE);
}

// ── ゲーム演奏画面 ──────────────────────────────────────────
void drawCondGamePlay(float x, float y, float w, float h){
  float bpm = uiBpmQ8 / 8.0f;
  int elapsed = millis() - gameStartMs;
  float intervalMs = uiTargetBpm > 0 ? 60000.0f / (float)uiTargetBpm : 600;
  int elapsedBeats = min((int)(elapsed / intervalMs), GAME_LENGTH_BEATS);
  float guide = gameGuideIntensity(elapsedBeats);
  String scoreStr = (uiScore == 0xFF) ? "採点中" : "" + uiScore;

  // ヘッダー
  fill(NODE_COLORS[0]); textSize(14); textAlign(LEFT, BASELINE);
  text("指揮者 — ゲーム演奏", x, y + 18);
  fill(61, 86, 111); textSize(11);
  text("目標: " + uiTargetBpm + " BPM  |  現在: " + nf(bpm, 1, 1) + " BPM  |  スコア: " + scoreStr,
       x + 160, y + 18);
  stroke(220, 228, 240); strokeWeight(1);
  line(x, y + 26, x + w, y + 26); noStroke();

  // ガイドバー (全幅)
  float barY = y + 34, barH = 24;
  noStroke(); fill(235, 240, 248);
  rect(x, barY, w, barH, 8);
  fill(64, 159, 255, (int)(guide * 200 + 55));
  rect(x + 3, barY + 3, (w - 6) * guide, barH - 6, 6);
  fill(18, 54, 88); textSize(11); textAlign(LEFT, BASELINE);
  text("ガイド: " + nf(guide * 100, 1, 0) + "%", x + 10, barY + 16);

  float contentY = barY + barH + 8;
  float contentH = h - (contentY - y) - 6;

  // 3列レイアウト: 進捗 | スコア | BPM
  float col1W = w * 0.38f;
  float col2W = w * 0.30f;
  float col3W = w * 0.32f;

  // 左列: 進捗ドット + 拍数
  fill(18, 54, 88); textSize(12); textAlign(LEFT, BASELINE);
  text(elapsedBeats + " / " + GAME_LENGTH_BEATS + " 拍 (目標テンポ基準)", x + 8, contentY + 14);

  float dotR = 8, dotGap = 2;
  int dotsPerRow = max(1, (int)((col1W - 20) / (dotR + dotGap)));
  float dotBaseY = contentY + 26;
  for (int i = 0; i < GAME_LENGTH_BEATS; i++){
    int drow = i / dotsPerRow;
    int dcol = i % dotsPerRow;
    float dx = x + 8 + dcol * (dotR + dotGap);
    float dy = dotBaseY + drow * (dotR + 4);
    if (dy + dotR > contentY + contentH - 20) break;
    noStroke();
    if (i < elapsedBeats) fill(64, 159, 255);
    else if (i < GAME_GUIDE_FULL_BEATS) fill(64, 159, 255, 80);
    else if (i < GAME_GUIDE_ZERO_BEATS) fill(220, 180, 60, 80);
    else fill(200, 200, 200, 60);
    ellipse(dx + dotR/2, dy, dotR, dotR);
  }

  fill(28, 54, 80); textSize(13); textAlign(LEFT, BASELINE);
  text("目標: " + uiTargetBpm + " BPM", x + 8, contentY + contentH - 4);

  // 中央列: スコア大表示
  float scoreX = x + col1W;
  noStroke(); fill(240, 245, 252);
  rect(scoreX + 8, contentY, col2W - 16, contentH, 12);
  stroke(200, 215, 230); strokeWeight(1.5f); noFill();
  rect(scoreX + 8, contentY, col2W - 16, contentH, 12);
  strokeWeight(1); noStroke();

  fill(18, 54, 88); textSize(46); textAlign(CENTER, CENTER);
  text(scoreStr, scoreX + col2W/2, contentY + contentH/2 - 8);
  fill(61, 86, 111); textSize(13);
  text(uiScore == 0xFF ? "スコア" : "/ 100", scoreX + col2W/2, contentY + contentH/2 + 28);

  // 右列: 現在 BPM
  float rightX = x + col1W + col2W;
  fill(18, 54, 88); textSize(38); textAlign(CENTER, CENTER);
  text(nf(bpm, 1, 1), rightX + col3W/2, contentY + contentH/2 - 14);
  fill(61, 86, 111); textSize(14);
  text("BPM", rightX + col3W/2, contentY + contentH/2 + 16);
  fill(28, 54, 80); textSize(11);
  text("発音中: " + activeVoices.size(), rightX + col3W/2, contentY + contentH - 4);

  textAlign(LEFT, BASELINE);
}

// ── 結果画面 ────────────────────────────────────────────────
void drawCondResult(float x, float y, float w, float h){
  fill(NODE_COLORS[0]); textSize(14); textAlign(LEFT, BASELINE);
  text("指揮者 — ゲーム結果", x, y + 18);
  stroke(220, 228, 240); strokeWeight(1);
  line(x, y + 26, x + w, y + 26); noStroke();

  float centerX = x + w / 2;
  float centerY = y + h / 2 + 10;
  float panW = 360, panH = min(150, h - 50);
  noStroke(); fill(240, 245, 252);
  rect(centerX - panW/2, centerY - panH/2, panW, panH, 14);
  stroke(200, 215, 230); strokeWeight(1.5f); noFill();
  rect(centerX - panW/2, centerY - panH/2, panW, panH, 14);
  strokeWeight(1); noStroke();

  fill(18, 54, 88); textSize(20); textAlign(CENTER, BASELINE);
  text("スコア", centerX, centerY - panH/2 + 28);

  if (uiScore != 0xFF){
    textSize(72); textAlign(CENTER, CENTER);
    if (uiScore >= 80) fill(24, 156, 104);
    else if (uiScore >= 50) fill(220, 180, 40);
    else fill(220, 80, 60);
    text("" + uiScore, centerX, centerY + 4);
    textSize(20); fill(61, 86, 111); textAlign(CENTER, BASELINE);
    text("/ 100", centerX, centerY + 40);
  } else {
    textSize(40); fill(120, 130, 150); textAlign(CENTER, CENTER);
    text("---", centerX, centerY + 4);
  }

  textSize(13); fill(61, 86, 111); textAlign(CENTER, BASELINE);
  text("指揮棒を縦に振るとメニューに戻ります", centerX, centerY + panH/2 - 10);
  textAlign(LEFT, BASELINE);
}

// ── マウス / キーボード ──────────────────────────────────
void mousePressed(){
  if (displayMode == MODE_PORT_SELECT){
    if (portRowCount <= 0) return;
    if (!mouseOver(portRowX, portViewY, portRowW, portViewH)) return;
    for (int i = 0; i < portRowCount; i++){
      float ry = portRowY0 + i * portRowH - portScrollY;
      if (ry + portRowH < portViewY) continue;
      if (ry > portViewY + portViewH) break;
      if (mouseOver(portRowX, ry, portRowW, portRowH - 2)){
        togglePort(displayPorts[i]);
        return;
      }
    }
  }
}

void mouseWheel(processing.event.MouseEvent e){
  if (displayMode == MODE_PORT_SELECT){
    if (portRowCount <= 0) return;
    portScrollY += e.getCount() * portRowH;
    float totalH = portRowCount * portRowH;
    float maxScroll = max(0, totalH - portViewH);
    portScrollY = constrain(portScrollY, 0, maxScroll);
  }
}

void keyPressed(){
  char c = Character.toLowerCase(key);
  if (c == 'r'){
    closeAllPorts();
    refreshPorts();
    displayMode = MODE_PORT_SELECT;
    resetNodeState();
    orcLogSystem("ポートリセット");
    return;
  }
  if (c == 'a'){
    autoConnectPorts();
    return;
  }
  if (c == 'd'){
    displayMode = (displayMode == MODE_DASHBOARD) ? MODE_PORT_SELECT : MODE_DASHBOARD;
    return;
  }
  if (c == 't'){ playTestChord(); return; }
  if (c == '+' || c == '='){ masterVolume = constrain(masterVolume + 0.05f, 0.05f, 1.5f); return; }
  if (c == '-' || c == '_'){ masterVolume = constrain(masterVolume - 0.05f, 0.05f, 1.5f); return; }
  if (c == ' '){ stopAll(); return; }
  if (c == 'f'){
    usbOnly = !usbOnly;
    rebuildDisplayPorts();
    portScrollY = 0;
    orcLogSystem("ポートフィルタ: " + (usbOnly ? "USB のみ" : "全ポート"));
    return;
  }
  if (c >= '0' && c <= '3'){ playTestNoteOnInstrument(c - '0'); return; }
}

void resetNodeState(){
  for (int i = 0; i < NODE_COUNT; i++){
    nodePacketCount[i] = 0;
    nodeLastNoteMs[i]  = 0;
    nodeLastEvent[i]   = null;
    nodeNoteNumber[i]  = 0;
    nodeVelocity[i]    = 0;
  }
  uiReceived = false;
  uiState = ST_IDLE;
  uiScore = 0xFF;
  totalReceived = 0;
  gameStartMs = 0;
  lastMetroBeat = -1;
  conductorScreen = SCR_WAITING;
  prevConductorScreen = -1;
  masterResetDetected = false;
  for (MetroClick mc : metroClicks) mc.unpatch(out);
  metroClicks.clear();
}

void dispose(){
  closeAllPorts();
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}
