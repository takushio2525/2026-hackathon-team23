/* ==========================================================================
   instrument_player — sound_lab で解析した音色定義(JSON)を読み込み、
   音程と長さを外から与えると「限りなく元に近い音」を鳴らす Processing スケッチ。

   合成方式: 倍音ごとに振幅・周波数比・時間エンベロープを持つ加算合成
             + 非調和性(f_n = n·f0·√(1+B·n²)) + スペクトル整形ノイズ + 全体振幅エンベロープ。
             全体エンベロープは要求発音長に合わせて「ループ区間を伸縮」して時間ワープする。

   必要ライブラリ: Minim (スケッチ → ライブラリをインポート → ライブラリを追加 → "Minim")

   音色の差し替え:
     data/ フォルダに置いた *.json をすべて自動で見つけ、起動後に画面の一覧をクリック
     (または '[' / ']' キー)で切り替えられる。'r' で data/ を再スキャン＋現在の音色を再読込。
     'o' で data/ 以外の場所にある JSON も選べる。
     何も置いていない場合は同梱の example_organ.json で起動する。

   操作:
     - 画面の鍵盤をクリック / PC キーボード(zsxdcvg… と q2w3e… の 2 列)で演奏
     - 上下矢印: オクターブ移動 / 左右矢印: 発音長 ±0.1s / スライダーをドラッグでも変更
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
ArrayList<ResynthVoice> voices = new ArrayList<ResynthVoice>();

// data/ 配下の *.json 一覧と、いま選んでいるインデックス
ArrayList<File> instrumentFiles = new ArrayList<File>();
int currentIdx = -1;
int listScroll = 0;               // 一覧が長いときの表示開始行

int   baseOctaveMidi = 48;        // 鍵盤左端の MIDI ノート(C3)
int   keyboardOctaves = 3;        // 表示するオクターブ数
float noteDurSec = 1.0;           // 発音長(スライダーで変更)
boolean useSimpleADSR = false;    // true なら値配列でなく A/D/S/R 4 値だけで包絡を作る
boolean draggingSlider = false;

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

// ── 演奏 ────────────────────────────────────────────────────
void playNote(int midiNote){
  if (model == null) return;
  ResynthVoice v = new ResynthVoice(model, midiNote, 1.0, noteDurSec, useSimpleADSR);
  v.patch(out);
  voices.add(v);
}
void stopAll(){
  for (ResynthVoice v : voices) v.unpatch(out);
  voices.clear();
}

// ── 描画ループ ──────────────────────────────────────────────
void draw(){
  // 終了したボイスを掃除
  for (Iterator<ResynthVoice> it = voices.iterator(); it.hasNext();){
    ResynthVoice v = it.next();
    if (v.done){ v.unpatch(out); it.remove(); }
  }
  drawBackground();
  drawHeader();
  drawVisualization();
  drawSlider();
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

void drawHeader(){
  glassPanel(20, 16, width-40, 64);
  fill(30,27,75); textSize(18);
  text("instrument_player", 34, 42);
  textSize(12); fill(99,102,241);
  text(loadedName, 34, 62);
  textAlign(RIGHT);
  text("発音長 " + nf(noteDurSec,0,2) + "s | 包絡 " + (useSimpleADSR ? "ADSR4値" : "実エンベロープ") +
       " | [ ]=音色切替  o=外部選択  r=再スキャン  a=包絡  矢印=音域/長さ  Space=停止", width-34, 52);
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
  fill(99,102,241); textSize(10); text("振幅エンベロープ", ex, ey-2);
  noFill(); stroke(129,140,248);
  float[] env = model.envValues; int n=env.length;
  // ループ区間ハイライト
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

// 発音長スライダー
float sliderX, sliderW, sliderY;
void drawSlider(){
  sliderX=20+14; sliderW=width-40-28; sliderY=92+120+22;
  glassPanel(20, 92+120+8, width-40, 30);
  stroke(99,102,241,120); strokeWeight(3); line(sliderX, sliderY, sliderX+sliderW, sliderY);
  float t=(noteDurSec-0.1f)/(4.0f-0.1f);
  float hx=sliderX + sliderW*t;
  noStroke(); fill(129,140,248); ellipse(hx, sliderY, 16,16);
  fill(30,27,75); textSize(11); textAlign(LEFT);
  text("発音長 (drag) : " + nf(noteDurSec,0,2) + " s", sliderX, sliderY-8);
  strokeWeight(1);
}

// ── インストゥルメント一覧 (data/*.json) ───────────────────
float listX, listY, listW, listH;            // 直近の描画範囲(クリック判定で使う)
void listGeom(){
  listX = 20; listY = 92+120+8+30+8;          // スライダーパネルの下
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
boolean isNoteOn(int midi){
  for (ResynthVoice v : voices){ if (v.midiNote==midi && !v.done && v.tSec < 0.18f) return true; }
  return false;
}

// ── マウス操作 ──────────────────────────────────────────────
void mousePressed(){
  // スライダー
  if (mouseY > sliderY-14 && mouseY < sliderY+14 && mouseX > sliderX-12 && mouseX < sliderX+sliderW+12){
    draggingSlider = true; updateSlider(); return;
  }
  // インストゥルメント一覧
  int li = instrumentRowAt(mouseX, mouseY);
  if (li >= 0){ loadByIndex(li); return; }
  // 鍵盤(黒鍵を先に判定)
  int m = keyAt(mouseX, mouseY);
  if (m >= 0) playNote(m);
}
void mouseDragged(){ if (draggingSlider) updateSlider(); }
void mouseReleased(){ draggingSlider = false; }
void updateSlider(){
  float t = constrain((mouseX - sliderX)/sliderW, 0, 1);
  noteDurSec = 0.1f + t*(4.0f-0.1f);
}
int keyAt(float mx, float my){
  if (my < kbY || my > kbY+kbH) return -1;
  // 黒鍵
  for (int i=0;i<whiteCount-1;i++){
    int pc = WHITE_PC[i%7];
    boolean hasSharp = (pc==0||pc==2||pc==5||pc==7||pc==9);
    if (!hasSharp) continue;
    float bx = kbX+(i+1)*whiteW - whiteW*0.30f, bw=whiteW*0.6f, bh=kbH*0.62f;
    if (mx>=bx && mx<=bx+bw && my<=kbY+bh) return whiteMidi(i)+1;
  }
  // 白鍵
  int i = (int)((mx-kbX)/whiteW);
  if (i<0 || i>=whiteCount) return -1;
  return whiteMidi(i);
}

// ── キーボード操作 ──────────────────────────────────────────
void keyPressed(){
  if (key==CODED){
    if (keyCode==UP)   baseOctaveMidi = min(96, baseOctaveMidi+12);
    if (keyCode==DOWN) baseOctaveMidi = max(12, baseOctaveMidi-12);
    if (keyCode==LEFT)  noteDurSec = max(0.1f, noteDurSec-0.1f);
    if (keyCode==RIGHT) noteDurSec = min(4.0f, noteDurSec+0.1f);
    return;
  }
  char c = Character.toLowerCase(key);
  if (c=='['){ cycleInstrument(-1); return; }
  if (c==']'){ cycleInstrument(1);  return; }
  if (c=='o'){ selectInput("data/ 以外の JSON を選択", "onJsonSelected"); return; }
  if (c=='r'){ rescanAndLoad(false); return; }     // data/ を再スキャンし、いまのファイルを読み直す
  if (c=='a'){ useSimpleADSR = !useSimpleADSR; return; }
  if (c==' '){ stopAll(); return; }
  Integer off = KEYMAP.get(c);
  if (off != null) playNote(baseOctaveMidi + off);
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
   ========================================================================== */
