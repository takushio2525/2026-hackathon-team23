/* ==========================================================================
   OrcLogger — 構造化ログ出力 (AI デバッグ対応)
   共有タブ: 各スケッチから symlink で参照。

   フォーマット: [HH:MM:SS.mmm] [ノードID] [カテゴリ] メッセージ
   Processing の println() は processing-java --run で起動時に stdout に出る。
   ========================================================================== */

// ── ログカテゴリ定数 ─────────────────────────────────────
final String LOG_NOTE   = "NOTE";
final String LOG_UI     = "UI";
final String LOG_SERIAL = "SERIAL";
final String LOG_AUDIO  = "AUDIO";
final String LOG_STATE  = "STATE";
final String LOG_ERROR  = "ERROR";
final String LOG_SYSTEM = "SYSTEM";
final String LOG_METRO  = "METRO";

// ── ログリングバッファ (画面表示用) ──────────────────────
ArrayList<String> logBuffer = new ArrayList<String>();
int LOG_BUFFER_MAX = 200;

String logTimestamp(){
  int ms = millis();
  int sec = (ms / 1000) % 60;
  int min = (ms / 60000) % 60;
  int hr  = (ms / 3600000) % 24;
  return nf(hr,2) + ":" + nf(min,2) + ":" + nf(sec,2) + "." + nf(ms % 1000, 3);
}

void orcLog(String nodeId, String category, String message){
  String line = "[" + logTimestamp() + "] [" + nodeId + "] [" + category + "] " + message;
  println(line);
  logBuffer.add(line);
  while (logBuffer.size() > LOG_BUFFER_MAX) logBuffer.remove(0);
}

void orcLogSystem(String message){
  orcLog("SYS", LOG_SYSTEM, message);
}

void orcLogNote(int partId, int noteNumber, int velocity, int durationMs, int instrumentId){
  String nodeId = "N" + nf(partId, 2);
  String instrLabel = isDrumInstrument(instrumentId) ? "drum" : "brass";
  orcLog(nodeId, LOG_NOTE, noteName(noteNumber) + " vel=" + velocity
         + " dur=" + durationMs + "ms instr=" + instrumentId + "(" + instrLabel + ")");
}

void orcLogUi(int state, int mode, int targetBpm, int score, int bpmQ8){
  float bpm = bpmQ8 / 8.0f;
  String scoreStr = (score == 0xFF) ? "---" : "" + score;
  orcLog("CTRL", LOG_UI, "state=" + stateName(state) + " mode=" + mode
         + " bpm=" + nf(bpm,1,1) + " target=" + targetBpm + " score=" + scoreStr);
}

void orcLogSerial(String portName, String message){
  orcLog("SER", LOG_SERIAL, "[" + portName + "] " + message);
}

void orcLogError(String nodeId, String message){
  orcLog(nodeId, LOG_ERROR, message);
}

// ── ログパネル描画 ───────────────────────────────────────
void drawLogPanel(float x, float y, float w, float h, int maxLines){
  drawPanel(x, y, w, h);
  fill(18, 54, 88); textSize(12); textAlign(LEFT, BASELINE);
  text("ログ (" + logBuffer.size() + " 行)", x + 14, y + 16);

  clip(x + 4, y + 22, w - 8, h - 26);
  textSize(10);
  float ly = y + 34;
  int startIdx = max(0, logBuffer.size() - maxLines);
  for (int i = startIdx; i < logBuffer.size(); i++){
    String line = logBuffer.get(i);
    if (line.contains("[ERROR]")) fill(220, 60, 60);
    else if (line.contains("[NOTE]")) fill(24, 100, 180);
    else if (line.contains("[UI]")) fill(24, 140, 80);
    else fill(60, 70, 85);
    text(line, x + 10, ly);
    ly += 13;
    if (ly > y + h - 4) break;
  }
  noClip();
}
