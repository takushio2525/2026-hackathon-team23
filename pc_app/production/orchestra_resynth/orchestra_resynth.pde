/* ==========================================================================
   orchestra_resynth — production ゲームモード対応 PC 側プログラム (Processing)

   firmware/production の楽器ノード (Arduino UNO R4 WiFi) から USB Serial で送られて
   くる NOTE パケット (type=3, 20B) と UI 状態パケット (type=4, 20B) を受信し、
   NOTE は加算合成で発音、UI は画面を自動判定して描画する。

   共通ライブラリ (pc_app/common/) の共有タブを利用:
     OrcProtocol.pde  — 定数・パケットパース
     InstrModel.pde   — 楽器定義 JSON 読込
     SynthVoice.pde   — 加算合成ボイス
     DrumEngine.pde   — ドラム音色・合成
     AudioManager.pde — 発音管理
     SerialCore.pde   — シリアルポート管理
     SharedUI.pde     — 共通 UI 部品
     OrcLogger.pde    — 構造化ログ

   必要ライブラリ: Minim
   ========================================================================== */

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*;
import java.util.Iterator;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.io.File;

// ── production 固有設定 ──────────────────────────────────
final int MAX_POLYPHONY = 24;

float   masterVolume  = 0.55f;
boolean useSimpleADSR = false;

// ── オーディオ (共通タブの AudioManager/DrumEngine が参照) ──
Minim       minim;
AudioOutput out;

// ── 楽器定義 (共通タブの AudioManager が参照) ────────────
ArrayList<File>        instrumentFiles = new ArrayList<File>();
ArrayList<InstrModel>  models          = new ArrayList<InstrModel>();
ArrayList<String>      modelLabels     = new ArrayList<String>();

// ── 発音中ボイス (共通タブの AudioManager が参照) ────────
ArrayList<ResynthVoice> activeVoices = new ArrayList<ResynthVoice>();
DrumTimbreData[] drumTimbres;
AudioSample[] recordedDrumSamples;
ArrayList<ActiveDrumSynth> activeDrumSynths = new ArrayList<ActiveDrumSynth>();
ArrayList<MetroClick> metroClicks = new ArrayList<MetroClick>();

// ── シリアルポート (共通タブの SerialCore が参照) ────────
String[]                  availablePorts = new String[0];
String[]                  displayPorts   = new String[0];
boolean                   usbOnly        = true;
float                     portScrollY    = 0;
HashMap<String,PortConn>  openByName     = new HashMap<String,PortConn>();
HashMap<Serial,PortConn>  bySerial       = new HashMap<Serial,PortConn>();
ConcurrentLinkedQueue<byte[]> packetQueue = new ConcurrentLinkedQueue<byte[]>();

// ── 表示用 ────────────────────────────────────────────────
int      totalReceived = 0;
String[] lastEventByPart = new String[256];
int[]    lastNoteMsByPart = new int[256];
int      lastNoteAtMs   = 0;
PFont    uiFont;

// ── UI 状態 (type=4 から更新) ─────────────────────────────
// ROLE_UNKNOWN=0, ST_IDLE=0 → int のデフォルト値と同じ (共通タブの定数は前方参照不可)
int nodeRole;
int uiState;
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
int   currentScreen;  // SCR_PORT_SELECT=0 → デフォルト値と同じ
int   prevScreen      = -1;

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
  loadDrumTimbres();
  refreshPorts();

  orcLogSystem("orchestra_resynth (production ゲームモード) 起動");
  orcLogSystem("楽器定義 " + models.size() + " 個ロード。ドラム音色 " + drumTimbres.length + " 個。");
  println("[click] ポート開閉  /  [r] ポート再列挙・画面リセット  /  [f] USBフィルタ  /  [t] テスト音  /  [+/-] 音量  /  [Space] 停止");
}

// 役割の確定/リセットをウィンドウタイトルにも反映
void updateRoleTitle(){
  String role = (nodeRole == ROLE_MAIN_UI) ? "メイン操作UI"
              : (nodeRole == ROLE_ANALYZER) ? "アナライザ" : "ポート選択";
  surface.setTitle("タクトーン production — " + role);
}

