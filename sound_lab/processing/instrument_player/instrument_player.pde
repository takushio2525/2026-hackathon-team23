/* ==========================================================================
   instrument_player — sound_lab で解析した音色定義(JSON)を読み込み、
   音程を与えると「限りなく元に近い音」を鳴らす Processing スケッチ。

   発音モデル: キー(または鍵盤クリック)を押している間ずっと鳴り続け、離すとリリース。
               持続音は押している間サステイン区間をループ、減衰音は自然に鳴り切る。

   合成方式: 倍音ごとに振幅・周波数比・時間エンベロープを持つ加算合成
             + 非調和性(f_n = n·f0·√(1+B·n²)) + スペクトル整形ノイズ + 全体振幅エンベロープ。

   必要ライブラリ: Minim (スケッチ → ライブラリをインポート → ライブラリを追加 → "Minim")

   音色の差し替え:
     data/ フォルダに置いた *.json をすべて自動で見つけ、起動後に画面の一覧をクリック
     (または '[' / ']' キー)で切り替えられる。'r' で data/ を再スキャン＋現在の音色を再読込。
     'o' で data/ 以外の場所にある JSON も選べる。
     何も置いていない場合は同梱の example_organ.json で起動する。

   操作:
     - 鍵盤をクリック / PC キーボード(zsxdcvg… と q2w3e… の 2 列)を「押している間」鳴る。離すとリリース
     - 上下矢印: オクターブ移動(押している鍵はいったん離される)
     - 'p' または画面のボタン: きらきら星(ドドソソララソ)を再生
     - '[' / ']': 音色を前 / 次へ切替   /   'o': data/ 外の JSON を選択   /   'r': data/ 再スキャン＋再読込
     - 'a': 振幅包絡の方式切替(実エンベロープ ↔ ADSR 4 値)   /   Space: 全音停止

   フォーマット仕様: sound_lab/library_format.md
   ========================================================================== */

import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*;
import java.util.Iterator;
import java.io.File;

Minim minim;
AudioOutput out;

InstrModel model;                 // 読み込んだ音色定義
String loadedName = "(未読込)";

ArrayList<ResynthVoice> voices = new ArrayList<ResynthVoice>();          // 鳴っている全ボイス
HashMap<Integer,ResynthVoice> heldByNote = new HashMap<Integer,ResynthVoice>();  // 押されている音(MIDI→voice)
int mousePressedNote = -1;        // マウスで押している鍵盤(離したとき用)
boolean useSimpleADSR = false;    // true なら値配列でなく A/D/S/R 4 値だけで包絡を作る

// data/ 配下の *.json 一覧と、いま選んでいるインデックス
ArrayList<File> instrumentFiles = new ArrayList<File>();
int currentIdx = -1;
int listScroll = 0;               // 一覧が長いときの表示開始行

int   baseOctaveMidi = 48;        // 鍵盤左端の MIDI ノート(C3)
int   keyboardOctaves = 3;        // 表示するオクターブ数

// ── きらきら星シーケンサ ──────────────────────────────────
final int[] SONG_NOTES = {60, 60, 67, 67, 69, 69, 67};   // ド ド ソ ソ ラ ラ ソ (C4 C4 G4 G4 A4 A4 G4)
final int[] SONG_BEATS = {1, 1, 1, 1, 1, 1, 2};          // 最後のソは 2 拍
int     songBeatMs = 480;          // 1 拍の長さ(ms)
boolean songPlaying = false;
int     songIdx = 0;
int     songNoteOnMs = 0;          // 次のノートを鳴らす時刻(millis)
int     songNoteOffMs = Integer.MAX_VALUE;   // 今のノートを離す時刻
ResynthVoice songVoice = null;
int     songCurrentNote = -1;      // 鍵盤ハイライト用

