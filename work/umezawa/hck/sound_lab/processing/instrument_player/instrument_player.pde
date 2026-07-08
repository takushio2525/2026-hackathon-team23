/* ==========================================================================
   instrument_player — sound_lab で解析した音色定義(JSON)を読み込み、
   音程を与えると「限りなく元に近い音」を鳴らす Processing スケッチ。

   発音モデル: キー(または鍵盤クリック)を押している間ずっと鳴り続け、離すとリリース。
               持続音は押している間サステイン区間をループ、減衰音は自然に鳴り切る。

   合成方式: sound_lab.instrument/1 の倍音・エンベロープ・ノイズ・変調、原音サンプル、
             調整後 JSON の全音響 fx (波形/ブラス層/ノイズ/ドライブ/EQ/フィルタ/
             コーラス/リバーブ/移調・グライド) を再現。

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
     - 'l': 改善版 ↔ 旧 test_multi 互換(固定倍音 + 線形 ADSR)を切替
     - 'a': 改善版での振幅包絡の方式切替(ADSR 4 値 ↔ 実エンベロープ)
     - Shift+'H': 倍音ごとの立ち上がり  /  Shift+'N': 残差ノイズ  /  Shift+'E': ボディ EQ・管共鳴
       (小文字 h/n/e は演奏鍵盤として使用)  /  Space: 全音停止

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
boolean useSimpleADSR = true;     // 改善版 test_multi の既定: A/D/S/R 4 値で全体振幅を作る
boolean enableDynamicHarmonics = true;
boolean enableInstrumentNoise  = true;
boolean enableInstrumentFx     = true;
boolean legacyPlayback         = false;  // 現行 pc_app/test_multi と同じ固定倍音 + 線形 ADSR
float lastTriggeredF0 = Float.NaN;       // fx.glide_ms のノート間ポルタメント開始音程

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
  if (target < 0) target = newestInstrumentIndex();
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
int newestInstrumentIndex(){
  int newest=-1; long newestTime=Long.MIN_VALUE;
  for (int i=0;i<instrumentFiles.size();i++){
    File f=instrumentFiles.get(i);
    if (f.getName().equalsIgnoreCase("example_organ.json")) continue;
    if (f.lastModified()>newestTime){ newestTime=f.lastModified(); newest=i; }
  }
  return newest;
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
    useSimpleADSR = model.preferSimpleADSR;           // 調整後 JSON の fx.env_mode を初期値にする
    String fname = new File(path).getName();
    loadedName = fname + "  —  " + root.getString("name", "instrument") + " (" + model.noteName + " / " +
                 nf(model.fundamentalHz,0,1) + " Hz / " + model.harmonicCount + " 倍音, " +
                 (model.sustaining ? "持続音" : "減衰音") + " / " + model.profileLabel + ")";
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
  ResynthVoice v = new ResynthVoice(model, midi, 0.95f, effectiveSimpleADSR(), legacyPlayback);
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
  lastTriggeredF0 = Float.NaN;
}
void toggleLegacyPlayback(){
  stopAll();                         // 旧/改善版の要素が同じボイス内で混ざらないようにする
  legacyPlayback = !legacyPlayback;
}
boolean effectiveSimpleADSR(){ return legacyPlayback || useSimpleADSR; }
boolean dynamicHarmonicsOn(){ return !legacyPlayback && enableDynamicHarmonics && (model==null || model.useHarmonicEnvelope); }
boolean instrumentNoiseOn(){ return !legacyPlayback && enableInstrumentNoise && (model==null || model.useNoise); }
boolean instrumentFxOn(){ return !legacyPlayback && enableInstrumentFx && (model==null || model.useBodyFx); }
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
      ResynthVoice v = new ResynthVoice(model, SONG_NOTES[songIdx], 0.95f, effectiveSimpleADSR(), legacyPlayback);
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
  text("再生 " + (legacyPlayback ? "旧test_multi" : "改善版") +
       "  |  包絡 " + (effectiveSimpleADSR() ? "ADSR4値" : "実エンベロープ") +
       "  |  H:" + onOff(dynamicHarmonicsOn()) + " N:" + onOff(instrumentNoiseOn()) + " E:" + onOff(instrumentFxOn()) +
       "  |  l=旧/改善  [ ]=音色  r=再読込  a=包絡  ↑↓=oct  p=曲  Space=停止",
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
  fill(99,102,241); textSize(10); text("解析した実エンベロープ（発音方式は上部の ADSR / 実エンベロープ表示を参照）", ex, ey-2);
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
float ctlY, ctlH, btnSongX, btnSongW, btnStopX, btnStopW, btnModeX, btnModeW;
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
  // 旧 test_multi 互換再生の一括切替
  btnModeX=btnStopX+btnStopW+10; btnModeW=170;
  fill(legacyPlayback ? color(20,184,166) : (mouseOver(btnModeX,by,btnModeW,bh)?color(255,255,255,235):color(255,255,255,150)));
  rect(btnModeX,by,btnModeW,bh,8);
  fill(legacyPlayback ? 255 : color(40,37,90));
  text(legacyPlayback ? "旧test_multi 再生中" : "旧test_multi で聞く", btnModeX+btnModeW/2, by+bh*0.5f+4);
  // ヒント
  fill(99,102,241); textAlign(LEFT); textSize(10);
  text("鍵盤は押している間鳴る。'l' でも旧/改善版を切替。", btnModeX+btnModeW+18, by+bh*0.5f+4);
  textAlign(LEFT);
}
int controlButtonAt(float mx, float my){
  float by=ctlY+5, bh=ctlH-10;
  if (my<by || my>by+bh) return 0;
  if (mx>=btnSongX && mx<=btnSongX+btnSongW) return 1;
  if (mx>=btnStopX && mx<=btnStopX+btnStopW) return 2;
  if (mx>=btnModeX && mx<=btnModeX+btnModeW) return 3;
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
  if (cb == 3){ toggleLegacyPlayback(); return; }
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
  if (key=='H'){ enableDynamicHarmonics = !enableDynamicHarmonics; return; }
  if (key=='N'){ enableInstrumentNoise  = !enableInstrumentNoise;  return; }
  if (key=='E'){ enableInstrumentFx     = !enableInstrumentFx;     return; }
  char c = Character.toLowerCase(key);
  if (c=='['){ cycleInstrument(-1); return; }
  if (c==']'){ cycleInstrument(1);  return; }
  if (c=='o'){ selectInput("data/ 以外の JSON を選択", "onJsonSelected"); return; }
  if (c=='r'){ rescanAndLoad(false); return; }     // data/ を再スキャンし、いまのファイルを読み直す
  if (c=='l'){ toggleLegacyPlayback(); return; }
  if (c=='a'){ useSimpleADSR = !useSimpleADSR; return; }
  if (c=='p'){ startSong(); return; }              // きらきら星
  if (c==' '){ stopAll(); return; }
  Integer off = KEYMAP.get(c);
  if (off != null) pressNote(baseOctaveMidi + off);
}
String onOff(boolean enabled){ return enabled ? "ON" : "OFF"; }
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
  float   synthSampleRate;
  String  format, profile, profileLabel;
  float fundamentalHz;  int midiNote;  String noteName;
  boolean sustaining;   float inharmB;  int harmonicCount;
  // 倍音
  int     N;            // harmonics 配列長
  int[]   harmN;        // 倍音次数
  float[] harmRatio;    // 周波数比
  float[] harmAmp;      // 静的振幅(0..1)
  float[] harmPhase;    // 初期位相
  float[][] harmEnv;    // 倍音ごとの時間エンベロープ(0..1)、各 envPoints 点
  float[] harmSustain;  // 立ち上がり後に保持するループ域平均
  int     envPoints;
  float   harmNorm;     // 1/Σamp
  // 全体エンベロープ
  float[] envValues;  float envRate;
  float attackSec, decaySec, sustainLevel, releaseSec, loopStartSec, loopEndSec;
  // ノイズ
  float   noiseLevel;
  float[] noiseEnv;   float noiseEnvRate;
  float[] noiseTable; // スペクトル整形済み白色ノイズ(ループ用)
  // モジュレーション(ビブラート=ピッチの周期揺れ / トレモロ=音量の周期揺れ)。無ければ 0
  float   vibRateHz, vibDepthCents, vibOnsetSec;   // depthCents は「全幅」(deviation = ±depthCents/2)
  float   tremRateHz, tremDepth;
  String  vibShape, tremShape;
  boolean useHarmonicEnvelope, useNoise, useBodyFx, preferSimpleADSR;
  float   transposeSemis, fineCents, glideMs, humanizeCents, decayStretch, masterVolume;
  boolean expAttack;
  float[] waveCycle;  float waveMix;
  float[] attackSample, sustainSample, drumSample;
  float attackSampleRate, sustainSampleRate, drumSampleRate;
  float attackRootMidi, sustainRootMidi, drumRootMidi;
  float sustainLoopStartSec, sustainLoopEndSec;
  float attackSampleMix, sustainSampleMix, drumSampleMix;
  boolean drumPitchFollow;
  float   brassMix, brassDetuneCents;
  String  noiseMode;
  float   noiseHpHz, noiseLpHz, attackNoise, breathAmount;
  float   eqLowGain, eqMidFreq, eqMidGain, eqMidQ, eqPresenceGain, eqHighGain;
  float   trumpetResonance;
  float   driveAmount, driveToneHz;
  String  filterMode;
  float   filterCutoffHz, filterQ, filterLfoRateHz, filterLfoDepth;
  float   chorusMix, chorusRateHz, chorusDepth, chorusWidth;
  float   reverbMix, reverbSizeSec, reverbDamping, reverbPreMs, reverbWidth;

  InstrModel(JSONObject root, float synthSampleRate){
    this.synthSampleRate = synthSampleRate;
    format        = root.getString("format", "sound_lab.instrument/1");
    if (!format.equals("sound_lab.instrument/1")) throw new RuntimeException("非対応の format: " + format);
    profile       = root.getString("instrument_profile", "auto");
    profileLabel  = root.getString("instrument_profile_label", profile);
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
    harmEnv=new float[N][]; harmSustain=new float[N]; envPoints=1;
    float sumAmp=0;
    useHarmonicEnvelope = false;
    for (int i=0;i<N;i++){
      JSONObject h = ha.getJSONObject(i);
      harmN[i]     = h.getInt("n", i+1);
      harmRatio[i] = h.getFloat("ratio", harmN[i]);
      harmAmp[i]   = h.getFloat("amp", 0);
      harmPhase[i] = h.getFloat("phase", 0);
      JSONArray ev = h.hasKey("env") ? h.getJSONArray("env") : null;
      harmEnv[i]   = (ev!=null && ev.size()>=2) ? toFloatArray(ev) : new float[]{1,1};
      if (ev!=null && ev.size()>=2) useHarmonicEnvelope = true;
      float originalDuration = max((envValues.length-1)/envRate, 1e-3f);
      int sustainA = constrain(round((loopStartSec/originalDuration)*(harmEnv[i].length-1)), 0, harmEnv[i].length-1);
      int sustainB = constrain(round((loopEndSec/originalDuration)*(harmEnv[i].length-1)), sustainA, harmEnv[i].length-1);
      float sustainSum=0; int sustainCount=0;
      for (int j=sustainA;j<=sustainB;j++){ sustainSum += harmEnv[i][j]; sustainCount++; }
      harmSustain[i] = sustainCount>0 ? sustainSum/sustainCount : 1;
      envPoints    = max(envPoints, harmEnv[i].length);
      if (harmAmp[i]>0) sumAmp += harmAmp[i];
    }
    harmNorm = 1.0f / max(sumAmp, 1.0f);
    harmonicCount = 0; for (int i=0;i<N;i++) if (harmAmp[i]>0) harmonicCount++;

    JSONObject no = root.hasKey("noise") ? root.getJSONObject("noise") : null;
    noiseLevel   = no!=null ? no.getFloat("level", 0) : 0;
    noiseEnv     = (no!=null && no.hasKey("envelope")) ? toFloatArray(no.getJSONArray("envelope")) : new float[]{1,1};
    noiseEnvRate = no!=null ? no.getFloat("rate_hz", 200) : 200;
    float[] bandsHz   = (no!=null && no.hasKey("bands_hz")) ? toFloatArray(no.getJSONArray("bands_hz")) : new float[]{0,(int)(synthSampleRate/2)};
    float[] bandLevs  = (no!=null && no.hasKey("band_levels")) ? toFloatArray(no.getJSONArray("band_levels")) : new float[]{1};
    noiseTable = makeShapedNoise(synthSampleRate, bandsHz, bandLevs);
    useNoise = noiseLevel > 0.0005f;

    // スタジオが書き出す fx。無い場合はすべて素通し。
    JSONObject fx = root.hasKey("fx") ? root.getJSONObject("fx") : null;
    preferSimpleADSR = fx==null || !fx.getString("env_mode", "adsr").equals("recorded");
    decayStretch     = fx!=null ? max(0.1f, fx.getFloat("decay_stretch", 1)) : 1;
    expAttack        = fx!=null && fx.getString("attack_curve", "lin").equals("exp");
    transposeSemis   = fx!=null ? fx.getFloat("transpose_semis", 0) : 0;
    fineCents        = fx!=null ? fx.getFloat("fine_cents", 0) : 0;
    glideMs          = fx!=null ? constrain(fx.getFloat("glide_ms", 0), 0, 400) : 0;
    humanizeCents    = fx!=null ? max(0, fx.getFloat("humanize_cents", 0)) : 0;
    masterVolume     = fx!=null ? max(0,fx.getFloat("master_volume",fx.getFloat("balance_master_volume",1))) : 1;
    if (fx!=null) useHarmonicEnvelope &= fx.getBoolean("harm_follow_env", true);

    JSONObject waveform = root.hasKey("waveform") ? root.getJSONObject("waveform") : null;
    waveCycle = (waveform!=null && waveform.hasKey("one_cycle")) ? toFloatArray(waveform.getJSONArray("one_cycle")) : new float[0];
    waveMix   = (fx!=null && waveCycle.length>=8) ? constrain(fx.getFloat("trumpet_wave_mix", 0),0,1) : 0;

    JSONObject attack = root.hasKey("attack_sample") ? root.getJSONObject("attack_sample") : null;
    attackSample     = sampleValues(attack);
    attackSampleRate = sampleRateOf(attack, synthSampleRate);
    attackRootMidi   = sampleRootOf(attack, midiNote);
    attackSampleMix  = (fx!=null && attackSample.length>1) ? constrain(fx.getFloat("attack_sample_mix",0),0,1.5f) : 0;
    JSONObject sustain = root.hasKey("sustain_sample") ? root.getJSONObject("sustain_sample") : null;
    sustainSample       = sampleValues(sustain);
    sustainSampleRate   = sampleRateOf(sustain, synthSampleRate);
    sustainRootMidi     = sampleRootOf(sustain, midiNote);
    sustainLoopStartSec = sustain!=null ? max(0,sustain.getFloat("loop_start_sec",0)) : 0;
    sustainLoopEndSec   = sustain!=null ? sustain.getFloat("loop_end_sec",sustainSample.length/max(sustainSampleRate,1)) : 0;
    sustainLoopEndSec   = constrain(sustainLoopEndSec,sustainLoopStartSec+1/max(sustainSampleRate,1),sustainSample.length/max(sustainSampleRate,1));
    sustainSampleMix    = (fx!=null && sustainSample.length>1) ? constrain(fx.getFloat("sustain_sample_mix",0),0,0.9f) : 0;
    JSONObject drum = root.hasKey("drum_sample") ? root.getJSONObject("drum_sample") : null;
    drumSample       = sampleValues(drum);
    drumSampleRate   = sampleRateOf(drum, synthSampleRate);
    drumRootMidi     = sampleRootOf(drum, midiNote);
    drumSampleMix    = (fx!=null && drumSample.length>1) ? constrain(fx.getFloat("drum_sample_mix",0),0,1.5f) : 0;
    drumPitchFollow  = fx!=null && fx.getBoolean("drum_pitch_follow",false);

    JSONObject brass = (fx!=null && fx.hasKey("brass_layer")) ? fx.getJSONObject("brass_layer") : null;
    brassMix         = brass!=null ? constrain(brass.getFloat("mix",0),0,0.75f) : 0;
    brassDetuneCents = brass!=null ? constrain(brass.getFloat("detune_cents",0),0,18) : 0;

    JSONObject eq = (fx!=null && fx.hasKey("body_eq")) ? fx.getJSONObject("body_eq") : null;
    eqLowGain      = eq!=null ? eq.getFloat("low_gain", 0) : 0;
    eqMidFreq      = eq!=null ? eq.getFloat("mid_freq", 900) : 900;
    eqMidGain      = eq!=null ? eq.getFloat("mid_gain", 0) : 0;
    eqMidQ         = eq!=null ? max(0.1f, eq.getFloat("mid_q", 1)) : 1;
    eqPresenceGain = eq!=null ? eq.getFloat("presence_gain", 0) : 0;
    eqHighGain     = eq!=null ? eq.getFloat("high_gain", 0) : 0;
    trumpetResonance = fx!=null ? constrain(fx.getFloat("trumpet_resonance", 0), 0, 1) : 0;
    JSONObject drive = (fx!=null && fx.hasKey("drive")) ? fx.getJSONObject("drive") : null;
    driveAmount = drive!=null ? constrain(drive.getFloat("amount",0),0,1) : 0;
    driveToneHz = drive!=null ? constrain(drive.getFloat("tone_hz",16000),400,synthSampleRate*0.45f) : 16000;
    JSONObject filter = (fx!=null && fx.hasKey("filter")) ? fx.getJSONObject("filter") : null;
    filterMode      = filter!=null ? filter.getString("mode","off") : "off";
    filterCutoffHz  = filter!=null ? constrain(filter.getFloat("cutoff_hz",6000),30,synthSampleRate*0.45f) : 6000;
    filterQ         = filter!=null ? constrain(filter.getFloat("q",1),0.1f,20) : 1;
    filterLfoRateHz = filter!=null ? constrain(filter.getFloat("lfo_rate_hz",1.5f),0.02f,12) : 1.5f;
    filterLfoDepth  = filter!=null ? constrain(filter.getFloat("lfo_depth",0),0,1) : 0;
    JSONObject chorus = (fx!=null && fx.hasKey("chorus")) ? fx.getJSONObject("chorus") : null;
    chorusMix    = chorus!=null ? constrain(chorus.getFloat("mix",0),0,1) : 0;
    chorusRateHz = chorus!=null ? constrain(chorus.getFloat("rate_hz",0.25f),0.02f,4) : 0.25f;
    chorusDepth  = chorus!=null ? constrain(chorus.getFloat("depth",0.4f),0,1) : 0.4f;
    chorusWidth  = chorus!=null ? constrain(chorus.getFloat("width",0.8f),0,1) : 0.8f;
    noiseMode    = fx!=null ? fx.getString("noise_mode","recorded") : "recorded";
    if (!noiseMode.equals("recorded") && !noiseMode.equals("constant") && !noiseMode.equals("attack")) noiseMode="recorded";
    noiseHpHz    = fx!=null ? constrain(fx.getFloat("noise_hp_hz",20),10,synthSampleRate*0.45f) : 20;
    noiseLpHz    = fx!=null ? constrain(fx.getFloat("noise_lp_hz",12000),200,synthSampleRate*0.49f) : synthSampleRate*0.45f;
    if (noiseLpHz <= noiseHpHz) noiseLpHz=min(synthSampleRate*0.49f,noiseHpHz+100);
    attackNoise  = fx!=null ? constrain(fx.getFloat("attack_noise",0),0,3) : 0;
    breathAmount = fx!=null ? constrain(fx.getFloat("breath_amount",0),0,1) : 0;
    JSONObject reverb = (fx!=null && fx.hasKey("reverb")) ? fx.getJSONObject("reverb") : null;
    reverbMix     = reverb!=null ? constrain(reverb.getFloat("mix",0),0,1) : 0;
    reverbSizeSec = reverb!=null ? constrain(reverb.getFloat("size_sec",2.2f),0.1f,6) : 2.2f;
    reverbDamping = reverb!=null ? constrain(reverb.getFloat("damping",0.35f),0,0.98f) : 0.35f;
    reverbPreMs   = reverb!=null ? constrain(reverb.getFloat("pre_ms",0),0,180) : 0;
    reverbWidth   = reverb!=null ? constrain(reverb.getFloat("width",0.85f),0,1) : 0.85f;
    if (breathAmount>0.001f && noiseTable.length<=1){
      float savedNoiseLevel=noiseLevel;
      noiseLevel=max(noiseLevel,0.001f);
      noiseTable=makeShapedNoise(synthSampleRate,new float[]{0,synthSampleRate*0.5f},new float[]{1});
      noiseLevel=savedNoiseLevel;
    }
    useNoise = noiseLevel>0.0005f || breathAmount>0.001f;
    useBodyFx = abs(eqLowGain)+abs(eqMidGain)+abs(eqPresenceGain)+abs(eqHighGain)+trumpetResonance+
                driveAmount+chorusMix+reverbMix+attackSampleMix+sustainSampleMix+drumSampleMix+
                attackNoise+breathAmount+(filterMode.equals("off")?0:1) > 0.001f;

    JSONObject compat = root.hasKey("test_multi_compat") ? root.getJSONObject("test_multi_compat") : null;
    if (compat != null){
      useHarmonicEnvelope &= compat.getBoolean("dynamic_harmonics", true);
      useNoise &= compat.getBoolean("noise", true);
      useBodyFx &= compat.getBoolean("body_fx", true);
    }

    // モジュレーション(任意)。古い JSON には無いので hasKey で守る
    JSONObject mod = root.hasKey("modulation") ? root.getJSONObject("modulation") : null;
    JSONObject vib = (mod!=null && mod.hasKey("vibrato")) ? mod.getJSONObject("vibrato") : null;
    JSONObject trem= (mod!=null && mod.hasKey("tremolo")) ? mod.getJSONObject("tremolo") : null;
    vibRateHz     = (vib!=null && vib.getBoolean("detected", false)) ? vib.getFloat("rate_hz", 0) : 0;
    vibDepthCents = (vib!=null && vib.getBoolean("detected", false)) ? vib.getFloat("depth_cents", 0) : 0;
    vibOnsetSec   = (vib!=null) ? vib.getFloat("onset_sec", 0) : 0;
    tremRateHz    = (trem!=null && trem.getBoolean("detected", false)) ? trem.getFloat("rate_hz", 0) : 0;
    tremDepth     = (trem!=null && trem.getBoolean("detected", false)) ? constrain(trem.getFloat("depth", 0),0,0.95f) : 0;
    vibShape      = vib!=null ? normalizeLfoShape(vib.getString("shape","sine")) : "sine";
    tremShape     = trem!=null ? normalizeLfoShape(trem.getString("shape","sine")) : "sine";

    // 調整後 JSON で意図的に指定した変調は、解析時の detected 値より優先。
    JSONObject fxMod = (fx!=null && fx.hasKey("modulation")) ? fx.getJSONObject("modulation") : null;
    if (fxMod != null){
      vibRateHz     = fxMod.getFloat("vibrato_rate_hz", vibRateHz);
      vibDepthCents = max(0, fxMod.getFloat("vibrato_depth_cents", vibDepthCents));
      vibOnsetSec   = max(0, fxMod.getFloat("vibrato_onset_sec", vibOnsetSec));
      tremRateHz    = fxMod.getFloat("tremolo_rate_hz", tremRateHz);
      tremDepth     = constrain(fxMod.getFloat("tremolo_depth", tremDepth),0,0.95f);
      vibShape      = normalizeLfoShape(fxMod.getString("vibrato_shape",vibShape));
      tremShape     = normalizeLfoShape(fxMod.getString("tremolo_shape",tremShape));
    }
  }

  float[] sampleValues(JSONObject sample){
    return (sample!=null && sample.hasKey("values")) ? toFloatArray(sample.getJSONArray("values")) : new float[0];
  }
  float sampleRateOf(JSONObject sample,float fallback){
    return sample!=null ? max(1,sample.getFloat("sample_rate",fallback)) : fallback;
  }
  float sampleRootOf(JSONObject sample,float fallback){
    return sample!=null ? sample.getFloat("root_midi_note",fallback) : fallback;
  }
  String normalizeLfoShape(String shape){
    if (shape.equals("triangle") || shape.equals("sawtooth") || shape.equals("square")) return shape;
    return "sine";
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
  float currentF0;
  float gain;            // velocity 由来
  boolean simpleADSR;
  boolean legacyMode;    // 旧 test_multi: 倍音env/ノイズ/変調/body FX を使わない

  float[] phase;         // 倍音ごとの位相
  float[] layerPhase;    // fx.brass_layer 用の補助発振位相
  float   wavePhase;
  double  noisePos;
  double  attackSamplePos, sustainSamplePos, drumSamplePos;
  boolean attackSampleDone, drumSampleDone;
  float   tSec = 0;      // 経過秒
  float   vibPhase = 0, tremPhase = 0;   // ビブラート/トレモロ LFO の位相
  boolean done = false;

  // ゲート状態(audio スレッドが読むので volatile で公開)
  volatile boolean releasing = false;
  float releaseStartT = 0;       // リリース開始の経過秒
  float releaseStartLevel = 0;   // リリース開始時の振幅(0..1) — ジャンプ防止
  float releaseHoldWarpT = 0;    // リリース中に倍音/ノイズ包絡を固定する原音時間

  // ワープ用に展開した値
  float origDur, headT, loopLen;
  BodyToneFx bodyFx;
  StudioStereoFx stereoFx;
  BiquadMono noiseHp, noiseLp, sustainTone;
  float silentSince=-1;

  ResynthVoice(InstrModel model, int midi, float velocity, boolean simple, boolean legacy){
    this.m = model; this.midiNote = midi;
    float studioCents = legacy ? 0 : model.fineCents + random(-model.humanizeCents, model.humanizeCents);
    float studioSemis = legacy ? 0 : model.transposeSemis;
    this.targetF0 = 440f * pow(2, (midi-69+studioSemis)/12.0f) * pow(2,studioCents/1200.0f);
    this.currentF0 = (!legacy && model.glideMs>=6 && !Float.isNaN(lastTriggeredF0)) ? lastTriggeredF0 : targetF0;
    lastTriggeredF0 = targetF0;
    this.gain = constrain(velocity, 0, 1);
    this.simpleADSR = simple;
    this.legacyMode = legacy;
    phase = new float[m.N];
    layerPhase = new float[m.N];
    for (int i=0;i<m.N;i++){ phase[i] = m.harmPhase[i]; layerPhase[i] = m.harmPhase[i]; }
    origDur = m.origDurSec();
    headT   = m.loopStartSec;
    loopLen = max(m.loopEndSec - m.loopStartSec, 1e-3f);
    bodyFx  = new BodyToneFx(m);
    stereoFx= new StudioStereoFx(m);
    noiseHp = new BiquadMono(); noiseHp.setHighPass(m.synthSampleRate,m.noiseHpHz,0.5f);
    noiseLp = new BiquadMono(); noiseLp.setLowPass(m.synthSampleRate,m.noiseLpHz,0.5f);
    sustainTone = new BiquadMono(); sustainTone.setLowPass(m.synthSampleRate,4800,0.45f);
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
      float a=m.attackSec, d=m.decaySec*(legacyMode?1:m.decayStretch), s=m.sustainLevel;
      if (t < a){
        float u=t/max(a,1e-4f);
        return (!legacyMode && m.expAttack) ? (pow(1000,u)-1)/999.0f : u;
      }
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
    if (!m.sustaining) return min(t/(legacyMode?1:m.decayStretch), origDur);
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
    float evalT = releasing ? releaseHoldWarpT : t;
    if (evalT >= headT) return m.harmSustain[k];
    return sampleCurve(he, rate, evalT);
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
  float sampleCycle(float[] c, float pos){
    if (c.length<2) return 0;
    float p=pos*c.length; int i0=((int)p)%c.length, i1=(i0+1)%c.length; float f=p-(int)p;
    return c[i0]+(c[i1]-c[i0])*f;
  }
  float sampleLinear(float[] c,double pos){
    if (c.length<2 || pos<0 || pos>=c.length-1) return 0;
    int i0=(int)pos, i1=i0+1; float f=(float)(pos-i0);
    return c[i0]+(c[i1]-c[i0])*f;
  }
  float lfoValue(String shape,float phase){
    float p=(phase/TWO_PI)%1.0f; if(p<0)p+=1;
    if(shape.equals("triangle")) return 1-4*abs(p-0.5f);
    if(shape.equals("sawtooth")) return 2*p-1;
    if(shape.equals("square")) return p<0.5f?1:-1;
    return sin(phase);
  }
  float noiseShapeAt(float t){
    if (m.noiseMode.equals("constant")) return 1;
    if (m.noiseMode.equals("attack")) return max(0,1-t/0.12f);
    return noiseEnvAt(t);
  }
  float sampleLayers(float sr,float pitchMul){
    if (legacyMode || !enableInstrumentFx) return 0;
    float direct=0;
    if (!attackSampleDone && m.attackSampleMix>0.001f && m.attackSample.length>1){
      float semis=midiNote-m.attackRootMidi+m.transposeSemis;
      float rate=constrain(pow(2,semis/12.0f),0.25f,4);
      float pitchSafe=1/(1+abs(semis)*0.08f);
      float dur=m.attackSample.length/m.attackSampleRate/max(rate,1e-4f);
      float env=tSec<0.006f?tSec/0.006f:(float)Math.exp(-max(0,tSec-dur*0.62f)/0.035f);
      direct+=sampleLinear(m.attackSample,attackSamplePos)*m.attackSampleMix*0.55f*pitchSafe*env;
      attackSamplePos+=m.attackSampleRate*rate/sr;
      if(attackSamplePos>=m.attackSample.length-1) attackSampleDone=true;
    }
    if (m.sustainSampleMix>0.001f && m.sustainSample.length>1){
      float semis=midiNote-m.sustainRootMidi+m.transposeSemis;
      float rate=constrain((currentF0/max(targetF0,1e-4f))*pow(2,semis/12.0f),0.25f,4);
      float pitchSafe=1/(1+semis*semis*0.12f);
      int loopA=constrain(round(m.sustainLoopStartSec*m.sustainSampleRate),0,m.sustainSample.length-2);
      int loopB=constrain(round(m.sustainLoopEndSec*m.sustainSampleRate),loopA+1,m.sustainSample.length-1);
      if(sustainSamplePos<loopA || sustainSamplePos>=loopB) sustainSamplePos=loopA;
      direct+=sustainTone.process(sampleLinear(m.sustainSample,sustainSamplePos))*m.sustainSampleMix*0.48f*pitchSafe*ampAt(tSec);
      sustainSamplePos+=m.sustainSampleRate*rate/sr;
      while(sustainSamplePos>=loopB) sustainSamplePos=loopA+(sustainSamplePos-loopB);
    }
    if (!drumSampleDone && m.drumSampleMix>0.001f && m.drumSample.length>1){
      float semis=(m.drumPitchFollow?midiNote-m.drumRootMidi:0)+m.transposeSemis;
      float rate=constrain(pow(2,semis/12.0f),0.25f,4);
      float posFrac=(float)(drumSamplePos/max(m.drumSample.length-1,1));
      float env=posFrac<0.002f?posFrac/0.002f:(posFrac>0.98f?max(0,(1-posFrac)/0.02f):1);
      direct+=sampleLinear(m.drumSample,drumSamplePos)*m.drumSampleMix*0.9f*env;
      drumSamplePos+=m.drumSampleRate*rate/sr;
      if(drumSamplePos>=m.drumSample.length-1) drumSampleDone=true;
    }
    return direct;
  }

  protected void uGenerate(float[] channels){
    float sr = sampleRate();
    if (done){ for (int i=0;i<channels.length;i++) channels[i]=0; return; }
    float a = ampAt(tSec);
    if (!legacyMode && m.glideMs>=6){
      float tau=max(0.004f,m.glideMs/1000.0f/3.0f);
      currentF0+=(targetF0-currentF0)*(1-(float)Math.exp(-1.0f/(tau*sr)));
    } else currentF0=targetF0;
    // ビブラート: 全幅 vibDepthCents → 偏差は ±vibDepthCents/2。onset で 0→1 にゲート
    float pitchMul = 1.0f;
    if (!legacyMode && m.vibDepthCents > 0.01f && m.vibRateHz > 0.001f){
      float vg = m.vibOnsetSec > 0.001f ? min(1, tSec/m.vibOnsetSec) : 1;
      pitchMul = pow(2, (m.vibDepthCents*0.5f*vg*lfoValue(m.vibShape,vibPhase))/1200.0f);
      vibPhase += TWO_PI * m.vibRateHz / sr; if (vibPhase >= TWO_PI) vibPhase -= TWO_PI;
    }
    float s = 0;
    for (int k=0;k<m.N;k++){
      float amp = m.harmAmp[k]; if (amp<=0) continue;
      int   n1  = m.harmN[k];
      float f   = currentF0 * m.harmRatio[k] * sqrt(1 + m.inharmB*n1*n1) * pitchMul;
      if (f >= sr*0.5f) continue;
      phase[k] += TWO_PI * f / sr;
      if (phase[k] >= TWO_PI) phase[k] -= TWO_PI;
      float harmonicEnvelope = (!legacyMode && enableDynamicHarmonics && m.useHarmonicEnvelope) ? harmEnvAt(k, tSec) : 1.0f;
      float main = sin(phase[k]);
      if (!legacyMode && m.brassMix>0.001f){
        float sign=(n1%2==0)?-0.72f:1.0f;
        float cents=m.brassDetuneCents*sign*(0.82f+min(n1,12)*0.018f);
        float layerF=f*pow(2,cents/1200.0f);
        layerPhase[k]+=TWO_PI*layerF/sr; if(layerPhase[k]>=TWO_PI) layerPhase[k]-=TWO_PI;
        float layerTone=0.5f+min(n1,14)*0.035f;
        main=main*(1-m.brassMix*0.16f)+sin(layerPhase[k])*m.brassMix*layerTone;
      }
      s += amp * harmonicEnvelope * main;
    }
    s *= m.harmNorm;
    if (!legacyMode && m.waveMix>0.001f && m.waveCycle.length>=8){
      float wave=sampleCycle(m.waveCycle,wavePhase);
      wavePhase += currentF0*pitchMul/sr; if(wavePhase>=1) wavePhase-=floor(wavePhase);
      s=s*(1-m.waveMix*0.28f)+wave*m.waveMix*0.34f;
    }
    if (!legacyMode && enableInstrumentNoise && m.useNoise && m.noiseTable.length > 1){
      float relMul = releasing ? max(0, 1-(tSec-releaseStartT)/relSec()) : 1;
      float recorded=noiseShapeAt(tSec)*m.noiseLevel;
      float attackBoost=tSec<0.12f ? 1+m.attackNoise*(1-tSec/0.12f) : 1;
      float breath=(tSec<0.03f?tSec/0.03f:1)*m.breathAmount*0.24f;
      float ne = (recorded*attackBoost+breath) * relMul;
      float noise=noiseHp.process(m.noiseTable[(int)noisePos]); noise=noiseLp.process(noise);
      s += noise * ne;
      noisePos += 1; if (noisePos >= m.noiseTable.length) noisePos -= m.noiseTable.length;
    }
    // トレモロ: 1-tremDepth .. 1 で振幅を周期変調
    if (!legacyMode && m.tremDepth > 0.001f && m.tremRateHz > 0.001f){
      s *= 1.0f - m.tremDepth*0.5f + m.tremDepth*0.5f*lfoValue(m.tremShape,tremPhase);
      tremPhase += TWO_PI * m.tremRateHz / sr; if (tremPhase >= TWO_PI) tremPhase -= TWO_PI;
    }
    s *= a * gain * 0.9f;
    s += sampleLayers(sr,pitchMul)*gain;
    boolean studioFxOn=!legacyMode && enableInstrumentFx && m.useBodyFx;
    if (studioFxOn) s = bodyFx.process(s);
    stereoFx.write(s,channels,studioFxOn);
    for(int c=0;c<channels.length;c++) channels[c]*=m.masterVolume; // ブラウザ版と同じFX後段のマスターGain
    tSec += 1.0f/sr;
    boolean sampleActive=(!attackSampleDone && m.attackSampleMix>0.001f) || (!drumSampleDone && m.drumSampleMix>0.001f);
    boolean bodyEnded=(releasing && (tSec-releaseStartT)>=relSec()) || (!releasing && a<=1e-4f && tSec>0.15f);
    if(bodyEnded && !sampleActive && silentSince<0) silentSince=tSec;
    if(silentSince>=0 && tSec-silentSince>=stereoFx.tailSec(studioFxOn)) done=true;
  }
}

/* スタジオの直列 FX: drive → body_eq / trumpet_resonance → filter。 */
class BodyToneFx {
  InstrModel m;
  BiquadMono driveTone, lowShelf, midBody, presence, highShelf, tubeBody, bell, air, toneFilter;
  float filterPhase=0; int filterUpdate=0;

