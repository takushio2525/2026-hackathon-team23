// Arduino オーケストラ — 楽器ノードからの NOTE パケットを受けて音を鳴らす
// 仕様準拠: magic=0x4F52 でフレーム同期 → 20 B 固定 → type=3 (NOTE) を再生
//
// 2 つのモードを持つ。起動時は SERIAL モード (本番動作):
//   SERIAL : 楽器ノード (UNO R4 WiFi) からのバイナリ NotePacket を再生する (デフォルト)
//   LOOP   : 内蔵メロディ「ドレミファミレド」を BPM 120 で自動再生する (ハード不要のオフライン確認用)
//   キー 'l' で LOOP、's' で SERIAL に切替
//
// SERIAL モードの動作:
//   - 起動時に Serial ポート一覧を表示し、SERIAL_PORT_NAME のポートを開く
//   - magic (0x52 0x4F リトルエンディアン) を待ち、20 B たまったら 1 パケットとして処理
//   - NoteOn (gate=1) パケット 1 個に「音の高さ + 長さ (durationMs)」が乗っており、
//     attack して durationMs 経過後に scheduleAutoRelease() が自動消音する
//   - 同じパートで次の NoteOn が来たらモノフォニックで前の音を即時 release
//   - NoteOff (gate=0) パケットは仕様上 node_02 から送られないが、来た場合の互換
//     パスとして triggerNoteOff() は残す
//
// 仕様書: meetings/0429_3回/事前課題共有/arduino_塩澤.pdf §2.3.3.5

import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import java.util.Iterator;
import java.util.Map;

// ─── 設定 ──────────────────────────────────────────
// 楽器ノード (UNO R4 WiFi) の USB シリアルポート名を直接指定する。
// Mac で `ls /dev/cu.*` するか、起動時にコンソールへ出る一覧で確認できる。
// SERIAL_PORT_NAME が空文字 ("") のときだけ SERIAL_PORT_INDEX にフォールバック。
final String SERIAL_PORT_NAME  = "/dev/cu.usbmodem34B7DA64482C2";
final int    SERIAL_PORT_INDEX = 0;     // フォールバック用 (Serial.list() のインデックス)
final int    SERIAL_BAUD       = 115200;

// ─── パケット仕様 ────────────────────────────────────
final int  PACKET_SIZE = 20;
final byte MAGIC_LO    = (byte) 0x52;  // 'R'
final byte MAGIC_HI    = (byte) 0x4F;  // 'O'
final int  TYPE_CTRL = 1;
final int  TYPE_BEAT = 2;
final int  TYPE_NOTE = 3;

// ─── 受信状態 ──────────────────────────────────────
Serial port;
byte[]  rxBuf = new byte[PACKET_SIZE];
int     rxIdx = 0;
boolean inFrame = false;

// ─── オーディオ ────────────────────────────────────
Minim       minim;
AudioOutput out;
HashMap<Integer, Voice> activeVoices = new HashMap<Integer, Voice>();
// release 中で unpatch 待ちのボイス。draw() から完了したものを回収する
ArrayList<Voice> releasingVoices = new ArrayList<Voice>();
final float RELEASE_SEC = 0.06f;

// ─── ループ再生モード ──────────────────────────────
//   起動時のデフォルトは SERIAL (UNO からの NotePacket を発音する本番動作)。
//   LOOP はハードなしで音出しを確認したいときに 'l' で明示的に入る確認用モード。
final int  MODE_LOOP   = 0;
final int  MODE_SERIAL = 1;
int        currentMode = MODE_SERIAL;

// 内蔵メロディ (firmware/test/node_02/src/score_data.cpp の冒頭と同じ「ドレミファミレド」)
// LOOP_PART_ID は LOOP モードでだけ使う Voice 鍵の一部。SERIAL モードでは
// 受信した NotePacket の partId をそのまま使うので、Mac に繋いでいる楽器ノードが
// node_02 (0x02) / node_03 (0x03) / node_04 (0x04) のいずれでもそのまま動く。
// LOOP モードのオフライン再生で使う partId を変えたい場合だけここを書き換える。
final int[] LOOP_MELODY    = { 60, 62, 64, 65, 64, 62, 60 };
final int   LOOP_BPM       = 120;
final int   LOOP_PART_ID   = 0x02;
final int   LOOP_VELOCITY  = 100;
int         loopIdx        = 0;
int         loopNextOnAtMs = 0;