// PC キーボード → MIDI ノート(0 = baseOctaveMidi 起点のオフセット)
final HashMap<Character,Integer> KEYMAP = new HashMap<Character,Integer>();
void initKeymap(){
  String low = "zsxdcvgbhnjm";   // 下段 = baseOctave..+11
  String hi  = "q2w3er5t6y7ui";  // 上段 = baseOctave+12..
  for (int i=0;i<low.length();i++) KEYMAP.put(low.charAt(i), i);
  for (int i=0;i<hi.length();i++)  KEYMAP.put(hi.charAt(i),  12+i);
}

void settings(){ size(960, 620); }

void setup(){
  surface.setTitle("instrument_player — sound_lab");
  textFont(createFont("SansSerif", 13));
  initKeymap();
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024, 44100);
  rescanAndLoad(true);
}

// data/ を再スキャンして、可能なら今と同じファイルを(無ければ既定を)読み直す
void rescanAndLoad(boolean preferDefault){
  String keep = (currentIdx>=0 && currentIdx<instrumentFiles.size()) ? instrumentFiles.get(currentIdx).getName() : null;
  scanInstruments();
  if (instrumentFiles.isEmpty()){
    model = null; loadedName = "(data/ に .json がありません)";
    println("[警告] data/ に *.json がありません。解析ツールで作った JSON をここに置くか、'o' で選んでください。");
    currentIdx = -1; return;
  }
  int target = -1;
  if (!preferDefault && keep != null) target = indexOfName(keep);
  if (target < 0) target = indexOfName("instrument.json");
  if (target < 0) target = indexOfName("example_organ.json");
  if (target < 0) target = 0;
  loadByIndex(target);
}

// data/ 直下の *.json をファイル名順に集める
void scanInstruments(){
  instrumentFiles.clear();
  File dir = new File(dataPath(""));
  File[] fs = dir.exists() ? dir.listFiles() : null;
  if (fs != null){
    for (File f : fs){
      if (f.isFile() && f.getName().toLowerCase().endsWith(".json")) instrumentFiles.add(f);
    }
    java.util.Collections.sort(instrumentFiles, new java.util.Comparator<File>(){
      public int compare(File a, File b){ return a.getName().compareToIgnoreCase(b.getName()); }
    });
  }
}
int indexOfName(String name){
  for (int i=0;i<instrumentFiles.size();i++) if (instrumentFiles.get(i).getName().equalsIgnoreCase(name)) return i;
  return -1;
}

// 一覧のインデックスで読み込む
void loadByIndex(int idx){
  if (idx<0 || idx>=instrumentFiles.size()) return;
  currentIdx = idx;
  ensureListVisible();
  loadInstrument(instrumentFiles.get(idx).getAbsolutePath());
}
void cycleInstrument(int delta){
  int n = instrumentFiles.size();
  if (n<=1) return;
  int base = currentIdx<0 ? 0 : currentIdx;
  loadByIndex(((base + delta) % n + n) % n);
}

void loadInstrument(String path){
  try {
    JSONObject root = loadJSONObject(path);
    model = new InstrModel(root, out.sampleRate());
    String fname = new File(path).getName();
    loadedName = fname + "  —  " + root.getString("name", "instrument") + " (" + model.noteName + " / " +
                 nf(model.fundamentalHz,0,1) + " Hz / " + model.harmonicCount + " 倍音, " +
                 (model.sustaining ? "持続音" : "減衰音") + ")";
    println("loaded: " + path + " → " + loadedName);
  } catch (Exception e){
    loadedName = "[読込失敗] " + new File(path).getName() + " : " + e;
    println("[エラー] JSON を読めませんでした: " + e);
  }
}