  BodyToneFx(InstrModel m){
    this.m=m;
    float sr = m.synthSampleRate;
    driveTone= new BiquadMono(); driveTone.setLowPass(sr,m.driveToneHz,0.4f);
    lowShelf = new BiquadMono(); lowShelf.setLowShelf(sr, 160, m.eqLowGain);
    midBody  = new BiquadMono(); midBody.setPeak(sr, m.eqMidFreq, m.eqMidQ, m.eqMidGain);
    presence = new BiquadMono(); presence.setPeak(sr, 3800, 1.2f, m.eqPresenceGain);
    highShelf= new BiquadMono(); highShelf.setHighShelf(sr, 8000, m.eqHighGain);
    tubeBody = new BiquadMono(); tubeBody.setPeak(sr, 980, 1.1f, m.trumpetResonance * 1.7f);
    bell     = new BiquadMono(); bell.setPeak(sr, 3200, 1.0f, m.trumpetResonance * 3.0f);
    air      = new BiquadMono(); air.setPeak(sr, 7200, 0.85f, m.trumpetResonance * 0.75f);
    toneFilter=new BiquadMono(); updateToneFilter();
  }

  float process(float x){
    if (m.driveAmount>0.001f){
      float k=1+m.driveAmount*28, norm=(float)Math.tanh(k);
      x=(float)Math.tanh(k*x)/max(norm,1e-6f)/(1+m.driveAmount*1.4f);
    }
    x=driveTone.process(x);
    x=lowShelf.process(x); x=midBody.process(x); x=presence.process(x); x=highShelf.process(x);
    x=tubeBody.process(x); x=bell.process(x); x=air.process(x);
    if (!m.filterMode.equals("off")){
      if ((filterUpdate++ & 63)==0) updateToneFilter();
      x=toneFilter.process(x);
      filterPhase+=TWO_PI*m.filterLfoRateHz/m.synthSampleRate;
      if(filterPhase>=TWO_PI) filterPhase-=TWO_PI;
    }
    return x;
  }
  void updateToneFilter(){
    float sr=m.synthSampleRate;
    if (m.filterMode.equals("off")){ toneFilter.bypass=true; return; }
    float swing=m.filterLfoDepth*min(m.filterCutoffHz*0.9f,6000);
    float cutoff=constrain(m.filterCutoffHz+swing*sin(filterPhase),30,sr*0.45f);
    if (m.filterMode.equals("hp")) toneFilter.setHighPass(sr,cutoff,m.filterQ);
    else if (m.filterMode.equals("bp")) toneFilter.setBandPass(sr,cutoff,m.filterQ);
    else toneFilter.setLowPass(sr,cutoff,m.filterQ);
  }
}

