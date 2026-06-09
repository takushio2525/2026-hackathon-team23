// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test_v3/node_04
//   pio run -d firmware/test_v3/node_04 -t upload
//   pio device monitor -d firmware/test_v3/node_04
//
// SERIAL_DEBUG=1 のときは Serial を「人間可読のデバッグ出力」専用に切替え、
// バイナリ NotePacket は流さない (Processing 連携を一時停止する代わりに
// pio device monitor で挙動を読めるようにする)。
// SERIAL_DEBUG=0 のときは従来どおり 20 B のバイナリ NotePacket を Serial に書く。

#include "NoteSenderModule.h"
#include "SystemData.h"
#include "OrcProtocol.h"
#include "SerialDebug.h"

bool NoteSenderModule::init() {
#if SERIAL_DEBUG
    // main.cpp 側で Serial.begin() / ホスト待機を済ませているので何もしない。
#else
    Serial.begin(cfg_.baudRate);
#endif
    return true;
}

namespace {

#if !SERIAL_DEBUG
void buildAndSend(uint8_t partId, uint8_t instrumentId, uint8_t gate,
                  uint32_t seq, uint32_t now, const NoteOutData& out) {
    orc::NotePacket pkt{};
    pkt.header.magic        = orc::MAGIC;
    pkt.header.version      = orc::PROTOCOL_VERSION;
    pkt.header.type         = orc::PKT_NOTE;
    pkt.header.seq          = seq;
    pkt.header.timestampMs  = now;
    pkt.payload.partId      = partId;
    pkt.payload.noteNumber  = out.noteNumber;
    pkt.payload.velocity    = out.velocity;
    pkt.payload.gate        = gate;
    pkt.payload.durationMs  = out.durationMs;
    pkt.payload.instrumentId = instrumentId;
    pkt.payload.reserved    = 0;
    Serial.write(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt));
    // UNO R4 WiFi の USB CDC は小さい書き込みを内部バッファで束ねるため、
    // flush() を呼んで即座にホスト (Processing) へ送り出す。
    // これがないとパケットがまとめて到着し、発音が「ためてバースト」状態になる。
    Serial.flush();
}
#endif

}  // namespace

void NoteSenderModule::updateOutput(SystemData& data) {
    const uint32_t now = millis();
    if (data.noteOut.pendingOn) {
        const uint32_t seq = ++data.noteSender.noteSeq;
#if SERIAL_DEBUG
        (void)seq;
        DBG_PRINTF("[N4 NOTE_ON ] part=0x%02X instr=%u note=%u vel=%u dur=%u seq=%lu t=%lu\n",
                   (unsigned)cfg_.partId,
                   (unsigned)cfg_.instrumentId,
                   (unsigned)data.noteOut.noteNumber,
                   (unsigned)data.noteOut.velocity,
                   (unsigned)data.noteOut.durationMs,
                   (unsigned long)seq,
                   (unsigned long)now);
#else
        buildAndSend(cfg_.partId, cfg_.instrumentId, /*gate=*/1, seq, now, data.noteOut);
#endif
        data.noteSender.lastSentMs = now;
        data.noteOut.pendingOn = false;
    }
    // NoteOff パケットは送らない: Processing 側が durationMs から自動消音する。
}