// ── 演奏 (押す / 離す) ──────────────────────────────────────
void pressNote(int midi){
  if (model == null) return;
  if (heldByNote.containsKey(midi)) return;            // 既に押している(キーリピート対策)
  ResynthVoice v = new ResynthVoice(model, midi, 0.95f, useSimpleADSR);
  v.patch(out);
  voices.add(v);
  heldByNote.put(midi, v);
}
void releaseNote(int midi){
  ResynthVoice v = heldByNote.remove(midi);
  if (v != null) v.noteOff();
}
void releaseAllHeld(){
  for (Integer n : new ArrayList<Integer>(heldByNote.keySet())) releaseNote(n);
  mousePressedNote = -1;
}
void stopAll(){
  for (ResynthVoice v : voices) v.unpatch(out);
  voices.clear(); heldByNote.clear();
  mousePressedNote = -1;
  songPlaying = false; songVoice = null; songCurrentNote = -1; songNoteOffMs = Integer.MAX_VALUE;
}
void shiftOctave(int dirSemis){
  releaseAllHeld();                                    // 押しっぱなしの鍵が迷子にならないよう離す
  baseOctaveMidi = constrain(baseOctaveMidi + dirSemis, 12, 96);
}

// ── きらきら星 ──────────────────────────────────────────────
void startSong(){
  stopAll();
  if (model == null) return;
  songPlaying = true; songIdx = 0;
  songNoteOnMs = millis();          // すぐ最初のノート
  songNoteOffMs = Integer.MAX_VALUE;
}
void updateSong(){
  if (!songPlaying) return;
  int now = millis();
  if (songVoice != null && now >= songNoteOffMs){     // 今のノートを離す
    songVoice.noteOff(); songVoice = null; songCurrentNote = -1; songNoteOffMs = Integer.MAX_VALUE;
  }
  if (now >= songNoteOnMs){                            // 次のノートを鳴らす
    if (songIdx >= SONG_NOTES.length){ songPlaying = false; return; }
    int durMs = SONG_BEATS[songIdx] * songBeatMs;
    if (model != null){
      ResynthVoice v = new ResynthVoice(model, SONG_NOTES[songIdx], 0.95f, useSimpleADSR);
      v.patch(out); voices.add(v);
      songVoice = v; songCurrentNote = SONG_NOTES[songIdx];
    }
    songNoteOffMs = now + (int)(durMs * 0.82f);       // 拍の 82% 鳴らして残りは隙間
    songNoteOnMs  = now + durMs;
    songIdx++;
  }
}

// ── 描画ループ ──────────────────────────────────────────────
void draw(){
  updateSong();
  // 終了したボイスを掃除
  for (Iterator<ResynthVoice> it = voices.iterator(); it.hasNext();){
    ResynthVoice v = it.next();
    if (v.done){
      v.unpatch(out); it.remove();
      if (heldByNote.get(v.midiNote) == v) heldByNote.remove(v.midiNote);
      if (songVoice == v){ songVoice = null; songCurrentNote = -1; }
    }
  }
  drawBackground();
  drawHeader();
  drawVisualization();
  drawControls();
  drawInstrumentList();
  drawKeyboard();
}

// 淡いグラデ背景(Glass Pastel 寄り)
void drawBackground(){
  for (int y=0;y<height;y++){
    float t = y/(float)height;
    int c = lerpColor(color(224,231,255), lerpColor(color(252,231,243), color(219,234,254), t), t);
    stroke(c); line(0,y,width,y);
  }
  noStroke();
}
void glassPanel(float x, float y, float w, float h){
  noStroke(); fill(255,255,255,150); rect(x,y,w,h,18);
  stroke(255,255,255,200); noFill(); rect(x,y,w,h,18); noStroke();
}
boolean mouseOver(float x, float y, float w, float h){
  return mouseX>=x && mouseX<=x+w && mouseY>=y && mouseY<=y+h;
}

void drawHeader(){
  glassPanel(20, 16, width-40, 64);
  fill(30,27,75); textSize(18);
  text("instrument_player", 34, 42);
  textSize(12); fill(99,102,241);
  text(loadedName, 34, 62);
  textAlign(RIGHT);
  text("包絡 " + (useSimpleADSR ? "ADSR4値" : "実エンベロープ") +
       "  |  鍵盤=押している間 鳴る / 離すとリリース   [ ]=音色  o=外部  r=再スキャン  a=包絡  ↑↓=オクターブ  p=きらきら星  Space=停止",
       width-34, 52);
  textAlign(LEFT);
}