/* 3 本の可変遅延コーラス + Schroeder 型リバーブ。 */
class StudioStereoFx {
  InstrModel m; float[] delay; int writePos=0; float[] lfo={0,0,0};
  final float[] BASE={0.013f,0.019f,0.026f};
  SimpleStereoReverb reverb;
  StudioStereoFx(InstrModel m){
    this.m=m; delay=new float[max(8,ceil(m.synthSampleRate*0.08f)+2)];
    reverb=m.reverbMix>0.001f ? new SimpleStereoReverb(m) : null;
  }
  void write(float dry,float[] channels,boolean enabled){
    float wetL=0,wetR=0;
    if(enabled && m.chorusMix>0.001f){
      delay[writePos]=dry;
      for(int i=0;i<3;i++){
        float rate=m.chorusRateHz*(0.8f+i*0.2f);
        float delaySec=BASE[i]+sin(lfo[i])*m.chorusDepth*0.005f;
        float tap=readDelay(delaySec*m.synthSampleRate);
        float pan=(i-1)*m.chorusWidth;
        wetL+=tap*sqrt((1-pan)*0.5f); wetR+=tap*sqrt((1+pan)*0.5f);
        lfo[i]+=TWO_PI*rate/m.synthSampleRate; if(lfo[i]>=TWO_PI) lfo[i]-=TWO_PI;
      }
      writePos++; if(writePos>=delay.length) writePos=0;
    }
    float send=m.chorusMix*0.6f/3.0f;
    float left=dry+wetL*send, right=dry+wetR*send;
    if(enabled && reverb!=null){
      reverb.process(dry);
      left+=reverb.outL*m.reverbMix*1.4f; right+=reverb.outR*m.reverbMix*1.4f;
    }
    if(channels.length==1) channels[0]=(left+right)*0.5f;
    else{
      channels[0]=left; channels[1]=right;
      for(int c=2;c<channels.length;c++) channels[c]=dry;
    }
  }
  float tailSec(boolean enabled){ return (enabled && m.reverbMix>0.001f) ? m.reverbPreMs/1000.0f+m.reverbSizeSec*1.1f : 0.03f; }
  float readDelay(float samples){
    float p=writePos-samples; while(p<0)p+=delay.length;
    int i0=(int)p, i1=(i0+1)%delay.length; float f=p-i0;
    return delay[i0]+(delay[i1]-delay[i0])*f;
  }
}