// ── パケット処理 (draw スレッド) ───────────────────────────
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
    uiPartId    = ui.partId;
    uiBpmQ8     = ui.bpmQ8;
    lastUiAtMs  = millis();
    if (nodeRole != ROLE_MAIN_UI){
      nodeRole = ROLE_MAIN_UI;
      updateRoleTitle();
      orcLogSystem("役割自動判定: メイン操作 UI (UIフレーム受信)");
    }
    masterResetDetected = false;
    orcLogUi(uiState, uiMode, uiTargetBpm, uiScore, uiBpmQ8);
    return;
  }

  if (type != TYPE_NOTE) return;

  NoteEvent n = new NoteEvent(buf);

  if (nodeRole == ROLE_UNKNOWN){
    if (n.partId == 0x02){
      nodeRole = ROLE_MAIN_UI;
      orcLogSystem("役割自動判定: メイン操作 UI (partId=0x02)");
    } else {
      nodeRole = ROLE_ANALYZER;
      orcLogSystem("役割自動判定: アナライザ (partId=0x" + hex(n.partId, 2) + ")");
    }
    updateRoleTitle();
  }

  if (n.gate == 1){
    orcLogNote(n.partId, n.noteNumber, n.velocity, n.durationMs, n.instrumentId);
    triggerNote(n.partId, n.instrumentId, n.noteNumber, n.velocity, n.durationMs);
    lastEventByPart[n.partId] = noteName(n.noteNumber) + " v=" + n.velocity + " dur=" + n.durationMs + "ms";
    lastNoteMsByPart[n.partId] = millis();
    lastNoteAtMs = millis();
  } else {
    if (isDrumInstrument(n.instrumentId)) return;
    int releaseMidi = n.noteNumber + brassOctaveShift(n.instrumentId);
    releaseMatching(n.partId, releaseMidi);
  }
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
  if (toScr == SCR_MENU){
    gameStartMs = 0;
    lastMetroBeat = -1;
    uiScore = 0xFF;
    for (MetroClick mc : metroClicks) mc.unpatch(out);
    metroClicks.clear();
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

  // マスター ESP32 リセット検知
  if (lastUiAtMs > 0 && !openByName.isEmpty() && nodeRole == ROLE_MAIN_UI){
    if (millis() - lastUiAtMs > UI_TIMEOUT_MS){
      uiState = ST_IDLE;
      uiScore = 0xFF;
      gameStartMs = 0;
      lastMetroBeat = -1;
      stopAll();
      masterResetDetected = true;
      lastUiAtMs = 0;
      orcLogError("CTRL", "マスターリセット検知: UIパケットタイムアウト (" + UI_TIMEOUT_MS + "ms)");
    }
  }

  updateVoiceLifecycle();
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

// ── ポート選択画面 ────────────────────────────────────────
void drawPortSelectScreen(){
  drawBackground();
  drawPageTitle("タクトーン — production",
      "楽器定義 " + models.size() + " 個  /  [click]ポート開閉  [r]再列挙  [f]フィルタ  [t]テスト音");
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

  drawHelpPanel("[r]ポート再選択  [t]テスト音  [+/-]音量");
}

// ── 自由演奏画面 ──────────────────────────────────────────
void drawFreePlayScreen(){
  drawBackground();
  float bpm = uiBpmQ8 / 8.0f;
  drawPageTitle("自由演奏",
      "BPM: " + nf(bpm, 1, 1) + "  /  発音中 " + activeVoices.size() + " / " + MAX_POLYPHONY +
      "  /  音量 " + nf(masterVolume, 1, 2));

  drawScope(28, 96, width - 56, 100);

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

  drawPanel(28, 316, width - 56, 130);
  fill(18, 54, 88); textSize(60); textAlign(CENTER, CENTER);
  text(nf(bpm, 1, 1), width/2, 365);
  fill(61, 86, 111); textSize(16);
  text("BPM", width/2, 410);
  textAlign(LEFT, BASELINE);

  drawHelpPanel("[r]リセット  [t]テスト音  [+/-]音量  [Space]停止");
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

  float barX = 28, barY = 96, barW = width - 56, barH = 32;
  drawPanel(barX, barY, barW, barH);
  fill(64, 159, 255, (int)(guide * 200 + 55));
  noStroke();
  rect(barX + 6, barY + 6, (barW - 12) * guide, barH - 12, 10);
  fill(18, 54, 88); textSize(12); textAlign(LEFT, BASELINE);
  text("ガイド: " + nf(guide * 100, 1, 0) + "%", barX + 14, barY + 22);

  drawScope(28, 138, width - 56, 80);

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

  drawPanel(28, 298, width - 56, 130);
  fill(18, 54, 88); textSize(50); textAlign(CENTER, CENTER);
  text(scoreStr, width/2, 348);
  fill(61, 86, 111); textSize(16);
  text(uiScore == 0xFF ? "スコア (" + GAME_LENGTH_BEATS + " 拍振り切ると結果画面へ)" : "スコア", width/2, 398);
  textAlign(LEFT, BASELINE);

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

  drawHelpPanel("[t]テスト音  [+/-]音量  [Space]停止");
}

// ── ヘルプパネル (画面下部) ───────────────────────────────
void drawHelpPanel(String helpText){
  float hx = 28, hy = height - 66, hw = width - 56, hh = 48;
  fill(255); noStroke();
  rect(hx, hy, hw, hh, 16);
  stroke(134, 184, 218); strokeWeight(2); noFill();
  rect(hx, hy, hw, hh, 16);
  strokeWeight(1); noStroke();
  fill(28, 54, 80); textSize(13); textAlign(LEFT, BASELINE);
  text(helpText, hx + 22, hy + 28);

  float sx = hx + hw - 22;
  int now = millis();

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
    nodeRole = ROLE_UNKNOWN;
    uiState = ST_IDLE;
    uiScore = 0xFF;
    updateRoleTitle();
    orcLogSystem("ポートリセット");
    return;
  }
  if (c=='i'){ rescanInstruments(); return; }
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
    orcLogSystem("ポートフィルタ: " + (usbOnly ? "USB のみ" : "全ポート"));
    return;
  }
}

void dispose(){
  closeAllPorts();
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}