// ─── 表示用 ────────────────────────────────────────
String  lastEventLabel = "(no events yet)";
int     receivedCount = 0;
int     lastBpmQ8 = 0;
int     lastConductorState = 0;
int     lastBeatNo = 0;
int     lastPartId = -1;   // 直近に受けた NotePacket の partId (未受信は -1)

void setup() {
    size(720, 340);
    minim = new Minim(this);
    out = minim.getLineOut(Minim.STEREO, 1024, 44100);

    println("=== Orchestra Test Player ===");
    println("Mode: SERIAL (press 'l' to switch to LOOP for offline test, 's' to come back)");
    println("");
    println("Available serial ports:");
    String[] ports = Serial.list();
    for (int i = 0; i < ports.length; i++) {
        println("  [" + i + "] " + ports[i]);
    }
    if (ports.length == 0) {
        println("(!) No serial ports detected. Plug in the instrument node and restart.");
        return;
    }
    // 1) SERIAL_PORT_NAME に一致するポートを最優先で選ぶ
    String chosen = null;
    if (SERIAL_PORT_NAME != null && SERIAL_PORT_NAME.length() > 0) {
        for (String p : ports) {
            if (p.equals(SERIAL_PORT_NAME)) { chosen = p; break; }
        }
        if (chosen == null) {
            println("(!) SERIAL_PORT_NAME '" + SERIAL_PORT_NAME +
                    "' が見つかりません。SERIAL_PORT_INDEX にフォールバックします。");
        }
    }
    // 2) 見つからなければ SERIAL_PORT_INDEX を使う
    if (chosen == null) {
        int idx = constrain(SERIAL_PORT_INDEX, 0, ports.length - 1);
        chosen = ports[idx];
    }
    println("Opening: " + chosen);
    try {
        port = new Serial(this, chosen, SERIAL_BAUD);
        port.buffer(1);
    } catch (Exception e) {
        println("(!) Failed to open serial port: " + e.getMessage());
        port = null;
    }
}

void draw() {
    background(20);
    noStroke();
    fill(currentMode == MODE_LOOP ? color(220, 160, 60) : color(60, 200, 120));
    rect(0, 0, width, 4);

    // ループ再生は draw() の cadence で進める
    updateLoopPlayback();

    fill(220);
    textSize(13);
    text("Orchestra Test Player", 16, 26);
    text("Mode: " + (currentMode == MODE_LOOP ? "LOOP (BPM " + LOOP_BPM + ")" : "SERIAL")
         + "   [l]=LOOP  [s]=SERIAL", 16, 46);
    text("Connected: " + (port != null), 16, 70);
    text("Received packets: " + receivedCount, 16, 90);
    text("Last event: " + lastEventLabel, 16, 110);
    text("BPM (×8): " + lastBpmQ8 + " → " + nf(lastBpmQ8 / 8.0f, 0, 2), 16, 130);
    text("Conductor state: " + stateLabel(lastConductorState), 16, 150);
    text("Last beatNo: " + lastBeatNo, 16, 170);
    text("Last partId: " + (lastPartId < 0 ? "(none)" :
         "0x" + hex(lastPartId, 2)), 16, 190);
    text("Active voices: " + activeVoices.size() +
         " (releasing: " + releasingVoices.size() + ")", 16, 210);

    // durationMs 到達した Voice を release に移し、release 完了したものを unpatch
    scheduleAutoRelease();
    reapReleasingVoices();

    // 波形描画
    stroke(80, 220, 120);
    noFill();
    int wy = 260;
    for (int i = 0; i < out.bufferSize() - 1; i++) {
        line(i, wy - out.left.get(i) * 60, i + 1, wy - out.left.get(i + 1) * 60);
    }
}

void keyPressed() {
    if (key == 'l' || key == 'L') {
        switchMode(MODE_LOOP);
    } else if (key == 's' || key == 'S') {
        switchMode(MODE_SERIAL);
    }
}