class SimpleStereoReverb {
  InstrModel m;
  float[] pre; int prePos=0, preDelaySamples;
  ReverbComb[] left=new ReverbComb[4], right=new ReverbComb[4];
  float outL,outR;
  SimpleStereoReverb(InstrModel m){
    this.m=m;
    pre=new float[max(2,ceil(m.synthSampleRate*0.181f)+2)];
    preDelaySamples=constrain(round(m.reverbPreMs*0.001f*m.synthSampleRate),0,pre.length-1);
    float[] baseL={0.0297f,0.0371f,0.0411f,0.0437f};
    float[] baseR={0.0307f,0.0329f,0.0393f,0.0449f};
    for(int i=0;i<4;i++){
      left[i]=new ReverbComb(m.synthSampleRate,baseL[i],m.reverbSizeSec,m.reverbDamping);
      right[i]=new ReverbComb(m.synthSampleRate,baseR[i],m.reverbSizeSec,m.reverbDamping);
    }
  }
  void process(float input){
    pre[prePos]=input;
    int read=prePos-preDelaySamples; if(read<0) read+=pre.length;
    float x=pre[read]; prePos++; if(prePos>=pre.length) prePos=0;
    float l=0,r=0;
    for(int i=0;i<4;i++){ l+=left[i].process(x); r+=right[i].process(x); }
    l*=0.25f; r*=0.25f;
    float mid=(l+r)*0.5f, side=(l-r)*0.5f*m.reverbWidth;
    outL=mid+side; outR=mid-side;
  }
}