class ResynthVoice extends UGen {
  InstrModel m;
  int   midiNote;
  float targetF0;
  float gain;            // velocity 由来
  float durSec;          // 要求された発音長(リリース除く本体)
  boolean simpleADSR;

  float[] phase;         // 倍音ごとの位相
  double  noisePos;
  float   tSec = 0;      // 経過秒
  float   totalSec;      // これを超えたら done
  boolean done = false;

  // 時間ワープ用に展開した値
  float origDur, headT, bodyLen, loopLen, tailStart, tailLen;

  ResynthVoice(InstrModel model, int midiNote, float velocity, float durationSec, boolean simple){
    this.m = model; this.midiNote = midiNote;
    this.targetF0 = 440f * pow(2, (midiNote-69)/12.0f);
    this.gain = constrain(velocity, 0, 1);
    this.durSec = max(0.05f, durationSec);
    this.simpleADSR = simple;
    phase = new float[m.N];
    for (int i=0;i<m.N;i++) phase[i] = m.harmPhase[i];

    origDur   = m.origDurSec();
    loopLen   = max(m.loopEndSec - m.loopStartSec, 1e-3f);
    tailStart = max(origDur - m.releaseSec, m.loopEndSec);
    tailLen   = max(origDur - tailStart, 0);
    headT     = m.loopStartSec;
    if (m.sustaining && durSec > origDur){
      bodyLen  = max(durSec - headT - tailLen, 0);
      totalSec = headT + bodyLen + tailLen + 0.01f;
    } else if (!m.sustaining && durSec >= origDur){
      totalSec = origDur + 0.01f;          // 鳴らし切り
    } else {
      totalSec = durSec + 0.01f;           // 原音より短く切る(末尾は releaseFade で減衰)
    }
    if (simpleADSR) totalSec = max(totalSec, m.attackSec + m.decaySec + m.releaseSec + 0.01f);
  }
  // この音は「自然な終端より前で切られる」か(= 末尾にリリースフェードを足す必要があるか)
  boolean isCutShort(){
    return (m.sustaining && durSec <= origDur) || (!m.sustaining && durSec < origDur);
  }