// 読み込んだ定義の可視化(振幅エンベロープ + 倍音バー)
void drawVisualization(){
  float x=20, y=92, w=width-40, h=120;
  glassPanel(x,y,w,h);
  if (model==null) return;
  float pad=14;
  // 左半分: エンベロープ
  float ex=x+pad, ey=y+pad, ew=w*0.5f-pad*1.5f, eh=h-pad*2-12;
  fill(99,102,241); textSize(10); text("振幅エンベロープ（緑＝押している間のループ区間 / 赤＝リリース尾）", ex, ey-2);
  float[] env = model.envValues; int n=env.length;
  float origDur=(n-1)/model.envRate;
  float lx0=ex+ew*constrain(model.loopStartSec/origDur,0,1), lx1=ex+ew*constrain(model.loopEndSec/origDur,0,1);
  noStroke(); fill(34,197,94,40); rect(lx0,ey+6,lx1-lx0,eh);
  fill(239,68,68,30); rect(lx1,ey+6,ex+ew-lx1,eh);
  stroke(129,140,248); strokeWeight(1.5f); noFill();
  beginShape();
  for (int i=0;i<n;i++){ vertex(ex + ew*i/(float)(n-1), ey+6+eh - env[i]*eh); }
  endShape();
  strokeWeight(1);
  // 右半分: 倍音バー(dB)
  float hx=x+w*0.5f+pad*0.5f, hw=w*0.5f-pad*1.5f, hy=ey, hh=eh;
  fill(99,102,241); text("倍音の振幅(dB)", hx, hy-2);
  int nh=model.harmonicCount; float bw=hw/max(nh,1);
  for (int k=0;k<nh;k++){
    float a=model.harmAmp[k]; if (a<=0) continue;
    float db = max(-60, 20*(float)Math.log10(a+1e-9));
    float bh = (1 - db/-60.0f)*hh;
    fill(lerpColor(color(129,140,248), color(192,132,252), k/(float)max(nh-1,1)));
    rect(hx+k*bw+1, hy+6+hh-bh, bw-2, bh);
  }
  noStroke();
}

// ── コントロールバー(きらきら星 / 停止) ───────────────────
float ctlY, ctlH, btnSongX, btnSongW, btnStopX, btnStopW;
void drawControls(){
  float x=20, y=92+120+8, w=width-40, h=30;
  ctlY=y; ctlH=h;
  glassPanel(x,y,w,h);
  float by=y+5, bh=h-10;
  // きらきら星ボタン
  btnSongX=x+12; btnSongW=232;
  fill(songPlaying ? color(192,132,252) : (mouseOver(btnSongX,by,btnSongW,bh)?color(150,160,250):color(129,140,248)));
  noStroke(); rect(btnSongX,by,btnSongW,bh,8);
  fill(255); textAlign(CENTER); textSize(11);
  text(songPlaying ? "♪ 再生中…  (クリックで頭から)" : "▶  きらきら星 ♪ ドドソソララソ", btnSongX+btnSongW/2, by+bh*0.5f+4);
  // 全部止めるボタン
  btnStopX=btnSongX+btnSongW+10; btnStopW=110;
  fill(mouseOver(btnStopX,by,btnStopW,bh)?color(255,255,255,235):color(255,255,255,150));
  rect(btnStopX,by,btnStopW,bh,8);
  fill(40,37,90); text("■  全部止める", btnStopX+btnStopW/2, by+bh*0.5f+4);
  // ヒント
  fill(99,102,241); textAlign(LEFT); textSize(10);
  text("鍵盤は「押している間」鳴り、離すとリリース。'p' でも きらきら星。", btnStopX+btnStopW+18, by+bh*0.5f+4);
  textAlign(LEFT);
}
int controlButtonAt(float mx, float my){
  float by=ctlY+5, bh=ctlH-10;
  if (my<by || my>by+bh) return 0;
  if (mx>=btnSongX && mx<=btnSongX+btnSongW) return 1;
  if (mx>=btnStopX && mx<=btnStopX+btnStopW) return 2;
  return 0;
}