void switchMode(int mode) {
    if (mode == currentMode) return;
    currentMode = mode;
    // 切替時は鳴っている音を全部止める
    silenceAllParts();
    if (mode == MODE_LOOP) {
        loopIdx = 0;
        loopNextOnAtMs = millis();  // すぐ最初の音を鳴らす
        println("[MODE] -> LOOP");
    } else {
        println("[MODE] -> SERIAL");
    }
}

// LOOP モード: BPM 120 で 1 拍ごとに次の音を鳴らす。
// モノフォニックなので triggerNoteOn が前の音を自動的に止める。
void updateLoopPlayback() {
    if (currentMode != MODE_LOOP) return;
    int nowMs = millis();
    if (nowMs < loopNextOnAtMs) return;
    int note = LOOP_MELODY[loopIdx];
    int beatPeriodMs = (int)(60000.0f / LOOP_BPM);
    triggerNoteOn(LOOP_PART_ID, note, LOOP_VELOCITY, beatPeriodMs);
    lastEventLabel = "LOOP NoteOn note=" + note + " (idx=" + loopIdx + "/" + LOOP_MELODY.length + ")";
    loopIdx = (loopIdx + 1) % LOOP_MELODY.length;
    loopNextOnAtMs = nowMs + beatPeriodMs;
}

String stateLabel(int s) {
    switch (s) {
        case 0: return "Idle";
        case 1: return "Calibrating";
        case 2: return "Conducting";
        case 3: return "Fallback";
        default: return "Unknown(" + s + ")";
    }
}

// ─── シリアル受信 ──────────────────────────────────
void serialEvent(Serial p) {
    while (p.available() > 0) {
        int b = p.read();
        if (!inFrame) {
            // magic 同期: 0x52 ('R'), 0x4F ('O') の順
            if (rxIdx == 0) {
                if ((byte) b == MAGIC_LO) {
                    rxBuf[0] = (byte) b;
                    rxIdx = 1;
                }
            } else if (rxIdx == 1) {
                if ((byte) b == MAGIC_HI) {
                    rxBuf[1] = (byte) b;
                    rxIdx = 2;
                    inFrame = true;
                } else {
                    // 同期外れ。再試行
                    rxIdx = ((byte) b == MAGIC_LO) ? 1 : 0;
                    if (rxIdx == 1) rxBuf[0] = (byte) b;
                }
            }
        } else {
            rxBuf[rxIdx++] = (byte) b;
            if (rxIdx >= PACKET_SIZE) {
                handlePacket(rxBuf);
                rxIdx = 0;
                inFrame = false;
            }
        }
    }
}

// ─── パケット処理 ──────────────────────────────────
int u8(byte v)              { return v & 0xFF; }
int u16le(byte lo, byte hi) { return u8(lo) | (u8(hi) << 8); }

void handlePacket(byte[] buf) {
    receivedCount++;
    int version = u8(buf[2]);
    int type    = u8(buf[3]);
    if (version != 0x01) return;

    if (type == TYPE_NOTE) {
        int partId     = u8(buf[12]);
        int noteNumber = u8(buf[13]);
        int velocity   = u8(buf[14]);
        int gate       = u8(buf[15]);
        int durationMs = u16le(buf[16], buf[17]);
        lastPartId = partId;   // どの楽器ノードから受けたか可視化 (1 対 1 構成でも有用)
        // LOOP モード中は受信した NoteOn を無視する。CTRL/BEAT は表示用に取り込む。
        if (currentMode == MODE_SERIAL) {
            if (gate == 1) {
                triggerNoteOn(partId, noteNumber, velocity, durationMs);
                lastEventLabel = "NoteOn part=0x" + hex(partId, 2) +
                                 " note=" + noteNumber +
                                 " v=" + velocity + " dur=" + durationMs + "ms";
            } else {
                triggerNoteOff(partId, noteNumber);
                lastEventLabel = "NoteOff part=0x" + hex(partId, 2) +
                                 " note=" + noteNumber;
            }
        }
    } else if (type == TYPE_CTRL) {
        // 楽器ノードの USB Serial には CTRL は通常流れないが、デバッグ用に対応
        lastBpmQ8         = u16le(buf[12], buf[13]);
        lastConductorState = u8(buf[15]);
        lastEventLabel    = "CTRL bpmQ8=" + lastBpmQ8;
    } else if (type == TYPE_BEAT) {
        lastBeatNo     = u16le(buf[12], buf[13]);
        lastEventLabel = "BEAT beatNo=" + lastBeatNo;
    }
}

