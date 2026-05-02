// Arduino オーケストラ — 楽器ノードからの NOTE パケットを受けて音を鳴らす
// 仕様準拠: magic=0x4F52 でフレーム同期 → 20 B 固定 → type=3 (NOTE) を再生
//
// 動作:
//   - 起動時に Serial ポート一覧を表示し、SERIAL_PORT_INDEX 番のポートを開く
//   - magic (0x52 0x4F リトルエンディアン) を待ち、20 B たまったら 1 パケットとして処理
//   - NoteOn (gate=1) で発音、NoteOff (gate=0) または durationMs 経過で消音
//
// 使い方:
//   1. 楽器ノード (UNO R4 WiFi) を Mac に USB 接続
//   2. このスケッチを Run
//   3. コンソールに表示される Serial ポート一覧を見て、UNO R4 のポート番号を
//      SERIAL_PORT_INDEX に設定して再起動
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

// ─── 表示用 ────────────────────────────────────────
String  lastEventLabel = "(no events yet)";
int     receivedCount = 0;
int     lastBpmQ8 = 0;
int     lastConductorState = 0;
int     lastBeatNo = 0;

void setup() {
    size(720, 320);
    minim = new Minim(this);
    out = minim.getLineOut(Minim.STEREO, 1024, 44100);

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
    fill(60, 200, 120);
    rect(0, 0, width, 4);

    fill(220);
    textSize(13);
    text("Orchestra Test Player", 16, 26);
    text("Connected: " + (port != null), 16, 50);
    text("Received packets: " + receivedCount, 16, 70);
    text("Last event: " + lastEventLabel, 16, 90);
    text("BPM (×8): " + lastBpmQ8 + " → " + nf(lastBpmQ8 / 8.0f, 0, 2), 16, 110);
    text("Conductor state: " + stateLabel(lastConductorState), 16, 130);
    text("Last beatNo: " + lastBeatNo, 16, 150);
    text("Active voices: " + activeVoices.size() +
         " (releasing: " + releasingVoices.size() + ")", 16, 170);

    // release 完了したボイスを unpatch して回収
    reapReleasingVoices();

    // 波形描画
    stroke(80, 220, 120);
    noFill();
    int wy = 240;
    for (int i = 0; i < out.bufferSize() - 1; i++) {
        line(i, wy - out.left.get(i) * 60, i + 1, wy - out.left.get(i + 1) * 60);
    }
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
        if (gate == 1) {
            triggerNoteOn(partId, noteNumber, velocity, durationMs);
            lastEventLabel = "NoteOn part=" + partId + " note=" + noteNumber +
                             " v=" + velocity + " dur=" + durationMs + "ms";
        } else {
            triggerNoteOff(partId, noteNumber);
            lastEventLabel = "NoteOff part=" + partId + " note=" + noteNumber;
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
    // firmware 側で NoteOff が落ちることがあるため、ここで保険をかける。
    silenceAllOnPart(partId);
    int k = voiceKey(partId, noteNumber);
    float freq = 440.0f * pow(2.0f, (noteNumber - 69) / 12.0f);
    float amp  = constrain(velocity / 127.0f, 0.0f, 1.0f) * 0.4f;
    Voice v = new Voice(freq, amp);
    v.attack();
    activeVoices.put(k, v);
}

void triggerNoteOff(int partId, int noteNumber) {
    int k = voiceKey(partId, noteNumber);
    Voice v = activeVoices.remove(k);
    if (v != null) {
        v.release();
        releasingVoices.add(v);
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
    boolean unpatched = false;

    Voice(float freq, float maxAmp) {
        this.maxAmp = maxAmp;
        this.osc = new Oscil(freq, 0, Waves.SINE);
        this.amp = new Line();
        this.amp.patch(osc.amplitude);
    }

    void attack() {
        amp.activate(0.01f, 0.0f, maxAmp);  // 10 ms で立ち上げ
        osc.patch(out);
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
