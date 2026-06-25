/* ==========================================================================
   OrcProtocol — 共通プロトコル定数・パケットパース・データクラス
   pc_app/common/ に置き、各スケッチから symlink で参照する共有タブ。
   ========================================================================== */

// ── プロトコル定数 ────────────────────────────────────────
final int  SERIAL_BAUD   = 115200;
final int  PACKET_SIZE   = 20;
final byte MAGIC_LO      = (byte) 0x52;
final byte MAGIC_HI      = (byte) 0x4F;
final int  TYPE_CTRL     = 1;
final int  TYPE_BEAT     = 2;
final int  TYPE_NOTE     = 3;
final int  TYPE_UI       = 4;

// ── 指揮者の状態 (OrcProtocol.h と整合) ──────────────────
final int ST_IDLE        = 0;
final int ST_CALIBRATING = 1;
final int ST_CONDUCTING  = 2;
final int ST_FALLBACK    = 3;
final int ST_MENU        = 4;
final int ST_RESULT      = 5;

String stateName(int st){
  switch(st){
    case ST_IDLE:        return "Idle";
    case ST_CALIBRATING: return "Calibrating";
    case ST_CONDUCTING:  return "Conducting";
    case ST_FALLBACK:    return "Fallback";
    case ST_MENU:        return "Menu";
    case ST_RESULT:      return "Result";
    default:             return "Unknown(" + st + ")";
  }
}

// ── 役割 ──────────────────────────────────────────────────
final int ROLE_UNKNOWN  = 0;
final int ROLE_MAIN_UI  = 1;
final int ROLE_ANALYZER = 2;

// ── 画面 ID ──────────────────────────────────────────────
final int SCR_PORT_SELECT = 0;
final int SCR_WAITING     = 1;
final int SCR_MENU        = 2;
final int SCR_FREE_PLAY   = 3;
final int SCR_GAME_PLAY   = 4;
final int SCR_RESULT      = 5;
final int SCR_ANALYZER    = 6;
final int SCR_DASHBOARD   = 7;  // test_multi 用

// ── ゲーム定数 (firmware ProjectConfig.h と整合) ─────────
final int GAME_LENGTH_BEATS      = 56;
final int GAME_GUIDE_FULL_BEATS  = 16;
final int GAME_GUIDE_ZERO_BEATS  = 32;
final int UI_TIMEOUT_MS          = 2000;

// ── メニュー ─────────────────────────────────────────────
final String[] MENU_ITEMS = { "自由演奏", "ゲーム" };
final String[] MENU_DESCS = { "振ったテンポで輪唱", "目標テンポ維持を採点" };

// ── ノート名 ─────────────────────────────────────────────
final String[] NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
String noteName(int midi){ return NOTE_NAMES[((midi%12)+12)%12] + (midi/12 - 1); }

// ── バイト解釈 ───────────────────────────────────────────
int u8(byte v){ return v & 0xFF; }
int u16le(byte lo, byte hi){ return u8(lo) | (u8(hi) << 8); }

// ── パース済みパケットデータ ─────────────────────────────
class NoteEvent {
  int partId, noteNumber, velocity, gate, durationMs, instrumentId;
  NoteEvent(byte[] buf){
    partId       = u8(buf[12]);
    noteNumber   = u8(buf[13]);
    velocity     = u8(buf[14]);
    gate         = u8(buf[15]);
    durationMs   = u16le(buf[16], buf[17]);
    instrumentId = u8(buf[18]);
  }
}

class UiEvent {
  int state, mode, navCursor, targetBpm, score, partId, bpmQ8;
  UiEvent(byte[] buf){
    state     = u8(buf[12]);
    mode      = u8(buf[13]);
    navCursor = u8(buf[14]);
    targetBpm = u8(buf[15]);
    score     = u8(buf[16]);
    partId    = u8(buf[17]);
    bpmQ8     = u16le(buf[18], buf[19]);
  }
}

int packetType(byte[] buf){
  if (buf.length < PACKET_SIZE) return -1;
  if (u8(buf[2]) != 0x01) return -1;
  return u8(buf[3]);
}
