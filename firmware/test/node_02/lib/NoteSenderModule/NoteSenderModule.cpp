// Build / Upload / Monitor (run from project root):
//   pio run -d firmware/test/node_02
//   pio run -d firmware/test/node_02 -t upload
//   pio device monitor -d firmware/test/node_02

#include "NoteSenderModule.h"
#include "SystemData.h"
#include "OrcProtocol.h"

bool NoteSenderModule::init() {
    Serial.begin(cfg_.baudRate);
    return true;
}

namespace {
void buildAndSend(uint8_t partId, uint8_t gate, uint32_t seq, uint32_t now,
                  const NoteOutData& out) {
    orc::NotePacket pkt{};
    pkt.header.magic       = orc::MAGIC;
    pkt.header.version     = orc::PROTOCOL_VERSION;
    pkt.header.type        = orc::PKT_NOTE;
    pkt.header.seq         = seq;
    pkt.header.timestampMs = now;
    pkt.payload.partId     = partId;
    pkt.payload.noteNumber = out.noteNumber;
    pkt.payload.velocity   = out.velocity;
    pkt.payload.gate       = gate;
    pkt.payload.durationMs = out.durationMs;
    pkt.payload.reserved[0] = 0;
    pkt.payload.reserved[1] = 0;
    Serial.write(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt));
}
}  // namespace

void NoteSenderModule::updateOutput(SystemData& data) {
    const uint32_t now = millis();
    if (data.noteOut.pendingOn) {
        buildAndSend(cfg_.partId, /*gate=*/1,
                     ++data.noteSender.noteSeq, now, data.noteOut);
        data.noteSender.lastSentMs = now;
        data.noteOut.pendingOn = false;
    }
    if (data.noteOut.pendingOff) {
        buildAndSend(cfg_.partId, /*gate=*/0,
                     ++data.noteSender.noteSeq, now, data.noteOut);
        data.noteSender.lastSentMs = now;
        data.noteOut.pendingOff = false;
    }
}