// ── インストゥルメント一覧 (data/*.json) ───────────────────
float listX, listY, listW, listH;            // 直近の描画範囲(クリック判定で使う)
void listGeom(){
  listX = 20; listY = 92+120+8+30+8;          // コントロールバーの下
  listW = width-40; listH = (height-180) - listY - 8;   // 鍵盤の上まで
}
int visibleRows(){ listGeom(); return max(1, (int)((listH - 36) / 22f)); }
void ensureListVisible(){
  int vis = visibleRows();
  if (currentIdx < listScroll) listScroll = currentIdx;
  if (currentIdx >= listScroll + vis) listScroll = currentIdx - vis + 1;
  listScroll = max(0, min(listScroll, max(0, instrumentFiles.size()-vis)));
}
void drawInstrumentList(){
  listGeom();
  glassPanel(listX, listY, listW, listH);
  fill(30,27,75); textSize(11); textAlign(LEFT);
  text("インストゥルメント (data/*.json) — クリック または [ / ] で切替", listX+14, listY+18);
  if (instrumentFiles.isEmpty()){
    fill(120,120,150);
    text("data/ に .json がありません。解析ツールでダウンロードした JSON をこのフォルダに置いて 'r' を押してください。", listX+14, listY+40);
    textAlign(LEFT); return;
  }
  int vis = visibleRows();
  float rowY0 = listY+28, rowH=22;
  for (int r=0; r<vis; r++){
    int i = listScroll + r;
    if (i >= instrumentFiles.size()) break;
    float ry = rowY0 + r*rowH;
    boolean cur = (i==currentIdx);
    boolean hover = (mouseX>listX+10 && mouseX<listX+listW-10 && mouseY>=ry && mouseY<ry+rowH-2);
    noStroke();
    fill(cur ? color(129,140,248) : (hover ? color(255,255,255,215) : color(255,255,255,120)));
    rect(listX+10, ry, listW-20, rowH-2, 7);
    fill(cur ? 255 : color(40,37,90)); textSize(11); textAlign(LEFT);
    text(nf(i+1,2) + ".  " + instrumentFiles.get(i).getName() + (cur ? "    ◀ 再生中" : ""), listX+22, ry+15);
  }
  fill(99,102,241); textSize(10); textAlign(RIGHT);
  text((listScroll>0 ? "▲ " : "") + (currentIdx+1) + " / " + instrumentFiles.size() +
       (listScroll+vis<instrumentFiles.size() ? " ▼" : ""), listX+listW-16, listY+18);
  textAlign(LEFT); noStroke();
}
int instrumentRowAt(float mx, float my){
  if (instrumentFiles.isEmpty()) return -1;
  listGeom();
  if (mx<listX+10 || mx>listX+listW-10) return -1;
  int vis = visibleRows();
  float rowY0 = listY+28, rowH=22;
  for (int r=0; r<vis; r++){
    int i = listScroll + r;
    if (i >= instrumentFiles.size()) break;
    float ry = rowY0 + r*rowH;
    if (my>=ry && my<ry+rowH-2) return i;
  }
  return -1;
}