  // ── 全体振幅エンベロープ(0..1) ── 要求発音長に時間ワープ
  float ampEnvAt(float t){
    if (simpleADSR) return adsrAt(t);
    float st = warpedTime(t);
    return sampleCurve(m.envValues, m.envRate, st) * releaseFade(t);
  }
  // 倍音 k の時間エンベロープ(0..1)
  float harmEnvAt(int k, float t){
    float[] he = m.harmEnv[k];
    float rate = (he.length-1)/max(origDur, 1e-3f);
    float st = warpedTime(t);
    return sampleCurve(he, rate, st);
  }
  float noiseEnvAt(float t){
    // ノイズ包絡も同じ時間ワープ(レートは JSON のまま)
    float st = warpedTime(t);
    return sampleCurve(m.noiseEnv, m.noiseEnvRate, st) * releaseFade(t);
  }
  // 経過秒 t → 原音時間 st(ループ伸縮込み)
  float warpedTime(float t){
    if (m.sustaining && durSec > origDur){
      if (t < headT) return t;
      if (t < headT + bodyLen){ float u = (t - headT) % loopLen; return m.loopStartSec + u; }
      return min(tailStart + (t - headT - bodyLen), origDur);
    }
    return min(t, origDur);   // 鳴らし切り / 短く切る場合は原音をそのまま辿る
  }
  // 自然終端より前で切る音は、末尾 releaseSec で 0 へ落としてクリックを防ぐ
  float releaseFade(float t){
    if (!isCutShort()) return 1;
    float r = max(m.releaseSec, 0.01f), fadeStart = durSec - r;
    return t <= fadeStart ? 1 : max(0, (durSec - t)/r);
  }
  // ADSR 4 値だけで包絡(useSimpleADSR 時)
  float adsrAt(float t){
    float a=m.attackSec, d=m.decaySec, s=m.sustainLevel, r=m.releaseSec;
    float sustainEnd = m.sustaining ? max(durSec, a+d) : a+d;  // 減衰音は実質 D で 0 へ
    if (t < a) return t/max(a,1e-4f);
    if (t < a+d){ float u=(t-a)/max(d,1e-4f); return lerp(1, s, u); }
    if (t < sustainEnd) return s;
    float u = (t - sustainEnd)/max(r,1e-4f);
    return max(0, lerp(s, 0, u));
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
    float a = ampEnvAt(tSec);
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
      float ne = noiseEnvAt(tSec) * m.noiseLevel;
      s += m.noiseTable[(int)noisePos] * ne;
      noisePos += 1; if (noisePos >= m.noiseTable.length) noisePos -= m.noiseTable.length;
    }
    s *= a * gain * 0.9f;
    for (int i=0;i<channels.length;i++) channels[i] = s;
    tSec += 1.0f/sr;
    if (tSec >= totalSec || (a <= 0 && tSec > 0.05f)) done = true;
  }
}
