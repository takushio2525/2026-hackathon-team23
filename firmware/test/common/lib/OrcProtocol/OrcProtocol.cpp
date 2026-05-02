// Build (run from project root) — shared by node_01 and node_02:
//   pio run -d firmware/test/node_01     # 指揮者ノード
//   pio run -d firmware/test/node_02     # 楽器 1

#include "OrcProtocol.h"
#include <stdint.h>
#include <string.h>

namespace orc {

bool parseHeader(const uint8_t* buf, size_t len, PacketHeader& out) {
    if (len < HEADER_SIZE) return false;
    memcpy(&out, buf, HEADER_SIZE);
    if (out.magic != MAGIC) return false;
    if (out.version != PROTOCOL_VERSION) return false;
    return true;
}

}  // namespace orc
