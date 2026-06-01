/* ==========================================================================
   orchestra_resynth — test_v2 の PC 側プログラム (Processing)

   firmware/test_v2 の楽器ノード (Arduino UNO R4 WiFi) から USB Serial で送られて
   くる NOTE パケット (楽器番号 / 高さ / 長さ / 声部 / velocity) を受け、
   sound_lab で解析した音色定義 (data/*.json) を使ってポリフォニックに加算合成する。

   ・楽器番号 (instrumentId) で data/ 内の何番目の楽器定義を使うか決まる
     (ファイル名昇順で 0,1,2,3…)。輪唱の声部 2/3/4 はそれぞれ楽器番号 0/1/2 を送る
     (firmware 側 ProjectConfig.h で固定。data/ には予備を入れて 4 種類置いてある)。
   ・複数音を重ねて鳴らせる (輪唱の 3 声部 = 3 音同時)。消音は NOTE の durationMs から自動。
   ・PC アプリは 1 個でよい。本番は 1 Mac : 1 ノード (1 声部) の想定だが、
     テスト用に「1 Mac に複数ノードを USB 接続 → このアプリで複数シリアルポートを同時に開く」
     ことができる (画面のポート一覧をクリックで開閉)。
   ・楽曲は指揮者ノードの拍番号で進むので、Processing をいつ起動しても「曲の現在位置」から
     鳴り始める (= 途中参加 OK)。

   合成方式 (instrument_player.pde と同じ): 倍音ごとに振幅・周波数比・時間エンベロープを
   持つ加算合成 + 非調和性 (f_n = n·f0·√(1+B·n²)) + スペクトル整形ノイズ + 全体振幅エンベロープ
   + ビブラート / トレモロ。

   必要ライブラリ: Minim (スケッチ → ライブラリをインポート → ライブラリを追加 → "Minim")

   操作:
     - 画面下の「シリアルポート」一覧をクリック → そのポートを開く / もう一度クリックで閉じる
       (複数ポートを同時に開ける)
     - 'r' : シリアルポート一覧を再列挙   /   'i' : data/ の楽器定義を再スキャン
     - 't' : テスト音 (C・E・G を楽器 0/1/2 で同時に鳴らす — Arduino なしで音出し確認)
     - '0'〜'3' : その番号の楽器で C4 を 1 発鳴らす (楽器の聴き比べ)
     - 'a' : 振幅包絡の方式切替 (実エンベロープ ↔ ADSR 4 値)
     - '+' / '-' : マスター音量   /   Space : 全音停止

   パケット仕様 (受信, 20 バイト固定, リトルエンディアン):
     0  magic       uint16  0x4F52 ("OR")
     2  version     uint8   0x01
     3  type        uint8   3=NOTE (1=CTRL / 2=BEAT は USB には流れないが来ても無視)
     4  seq         uint32
     8  timestampMs uint32
     12 partId      uint8   test_v2 は 0x02-0x04 / production 想定は 0x02-0x06 (ADR-0004 改訂版で楽器 5 台 = 金管 4 + ドラム 1)
     13 noteNumber  uint8   MIDI ノート番号 (60=C4, 高さ)
     14 velocity    uint8   0-127
     15 gate        uint8   1=NoteOn (0=NoteOff は来ないが来たら一致音を release)
     16 durationMs  uint16  発音予定長 (長さ)
     18 instrumentId uint8  0..N-1 (楽器番号 — data/*.json をファイル名昇順ソートしたときの index)
     19 reserved    uint8   0

   フォーマット仕様: ../../../sound_lab/library_format.md
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
final byte MAGIC_LO      = (byte) 0x52;   // 'R'
final byte MAGIC_HI      = (byte) 0x4F;   // 'O'
final int  TYPE_CTRL     = 1;
final int  TYPE_BEAT     = 2;
final int  TYPE_NOTE     = 3;
final int  MAX_POLYPHONY = 24;            // 同時発音数の上限 (超えたら最古を強制 release)

float   masterVolume  = 0.55f;            // 全声部合算のスケール (clip を抑える)
boolean useSimpleADSR = false;

// ── オーディオ ────────────────────────────────────────────
Minim       minim;
AudioOutput out;

// ── 楽器定義 (data/*.json) ────────────────────────────────
ArrayList<File>        instrumentFiles = new ArrayList<File>();
ArrayList<InstrModel>  models          = new ArrayList<InstrModel>();
ArrayList<String>      modelLabels     = new ArrayList<String>();
// [一時] 輪唱の聞き分けを優しくするため、全パートを同じ音色 (piano.json) で鳴らすモード。
// 'p' キーで切替。false なら従来通り NOTE.instrumentId で楽器を引く。
boolean      forceSingleInstrument    = true;
final String FORCED_INSTRUMENT_FILE   = "piano.json";
int          forcedInstrumentIdx      = -1;   // rescanInstruments() が更新

// ── シリアルポート ────────────────────────────────────────
// 各ポートはフレーム同期状態を個別に持つ。serialEvent(Serial) でどのポートか引く。
class PortConn {
  String  name;
  Serial  port;
  byte[]  rxBuf = new byte[PACKET_SIZE];
  int     rxIdx = 0;
  boolean inFrame = false;
  int     rxCount = 0;
  PortConn(String n) { name = n; }
}
String[]                  availablePorts = new String[0];  // Serial.list() の生 (全 OS ポート)
String[]                  displayPorts   = new String[0];  // 一覧 UI に出すフィルタ済リスト
boolean                   usbOnly        = true;            // true なら usbmodem/usbserial 系のみ表示 ('f' で切替)
float                     portScrollY    = 0;               // ポート一覧の縦スクロール量 (px)
HashMap<String,PortConn>  openByName     = new HashMap<String,PortConn>();
HashMap<Serial,PortConn>  bySerial       = new HashMap<Serial,PortConn>();
// serialEvent (Serial スレッド) は 20 B 揃ったパケットをここに積むだけ。
// 発音処理 (Voice 操作) は draw() スレッドで drainPackets() がまとめて行う。
ConcurrentLinkedQueue<byte[]> packetQueue = new ConcurrentLinkedQueue<byte[]>();

// ── 発音中ボイス (最古が先頭) ─────────────────────────────
ArrayList<ResynthVoice> activeVoices = new ArrayList<ResynthVoice>();

// ── 表示用 ────────────────────────────────────────────────
int      totalReceived = 0;
String[] lastEventByPart = new String[256];   // partId -> 直近イベントのラベル
int      lastNoteAtMs   = 0;
PFont    uiFont;

final String[] NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
String noteName(int midi){ return NOTE_NAMES[((midi%12)+12)%12] + (midi/12 - 1); }

// ────────────────────────────────────────────────────────────
void settings(){ size(900, 560); }

void setup(){
  frameRate(90);   // draw()/drainPackets() を ~11ms 周期に (既定60fps=16.7ms より受信処理の粒度を短縮)
  surface.setTitle("orchestra_resynth — test_v2 (輪唱 / きらきら星)");
  uiFont = loadJapaneseFont(13);
  if (uiFont != null) textFont(uiFont);
  else textFont(createFont("SansSerif", 13));

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 512, 44100);   // バッファ 512 = 約11.6ms (1024 の半分・低遅延化)

  rescanInstruments();
  refreshPorts();

  println("=== orchestra_resynth (test_v2) ===");
  println("data/ から楽器定義 " + models.size() + " 個をロードしました。");
  println("[click] ポート開閉  /  [wheel] スクロール  /  [r] ポート再列挙  /  [f] USB-onlyフィルタ切替  /  [i] 楽器再スキャン  /  [p] 全パート同じ音色 ON/OFF  /  [t] テスト音  /  [0-3] 楽器ごとの試聴  /  [Space] 停止");
}

// OS の日本語対応フォントを優先順位付きで探す (orchestra_player.pde と同じ手法)
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
  println("(!) 日本語対応フォントが見つかりませんでした。文字が化ける可能性があります。");
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
      modelLabels.add(f.getName() + "  —  " + root.getString("name","instrument") +
                      " (" + m.noteName + " / " + nf(m.fundamentalHz,0,1) + " Hz / " +
                      m.harmonicCount + " 倍音, " + (m.sustaining ? "持続音" : "減衰音") + ")");
      println("loaded[" + (models.size()-1) + "] " + f.getName());
    } catch (Exception e){
      models.add(null);
      modelLabels.add(f.getName() + "   [読込失敗] " + e);
      println("[エラー] " + f.getName() + " を読めませんでした: " + e);
    }
  }
  if (models.isEmpty())
    println("[警告] data/ に *.json がありません。sound_lab で作った楽器定義を data/ に置いて 'i' を押してください。");

  // [一時] 全パートを同じ音色に固定するモード用。data/piano.json の index を覚える。
  forcedInstrumentIdx = -1;
  for (int i = 0; i < instrumentFiles.size(); i++){
    if (instrumentFiles.get(i).getName().equalsIgnoreCase(FORCED_INSTRUMENT_FILE) && models.get(i) != null){
      forcedInstrumentIdx = i;
      break;
    }
  }
  println("single-instrument モード: " + (forceSingleInstrument ? "ON" : "OFF")
        + " / 固定先=" + FORCED_INSTRUMENT_FILE
        + " (" + (forcedInstrumentIdx >= 0 ? "idx=" + forcedInstrumentIdx : "未検出") + ")");
}

// 楽器番号 → 使えるモデル (範囲外は末尾にクランプ。1 個も無ければ null)
// forceSingleInstrument=true なら instrumentId を無視して FORCED_INSTRUMENT_FILE を引く。
InstrModel modelForId(int id){
  if (models.isEmpty()) return null;
  int idx;
  if (forceSingleInstrument && forcedInstrumentIdx >= 0) idx = forcedInstrumentIdx;
  else                                                   idx = constrain(id, 0, models.size()-1);
  InstrModel m = models.get(idx);
  if (m != null) return m;
  for (InstrModel mm : models) if (mm != null) return mm;   // フォールバック
  return null;
}

// ── シリアルポート 列挙 / 開閉 ─────────────────────────────
void refreshPorts(){
  availablePorts = Serial.list();
  rebuildDisplayPorts();
  println("");
  println("Available serial ports (usbOnly=" + usbOnly + "):");
  if (availablePorts.length == 0) println("  (none) — デバイスを挿してから 'r' で再列挙");
  for (int i=0;i<availablePorts.length;i++){
    boolean shown = isUsbSerialName(availablePorts[i]);
    println("  [" + i + "] " + availablePorts[i]
        + (openByName.containsKey(availablePorts[i]) ? "  <OPEN>" : "")
        + (usbOnly && !shown ? "  (hidden by USB-only filter)" : ""));
  }
}

// USB シリアル系の名前判定。macOS の usbmodem*/usbserial*、Linux の ttyUSB*/ttyACM*、
// Windows の COM* もマッチさせる (Windows は将来移植時の保険)。
boolean isUsbSerialName(String name){
  if (name == null) return false;
  String n = name.toLowerCase();
  return n.contains("usbmodem") || n.contains("usbserial")
      || n.contains("ttyusb")   || n.contains("ttyacm")
      || n.startsWith("com")    || n.contains("/com");
}