// 鍵盤
float kbX, kbY, kbW, kbH, whiteW;
int   whiteCount;
final int[] WHITE_PC = {0,2,4,5,7,9,11};      // C D E F G A B
void drawKeyboard(){
  kbX=20; kbY=height-180; kbW=width-40; kbH=160;
  whiteCount = keyboardOctaves*7 + 1;          // 末尾に C を 1 つ追加
  whiteW = kbW/whiteCount;
  // 白鍵
  for (int i=0;i<whiteCount;i++){
    int midi = whiteMidi(i);
    boolean on = isNoteOn(midi);
    if (on) fill(129,140,248); else fill(255,255,255,235);
    stroke(129,140,248,90); rect(kbX+i*whiteW, kbY, whiteW, kbH, 0,0,6,6);
    fill(on?255:color(120,120,150)); textAlign(CENTER); textSize(9);
    text(noteName(midi), kbX+i*whiteW+whiteW/2, kbY+kbH-8);
  }
  // 黒鍵
  for (int i=0;i<whiteCount-1;i++){
    int pc = WHITE_PC[i%7];
    boolean hasSharp = (pc==0||pc==2||pc==5||pc==7||pc==9);  // C D F G A の右に黒鍵
    if (!hasSharp) continue;
    int midi = whiteMidi(i)+1;
    boolean on = isNoteOn(midi);
    float bx = kbX+(i+1)*whiteW - whiteW*0.30f, bw=whiteW*0.6f, bh=kbH*0.62f;
    if (on) fill(192,132,252); else fill(40,33,90);
    noStroke(); rect(bx, kbY, bw, bh, 0,0,5,5);
  }
  textAlign(LEFT); stroke(255); noStroke();
}
int whiteMidi(int whiteIndex){
  int oct = whiteIndex/7, idx=whiteIndex%7;
  return baseOctaveMidi + oct*12 + WHITE_PC[idx];
}
boolean isNoteOn(int midi){ return heldByNote.containsKey(midi) || midi == songCurrentNote; }

// ── マウス操作 ──────────────────────────────────────────────
void mousePressed(){
  int cb = controlButtonAt(mouseX, mouseY);   // コントロールバー
  if (cb == 1){ startSong(); return; }
  if (cb == 2){ stopAll();  return; }
  int li = instrumentRowAt(mouseX, mouseY);   // 音色一覧
  if (li >= 0){ loadByIndex(li); return; }
  int m = keyAt(mouseX, mouseY);              // 鍵盤(押し始め)
  if (m >= 0){ pressNote(m); mousePressedNote = m; }
}
void mouseReleased(){
  if (mousePressedNote >= 0){ releaseNote(mousePressedNote); mousePressedNote = -1; }
}
int keyAt(float mx, float my){
  if (my < kbY || my > kbY+kbH) return -1;
  for (int i=0;i<whiteCount-1;i++){           // 黒鍵を先に判定
    int pc = WHITE_PC[i%7];
    boolean hasSharp = (pc==0||pc==2||pc==5||pc==7||pc==9);
    if (!hasSharp) continue;
    float bx = kbX+(i+1)*whiteW - whiteW*0.30f, bw=whiteW*0.6f, bh=kbH*0.62f;
    if (mx>=bx && mx<=bx+bw && my<=kbY+bh) return whiteMidi(i)+1;
  }
  int i = (int)((mx-kbX)/whiteW);             // 白鍵
  if (i<0 || i>=whiteCount) return -1;
  return whiteMidi(i);
}

// ── キーボード操作 ──────────────────────────────────────────
void keyPressed(){
  if (key==CODED){
    if (keyCode==UP)   shiftOctave(+12);
    if (keyCode==DOWN) shiftOctave(-12);
    return;
  }
  char c = Character.toLowerCase(key);
  if (c=='['){ cycleInstrument(-1); return; }
  if (c==']'){ cycleInstrument(1);  return; }
  if (c=='o'){ selectInput("data/ 以外の JSON を選択", "onJsonSelected"); return; }
  if (c=='r'){ rescanAndLoad(false); return; }     // data/ を再スキャンし、いまのファイルを読み直す
  if (c=='a'){ useSimpleADSR = !useSimpleADSR; return; }
  if (c=='p'){ startSong(); return; }              // きらきら星
  if (c==' '){ stopAll(); return; }
  Integer off = KEYMAP.get(c);
  if (off != null) pressNote(baseOctaveMidi + off);
}
void keyReleased(){
  if (key==CODED) return;
  Integer off = KEYMAP.get(Character.toLowerCase(key));
  if (off != null) releaseNote(baseOctaveMidi + off);
}
void onJsonSelected(File f){
  if (f == null) return;
  loadInstrument(f.getAbsolutePath());
  scanInstruments();                                // data/ 内のファイルを選んだ場合は一覧に反映
  int i = -1;
  for (int k=0;k<instrumentFiles.size();k++)
    if (instrumentFiles.get(k).getAbsolutePath().equals(f.getAbsolutePath())){ i=k; break; }
  currentIdx = i;                                   // 外部ファイルなら -1(どの行も再生中表示にしない)
  if (i>=0) ensureListVisible();
}