// ─── 発音管理 ──────────────────────────────────────
int voiceKey(int partId, int noteNumber) {
    return (partId << 8) | (noteNumber & 0xFF);
}

void triggerNoteOn(int partId, int noteNumber, int velocity, int durationMs) {
    // モノフォニック化: 同じパートで鳴っている音は note 番号に関係なく止める。
    silenceAllOnPart(partId);
    int k = voiceKey(partId, noteNumber);
    float freq = 440.0f * pow(2.0f, (noteNumber - 69) / 12.0f);
    float amp  = constrain(velocity / 127.0f, 0.0f, 1.0f) * 0.4f;
    Voice v = new Voice(freq, amp);
    v.attack(durationMs);   // durationMs 後に scheduleAutoRelease() が release を呼ぶ
    activeVoices.put(k, v);
}

// durationMs 経過した Voice を release に移行する。
// node_02 は NoteOff パケットを送らないため、消音はこちらが担当する。
void scheduleAutoRelease() {
    int nowMs = millis();
    Iterator<Map.Entry<Integer, Voice>> it = activeVoices.entrySet().iterator();
    while (it.hasNext()) {
        Map.Entry<Integer, Voice> e = it.next();
        Voice v = e.getValue();
        if (!v.releaseScheduled && nowMs >= v.noteOffAtMs) {
            v.release();
            v.releaseScheduled = true;
            releasingVoices.add(v);
            it.remove();
        }
    }
}

void triggerNoteOff(int partId, int noteNumber) {
    int k = voiceKey(partId, noteNumber);
    Voice v = activeVoices.remove(k);
    if (v != null) {
        v.release();
        releasingVoices.add(v);
    }
}

void silenceAllParts() {
    Iterator<Map.Entry<Integer, Voice>> it = activeVoices.entrySet().iterator();
    while (it.hasNext()) {
        Voice v = it.next().getValue();
        v.release();
        releasingVoices.add(v);
        it.remove();
    }
}

void silenceAllOnPart(int partId) {
    Iterator<Map.Entry<Integer, Voice>> it = activeVoices.entrySet().iterator();
    while (it.hasNext()) {
        Map.Entry<Integer, Voice> e = it.next();
        if ((e.getKey() >> 8) == partId) {
            Voice v = e.getValue();
            v.release();
            releasingVoices.add(v);
            it.remove();
        }
    }
}

void reapReleasingVoices() {
    int nowMs = millis();
    Iterator<Voice> it = releasingVoices.iterator();
    while (it.hasNext()) {
        Voice v = it.next();
        if (nowMs - v.releaseStartedAtMs >= (int)(RELEASE_SEC * 1000) + 5) {
            v.unpatchNow();
            it.remove();
        }
    }
}

// シンプルなサイン波 + 線形 ADSR ボイス
class Voice {
    Oscil osc;
    Line  amp;
    float maxAmp;
    int   releaseStartedAtMs = 0;
    int   noteOffAtMs = 0;       // attack 時にセット: この時刻になったら自動消音
    boolean releaseScheduled = false;
    boolean unpatched = false;

    Voice(float freq, float maxAmp) {
        this.maxAmp = maxAmp;
        this.osc = new Oscil(freq, 0, Waves.SINE);
        this.amp = new Line();
        this.amp.patch(osc.amplitude);
    }

    void attack(int durationMs) {
        amp.activate(0.01f, 0.0f, maxAmp);  // 10 ms で立ち上げ
        osc.patch(out);
        noteOffAtMs = millis() + durationMs;
    }

    void release() {
        // 振幅だけ落として patch は維持。実際の unpatch は reapReleasingVoices() で行う
        amp.activate(RELEASE_SEC, maxAmp, 0.0f);
        releaseStartedAtMs = millis();
    }

    void unpatchNow() {
        if (unpatched) return;
        osc.unpatch(out);
        unpatched = true;
    }
}
