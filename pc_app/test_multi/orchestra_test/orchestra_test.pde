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
    lastUiAtMs = 0;
  }

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

  // 全体ステータス
  String stateStr = uiReceived ? stateName(uiState) : "UI未受信";
  String modeStr  = uiMode == 0 ? "自由演奏" : "ゲーム";
  float bpm = uiBpmQ8 / 8.0f;
  String scoreStr = (uiScore == 0xFF) ? "---" : "" + uiScore;

  textSize(13); fill(61, 86, 111); textAlign(RIGHT, BASELINE);
  text("State: " + stateStr + "  |  Mode: " + modeStr + "  |  BPM: " + nf(bpm,1,1)
       + "  |  Score: " + scoreStr + "  |  ポート: " + openByName.size()
       + "  |  受信: " + totalReceived + "  |  発音: " + activeVoices.size(),
       width - 20, 36);
  textAlign(LEFT, BASELINE);

  // UIリンク鮮度インジケータ
  int now = millis();
  if (uiReceived && lastUiAtMs > 0){
    int age = now - lastUiAtMs;
    float cx = width - 20;
    if (age < 500){ noStroke(); fill(24, 156, 104); }
    else if (age < 2000){ noStroke(); fill(214, 138, 24); }
    else { noStroke(); fill(220, 60, 60); }
    ellipse(cx, 22, 10, 10);
  }

  // ノードパネル (2行3列)
  float panelW = (width - 60) / 3.0f - 8;
  float panelH = 155;
  float startX = 20, startY = 66;

  for (int i = 0; i < NODE_COUNT; i++){
    int col = i % 3;
    int row = i / 3;
    float px = startX + col * (panelW + 12);
    float py = startY + row * (panelH + 10);
    drawNodePanel(i, px, py, panelW, panelH);
  }

  // 波形
  float scopeY = startY + 2 * (panelH + 10);
  drawScope(20, scopeY, width / 2 - 30, 90);

  // 音量コントロール
  float volX = width / 2 + 10, volY = scopeY;
  drawPanel(volX, volY, width / 2 - 30, 90);
  fill(18, 54, 88); textSize(13); textAlign(LEFT, BASELINE);
  text("音量: " + nf(masterVolume, 1, 2) + "  [+/-]  |  発音中: "
       + activeVoices.size() + "/" + MAX_POLYPHONY + "  |  [t]テスト音  [Space]停止", volX + 16, volY + 24);
  // 音量バー
  float barX = volX + 16, barY = volY + 36, barW = (width/2 - 62), barH = 16;
  noStroke(); fill(220, 225, 235); rect(barX, barY, barW, barH, 6);
  fill(64, 159, 255); rect(barX, barY, barW * constrain(masterVolume / 1.5f, 0, 1), barH, 6);
  // BPM 大表示
  fill(18, 54, 88); textSize(36); textAlign(CENTER, BASELINE);
  text(nf(bpm, 1, 1) + " BPM", volX + (width/2 - 30)/2, volY + 80);
  textAlign(LEFT, BASELINE);

  // ログパネル
  float logY = scopeY + 100;
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
}

void dispose(){
  closeAllPorts();
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}