// ── 音名 ────────────────────────────────────────────────────
final String[] NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
String noteName(int midi){ return NOTE_NAMES[((midi%12)+12)%12] + (midi/12 - 1); }

void dispose(){
  if (out != null) out.close();
  if (minim != null) minim.stop();
  super.dispose();
}


/* ==========================================================================
   InstrModel — JSON を解釈して合成に必要な配列を保持。スペクトル整形ノイズの
   ループバッファもここで一度だけ作る(全ボイスで共有)。
   ========================================================================== */
class InstrModel {
  float fundamentalHz;  int midiNote;  String noteName;
  boolean sustaining;   float inharmB;  int harmonicCount;
  // 倍音
  int     N;            // harmonics 配列長
  int[]   harmN;        // 倍音次数
  float[] harmRatio;    // 周波数比
  float[] harmAmp;      // 静的振幅(0..1)
  float[] harmPhase;    // 初期位相
  float[][] harmEnv;    // 倍音ごとの時間エンベロープ(0..1)、各 envPoints 点
  int     envPoints;
  float   harmNorm;     // 1/Σamp
  // 全体エンベロープ
  float[] envValues;  float envRate;
  float attackSec, decaySec, sustainLevel, releaseSec, loopStartSec, loopEndSec;
  // ノイズ
  float   noiseLevel;
  float[] noiseEnv;   float noiseEnvRate;
  float[] noiseTable; // スペクトル整形済み白色ノイズ(ループ用)

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
    float[] bandsHz   = (no!=null) ? toFloatArray(no.getJSONArray("bands_hz")) : new float[]{0,(int)(synthSampleRate/2)};
    float[] bandLevs  = (no!=null) ? toFloatArray(no.getJSONArray("band_levels")) : new float[]{1};
    noiseTable = makeShapedNoise(synthSampleRate, bandsHz, bandLevs);
  }

  // 白色ノイズを FFT 帯域ゲインで整形 → ループ用バッファ
  float[] makeShapedNoise(float sr, float[] bandsHz, float[] bandLevs){
    if (noiseLevel <= 0.0005f) return new float[]{0};
    int Nfft = 16384;     // ≒ 0.37 s @44.1k
    float[] buf = new float[Nfft];
    for (int i=0;i<Nfft;i++) buf[i] = random(-1,1);
    FFT fft = new FFT(Nfft, sr);
    fft.forward(buf);
    int bands = fft.specSize();
    for (int b=0;b<bands;b++){
      float fc = b * sr / Nfft;
      float g = bandGain(fc, bandsHz, bandLevs);
      fft.setBand(b, fft.getBand(b) * g);
    }
    fft.inverse(buf);
    float mx=1e-9f; for (int i=0;i<Nfft;i++) mx=max(mx, abs(buf[i]));
    for (int i=0;i<Nfft;i++) buf[i] /= mx;
    return buf;
  }
  float bandGain(float fc, float[] bandsHz, float[] bandLevs){
    for (int i=0;i<bandLevs.length;i++){
      float lo = bandsHz[i], hi = bandsHz[min(i+1, bandsHz.length-1)];
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
   ResynthVoice — 1 音ぶんの加算合成ボイス。Minim の UGen として out に patch する。
   ゲートモデル: 生成時は「押されている」状態で鳴り続け、noteOff() でリリースに入る。
   ========================================================================== */
class ResynthVoice extends UGen {
  InstrModel m;
  int   midiNote;
  float targetF0;
  float gain;            // velocity 由来
  boolean simpleADSR;

  float[] phase;         // 倍音ごとの位相
  double  noisePos;
  float   tSec = 0;      // 経過秒
  boolean done = false;

  // ゲート状態(audio スレッドが読むので volatile で公開)
  volatile boolean releasing = false;
  float releaseStartT = 0;       // リリース開始の経過秒
  float releaseStartLevel = 0;   // リリース開始時の振幅(0..1) — ジャンプ防止
  float releaseHoldWarpT = 0;    // リリース中に倍音/ノイズ包絡を固定する原音時間

  // ワープ用に展開した値
  float origDur, headT, loopLen;

  ResynthVoice(InstrModel model, int midi, float velocity, boolean simple){
    this.m = model; this.midiNote = midi;
    this.targetF0 = 440f * pow(2, (midi-69)/12.0f);
    this.gain = constrain(velocity, 0, 1);
    this.simpleADSR = simple;
    phase = new float[m.N];
    for (int i=0;i<m.N;i++) phase[i] = m.harmPhase[i];
    origDur = m.origDurSec();
    headT   = m.loopStartSec;
    loopLen = max(m.loopEndSec - m.loopStartSec, 1e-3f);
  }

  float relSec(){ return max(m.releaseSec, 0.02f); }

  // キーを離した(または曲のノートオフ)
  void noteOff(){
    if (releasing) return;
    releaseStartLevel = sustainBodyLevel(tSec);   // 直前の本体振幅
    releaseHoldWarpT  = warpBody(tSec);
    releaseStartT     = tSec;
    releasing = true;                             // ← 最後に立てる(他フィールドの可視性を確保)
  }

  // 押している間の本体振幅(0..1) — リリース処理は含まない
  float sustainBodyLevel(float t){
    if (simpleADSR){
      float a=m.attackSec, d=m.decaySec, s=m.sustainLevel;
      if (t < a) return t/max(a,1e-4f);
      if (!m.sustaining){                         // 減衰音: A→D で ≒0 へ落として保持
        if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, 0.02f, u); }
        return 0.02f;
      }
      if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, s, u); }
      return s;                                   // 押している間サステインを保持
    }
    return sampleCurve(m.envValues, m.envRate, warpBody(t));
  }
  // 押している間の原音時間(持続音はループ、減衰音は鳴らし切り)
  float warpBody(float t){
    if (!m.sustaining) return min(t, origDur);
    if (t < headT) return t;
    float u = (t - headT) % loopLen;
    return m.loopStartSec + u;
  }
  // 実際の振幅(0..1) — リリース込み
  float ampAt(float t){
    if (!releasing) return sustainBodyLevel(t);
    float u = (t - releaseStartT) / relSec();
    if (u >= 1) return 0;
    float k = 1 - u;
    return releaseStartLevel * k * k;             // (1-u)^2 ≒ やわらかい減衰
  }
  // 倍音 k の時間エンベロープ(0..1)
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
  // 線形補間でカーブを評価(時刻 sec、レート rate)
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
    float s = 0;
    for (int k=0;k<m.N;k++){
      float amp = m.harmAmp[k]; if (amp<=0) continue;
      int   n1  = m.harmN[k];
      float f   = targetF0 * m.harmRatio[k] * sqrt(1 + m.inharmB*n1*n1);
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
    s *= a * gain * 0.9f;
    for (int i=0;i<channels.length;i++) channels[i] = s;
    tSec += 1.0f/sr;
    if (releasing && (tSec - releaseStartT) >= relSec()) done = true;       // リリース完了
    else if (!done && a <= 1e-4f && tSec > 0.15f) done = true;              // 減衰音が自然に死んだ
  }
}