class ReverbComb {
  float[] buf; int pos=0; float feedback,damping,last=0;
  ReverbComb(float sr,float delaySec,float rt60,float damping){
    buf=new float[max(2,round(sr*delaySec))];
    feedback=pow(0.001f,delaySec/max(rt60,0.1f));
    this.damping=damping;
  }
  float process(float x){
    float y=buf[pos];
    last+= (1-damping)*(y-last);
    buf[pos]=x+last*feedback;
    pos++; if(pos>=buf.length) pos=0;
    return y;
  }
}

class BiquadMono {
  float b0=1, b1=0, b2=0, a1=0, a2=0, z1=0, z2=0;
  boolean bypass=true;

  float process(float x){
    if (bypass) return x;
    float y=b0*x+z1; z1=b1*x-a1*y+z2; z2=b2*x-a2*y; return y;
  }
  void setPeak(float sr, float freq, float q, float gainDb){
    if (abs(gainDb)<0.001f){ bypass=true; return; }
    float f=constrain(freq,20,sr*0.45f), A=pow(10,gainDb/40.0f);
    float w=TWO_PI*f/sr, c=cos(w), alpha=sin(w)/(2*max(q,0.1f));
    setCoefficients(1+alpha*A,-2*c,1-alpha*A,1+alpha/A,-2*c,1-alpha/A);
  }
  void setLowPass(float sr,float freq,float q){
    float f=constrain(freq,20,sr*0.45f), w=TWO_PI*f/sr, c=cos(w), alpha=sin(w)/(2*max(q,0.1f));
    setCoefficients((1-c)*0.5f,1-c,(1-c)*0.5f,1+alpha,-2*c,1-alpha);
  }
  void setHighPass(float sr,float freq,float q){
    float f=constrain(freq,20,sr*0.45f), w=TWO_PI*f/sr, c=cos(w), alpha=sin(w)/(2*max(q,0.1f));
    setCoefficients((1+c)*0.5f,-(1+c),(1+c)*0.5f,1+alpha,-2*c,1-alpha);
  }
  void setBandPass(float sr,float freq,float q){
    float f=constrain(freq,20,sr*0.45f), w=TWO_PI*f/sr, c=cos(w), alpha=sin(w)/(2*max(q,0.1f));
    setCoefficients(alpha,0,-alpha,1+alpha,-2*c,1-alpha);
  }
  void setLowShelf(float sr, float freq, float gainDb){
    if (abs(gainDb)<0.001f){ bypass=true; return; }
    float f=constrain(freq,20,sr*0.45f), A=pow(10,gainDb/40.0f);
    float w=TWO_PI*f/sr, c=cos(w), alpha=sin(w)*sqrt(2)/2, beta=2*sqrt(A)*alpha;
    setCoefficients(A*((A+1)-(A-1)*c+beta),2*A*((A-1)-(A+1)*c),A*((A+1)-(A-1)*c-beta),
                    (A+1)+(A-1)*c+beta,-2*((A-1)+(A+1)*c),(A+1)+(A-1)*c-beta);
  }
  void setHighShelf(float sr, float freq, float gainDb){
    if (abs(gainDb)<0.001f){ bypass=true; return; }
    float f=constrain(freq,20,sr*0.45f), A=pow(10,gainDb/40.0f);
    float w=TWO_PI*f/sr, c=cos(w), alpha=sin(w)*sqrt(2)/2, beta=2*sqrt(A)*alpha;
    setCoefficients(A*((A+1)+(A-1)*c+beta),-2*A*((A-1)+(A+1)*c),A*((A+1)+(A-1)*c-beta),
                    (A+1)-(A-1)*c+beta,2*((A-1)-(A+1)*c),(A+1)-(A-1)*c-beta);
  }
  void setCoefficients(float nb0,float nb1,float nb2,float na0,float na1,float na2){
    if (abs(na0)<1e-9f){ bypass=true; return; }
    b0=nb0/na0; b1=nb1/na0; b2=nb2/na0; a1=na1/na0; a2=na2/na0; bypass=false;
  }
}