// availablePorts (生リスト) から displayPorts (UI 表示用) を作る。
// usbOnly が true のときは USB シリアル系だけに絞る。
// 既に開いているポートはフィルター対象でも常に残す (close 操作を奪わないため)。
void rebuildDisplayPorts(){
  if (!usbOnly){
    displayPorts = availablePorts;
  } else {
    ArrayList<String> kept = new ArrayList<String>();
    for (String n : availablePorts){
      if (isUsbSerialName(n) || openByName.containsKey(n)) kept.add(n);
    }
    displayPorts = kept.toArray(new String[0]);
  }
  // スクロール量を新リスト長に合わせてクランプ (後段で h を知らないので 0 に寄せるだけ)
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
    try { pc.port.stop(); } catch (Exception e){ /* 無視 */ }
  }
  println("Closed: " + name);
}
void closeAllPorts(){
  for (String n : new ArrayList<String>(openByName.keySet())) closePort(n);
}

// ── シリアル受信 (Serial スレッド) ─────────────────────────
// Voice には触らず、20 B 揃ったら packetQueue に積むだけ。
void serialEvent(Serial p){
  PortConn pc = bySerial.get(p);
  if (pc == null){ while (p.available() > 0) p.read(); return; }
  while (p.available() > 0){
    int b = p.read();
    if (!pc.inFrame){
      if (pc.rxIdx == 0){
        if ((byte)b == MAGIC_LO){ pc.rxBuf[0] = (byte)b; pc.rxIdx = 1; }
      } else { // rxIdx == 1
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
  if (u8(buf[2]) != 0x01) return;          // version
  int type = u8(buf[3]);
  if (type != TYPE_NOTE) return;            // CTRL/BEAT は USB には来ない想定 — 無視
  int partId       = u8(buf[12]);
  int noteNumber   = u8(buf[13]);
  int velocity     = u8(buf[14]);
  int gate         = u8(buf[15]);
  int durationMs   = u16le(buf[16], buf[17]);
  int instrumentId = u8(buf[18]);
  if (gate == 1){
    triggerNote(partId, instrumentId, noteNumber, velocity, durationMs);
    lastEventByPart[partId] = "instr=" + instrumentId + " " + noteName(noteNumber) +
                              " v=" + velocity + " dur=" + durationMs + "ms";
    lastNoteAtMs = millis();
  } else {
    releaseMatching(partId, noteNumber);
    lastEventByPart[partId] = "NoteOff " + noteName(noteNumber);
  }
}

// ── 発音管理 ──────────────────────────────────────────────
void triggerNote(int partId, int instrumentId, int midi, int velocity, int durationMs){
  InstrModel m = modelForId(instrumentId);
  if (m == null) return;
  // 同時発音上限を超えていたら最古の active を強制 release してリソースを確保
  int guard = 0;
  while (countNonReleasing() >= MAX_POLYPHONY && guard++ < MAX_POLYPHONY){
    for (ResynthVoice v : activeVoices){ if (!v.releasing){ v.noteOff(); break; } }
  }
  float g = constrain(velocity / 127.0f, 0.0f, 1.0f) * masterVolume;
  ResynthVoice v = new ResynthVoice(m, midi, g, useSimpleADSR);
  v.partId        = partId;
  v.instrumentIdx = constrain(instrumentId, 0, max(0, models.size()-1));
  v.scheduledOffMs = millis() + max(40, durationMs);   // durationMs 後に自動で noteOff
  v.patch(out);
  activeVoices.add(v);
}
int countNonReleasing(){
  int n = 0; for (ResynthVoice v : activeVoices) if (!v.releasing) n++; return n;
}
// gate=0 互換: partId + noteNumber が一致する発音中ボイスを全部 release
void releaseMatching(int partId, int midi){
  for (ResynthVoice v : activeVoices)
    if (!v.releasing && v.partId == partId && v.midiNote == midi) v.noteOff();
}
void stopAll(){
  for (ResynthVoice v : activeVoices) v.unpatch(out);
  activeVoices.clear();
}

// テスト音 (Arduino なしで音を確認する用)
void playTestChord(){
  int[] chord = {60, 64, 67};   // C4 E4 G4
  for (int i=0;i<chord.length;i++) triggerNote(0x02+i, i, chord[i], 100, 900);
}
void playTestNoteOnInstrument(int idx){
  triggerNote(0x02, idx, 60, 100, 1000);
}

// ── 描画ループ ────────────────────────────────────────────
void draw(){
  drainPackets();

  // durationMs 到達したボイスを release に移し、release 完了したものを unpatch
  int now = millis();
  for (ResynthVoice v : activeVoices) if (!v.releasing && now >= v.scheduledOffMs) v.noteOff();
  for (Iterator<ResynthVoice> it = activeVoices.iterator(); it.hasNext();){
    ResynthVoice v = it.next();
    if (v.done){ v.unpatch(out); it.remove(); }
  }

  drawBackground();
  drawHeader();
  drawScope();
  drawStatus();
  drawInstrumentList();
  drawPortList();
}

// ── UI パーツ ─────────────────────────────────────────────
void drawBackground(){
  for (int y=0;y<height;y++){
    float t = y/(float)height;
    int c = lerpColor(color(224,231,255), lerpColor(color(252,231,243), color(219,234,254), t), t);
    stroke(c); line(0,y,width,y);
  }
  noStroke();
}
void glassPanel(float x, float y, float w, float h){
  noStroke(); fill(255,255,255,150); rect(x,y,w,h,16);
  stroke(255,255,255,200); noFill(); rect(x,y,w,h,16); noStroke();
}
boolean mouseOver(float x, float y, float w, float h){ return mouseX>=x && mouseX<=x+w && mouseY>=y && mouseY<=y+h; }

void drawHeader(){
  glassPanel(16, 14, width-32, 56);
  fill(30,27,75); textSize(17); textAlign(LEFT);
  text("orchestra_resynth — test_v2  (輪唱 / きらきら星)", 30, 38);
  textSize(11); fill(99,102,241);
  text("楽器定義 " + models.size() + " 個ロード  /  開いているポート " + openByName.size() + " 個  /  発音中 " +
       activeVoices.size() + " / " + MAX_POLYPHONY + "  /  マスター音量 " + nf(masterVolume,1,2), 30, 56);
  textAlign(RIGHT); fill(120,120,160);
  text("[click]ポート開閉  [wheel]スクロール  [r]再列挙  [f]USBフィルタ  [i]楽器再スキャン  [t]テスト音  [0-3]試聴  [a]包絡  [+/-]音量  [Space]停止", width-30, 56);
  textAlign(LEFT);
}

// out.left の波形スコープ
void drawScope(){
  float x=16, y=78, w=width-32, h=84;
  glassPanel(x,y,w,h);
  fill(99,102,241); textSize(10); text("出力波形", x+12, y+16);
  stroke(129,140,248); noFill();
  float cy = y + h*0.5f;
  beginShape();
  for (int i=0;i<out.bufferSize();i++) vertex(x + 8 + (w-16)*i/(float)(out.bufferSize()-1), cy - out.left.get(i)*(h*0.40f));
  endShape();
  noStroke();
}

void drawStatus(){
  float x=16, y=170, w=width-32, h=88;
  glassPanel(x,y,w,h);
  fill(30,27,75); textSize(11); textAlign(LEFT);
  text("受信状況", x+12, y+18);
  fill(60,57,110); textSize(11);
  text("受信パケット合計: " + totalReceived +
       (lastNoteAtMs>0 ? "   (最後の NOTE から " + (millis()-lastNoteAtMs) + " ms)" : ""), x+12, y+38);
  // 声部ごとの直近イベント (partId 0x02..0x05)
  float ry = y+56; int col=0;
  for (int p=0x02; p<=0x05; p++){
    String ev = lastEventByPart[p];
    fill(ev!=null ? color(40,37,90) : color(150,150,180));
    text("声部 0x" + hex(p,2) + ": " + (ev!=null ? ev : "(まだ受信なし)"), x+12 + col*((w-24)/2), ry);
    col++; if (col>=2){ col=0; ry += 16; }
  }
  textAlign(LEFT);
}

// data/ 内の楽器定義一覧 (どの番号がどの楽器か)
void drawInstrumentList(){
  float x=16, y=266, w=width-32, h=110;
  glassPanel(x,y,w,h);
  fill(30,27,75); textSize(11); textAlign(LEFT);
  String forcedTag = forceSingleInstrument
      ? "  [p:ON 全パート→" + FORCED_INSTRUMENT_FILE + (forcedInstrumentIdx>=0 ? " (idx=" + forcedInstrumentIdx + ")" : " (未検出)") + "]"
      : "  [p:OFF instrumentId に従う]";
  text("楽器定義 (data/*.json) — 番号 = 楽器番号 (Arduino が送る instrumentId)" + forcedTag, x+12, y+18);
  if (models.isEmpty()){
    fill(150,150,180);
    text("data/ に *.json がありません。sound_lab で作った楽器定義を置いて 'i' を押してください。", x+12, y+40);
    textAlign(LEFT); return;
  }
  float rowY0 = y+28, rowH=18;
  for (int i=0;i<modelLabels.size();i++){
    float ry = rowY0 + i*rowH;
    if (ry > y+h-6) break;
    fill(i<models.size() && models.get(i)!=null ? color(40,37,90) : color(231,68,68));
    textSize(11);
    text(nf(i,1) + ".  " + modelLabels.get(i), x+22, ry+13);
  }
  textAlign(LEFT);
}

// シリアルポート一覧 (クリックで開閉)
// 縦方向にスクロール可能 (mouseWheel) で、表示は usbOnly フィルタ済の displayPorts を使う。
// クリック判定もスクロール量を反映するため、座標計算は drawPortList と mousePressed で共有する。
float portRowX, portRowW, portRowY0, portRowH;       // リストの 1 行ぶんの座標 (スクロール無視)
float portViewY, portViewH;                          // リスト描画領域の Y / 高さ (スクロールクリップ範囲)
int   portRowCount;                                  // displayPorts.length のキャッシュ
void drawPortList(){
  // ポート開閉直後 / フィルタ切替時の追従のため毎フレーム再構築 (availablePorts は 'r' でのみ更新)
  rebuildDisplayPorts();
  float x=16, y=384, w=width-32, h=height-y-12;
  glassPanel(x,y,w,h);
  fill(30,27,75); textSize(11); textAlign(LEFT);
  String filterTag = usbOnly ? "USB のみ" : "全ポート";
  text("シリアルポート [" + filterTag + " / 表示 " + displayPorts.length + " / 全 " + availablePorts.length + "] "
       + "— クリックで開閉 / ホイールでスクロール / [f] フィルタ切替 / [r] 再列挙",
       x+12, y+18);

  portRowX = x+12; portRowW = w-24; portRowY0 = y+28; portRowH = 24;
  portViewY = portRowY0; portViewH = (y + h) - portRowY0 - 4;
  portRowCount = displayPorts.length;

  if (availablePorts.length == 0){
    fill(220,160,60); textSize(11);
    text("シリアルポートが見つかりません。Arduino を USB 接続して 'r' で再列挙してください。", x+12, y+40);
    textAlign(LEFT); return;
  }
  if (displayPorts.length == 0){
    fill(220,160,60); textSize(11);
    text("USB-only フィルタで全部隠れています。'f' で全表示に切り替えるか USB デバイスを挿してください。", x+12, y+40);
    textAlign(LEFT); return;
  }

  // スクロール範囲をクランプ (totalH > viewH のときだけスクロール余地がある)
  float totalH = portRowCount * portRowH;
  float maxScroll = max(0, totalH - portViewH);
  portScrollY = constrain(portScrollY, 0, maxScroll);

  // リスト領域をクリッピング (スクロール時に枠外へはみ出さない)
  clip(portRowX - 2, portViewY - 2, portRowW + 4, portViewH + 4);
  for (int i=0;i<displayPorts.length;i++){
    float ry = portRowY0 + i*portRowH - portScrollY;
    if (ry + portRowH < portViewY) continue;           // 上に消えた行はスキップ
    if (ry > portViewY + portViewH)  break;            // 下にはみ出たら以降不要
    boolean isOpen = openByName.containsKey(displayPorts[i]);
    boolean isHover = mouseOver(portRowX, ry, portRowW, portRowH-2)
                   && mouseOver(portRowX, portViewY, portRowW, portViewH); // 領域外ホバーは無視
    noStroke();
    if (isOpen) fill(isHover ? color(80,180,120) : color(96,200,140));
    else        fill(isHover ? color(255,255,255,235) : color(255,255,255,140));
    rect(portRowX, ry, portRowW, portRowH-2, 7);
    fill(isOpen ? 255 : color(60,57,110)); textSize(11);
    String tag = isOpen ? ("● OPEN  受信 " + openByName.get(displayPorts[i]).rxCount + " 個") : "○ closed (クリックで開く)";
    text("[" + i + "] " + displayPorts[i] + "    " + tag, portRowX+10, ry+16);
  }
  noClip();

  // スクロールバー (右端の細い縦バー)。スクロール余地があるときだけ描画。
  if (maxScroll > 0){
    float barX = portRowX + portRowW - 4;
    float barW = 4;
    float barTrackH = portViewH;
    noStroke(); fill(0, 0, 0, 30);
    rect(barX, portViewY, barW, barTrackH, 2);
    float thumbH = max(20, barTrackH * (portViewH / totalH));
    float thumbY = portViewY + (barTrackH - thumbH) * (portScrollY / maxScroll);
    fill(99,102,241, 180);
    rect(barX, thumbY, barW, thumbH, 2);
  }
  textAlign(LEFT);
}

// ── マウス / キーボード ───────────────────────────────────
void mousePressed(){
  if (portRowCount <= 0) return;
  if (!mouseOver(portRowX, portViewY, portRowW, portViewH)) return;  // リスト領域外は無視
  for (int i=0;i<portRowCount;i++){
    float ry = portRowY0 + i*portRowH - portScrollY;
    if (ry + portRowH < portViewY) continue;
    if (ry > portViewY + portViewH)  break;
    if (mouseOver(portRowX, ry, portRowW, portRowH-2)){ togglePort(displayPorts[i]); return; }
  }
}

// マウスホイールで一覧をスクロール。リスト領域内のホイールだけ拾う。
void mouseWheel(processing.event.MouseEvent e){
  if (portRowCount <= 0) return;
  if (!mouseOver(portRowX, portViewY, portRowW, portViewH)) return;
  portScrollY += e.getCount() * portRowH;  // 1 ノッチ = 1 行
  // 範囲クランプは drawPortList 側でも行うが、即時にもクランプして UI 反応を素直にする
  float totalH = portRowCount * portRowH;
  float maxScroll = max(0, totalH - portViewH);
  portScrollY = constrain(portScrollY, 0, maxScroll);
}

void keyPressed(){
  char c = Character.toLowerCase(key);
  if (c=='r'){ refreshPorts(); return; }
  if (c=='i'){ rescanInstruments(); return; }
  if (c=='p'){
    forceSingleInstrument = !forceSingleInstrument;
    println("single-instrument モード: " + (forceSingleInstrument ? "ON (全パート " + FORCED_INSTRUMENT_FILE + ")" : "OFF (instrumentId に従う)"));
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
    println("ポートフィルタ: " + (usbOnly ? "USB のみ" : "全ポート") + " (表示 " + displayPorts.length + " / 全 " + availablePorts.length + ")");
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
   InstrModel — sound_lab の JSON を解釈して合成に必要な配列を保持。
   (instrument_player.pde の同名クラスを移植。スペクトル整形ノイズのループバッファは
    ここで一度だけ作り、その楽器の全ボイスで共有する。)
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
   (instrument_player.pde の同名クラスを移植 + 自動オフ時刻 scheduledOffMs を追加。)
   生成時は「鳴っている」状態で、scheduledOffMs に達したら draw() が noteOff() を呼ぶ。
   ========================================================================== */
class ResynthVoice extends UGen {
  InstrModel m;
  int   midiNote;
  float targetF0;
  float gain;
  boolean simpleADSR;

  // test_v2 で追加: どの声部 / 楽器番号か、いつ自動 noteOff するか
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
    if (m.vibDepthCents > 0.01f && m.vibRateHz > 0.001f){
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
      s += amp * harmEnvAt(k, tSec) * sin(phase[k]);
    }
    s *= m.harmNorm;
    if (m.noiseLevel > 0 && m.noiseTable.length > 1){
      float relMul = releasing ? max(0, 1-(tSec-releaseStartT)/relSec()) : 1;
      float ne = noiseEnvAt(tSec) * m.noiseLevel * relMul;
      s += m.noiseTable[(int)noisePos] * ne;
      noisePos += 1; if (noisePos >= m.noiseTable.length) noisePos -= m.noiseTable.length;
    }
    if (m.tremDepth > 0.001f && m.tremRateHz > 0.001f){
      s *= 1.0f - m.tremDepth*0.5f + m.tremDepth*0.5f*sin(tremPhase);
      tremPhase += TWO_PI * m.tremRateHz / sr; if (tremPhase >= TWO_PI) tremPhase -= TWO_PI;
    }
    s *= a * gain * 0.9f;
    for (int i=0;i<channels.length;i++) channels[i] = s;
    tSec += 1.0f/sr;
    if (releasing && (tSec - releaseStartT) >= relSec()) done = true;
    else if (!done && a <= 1e-4f && tSec > 0.15f) done = true;   // 減衰音が自然に死んだ
  }
}
