// Build (run from project root) — shared by node_01〜node_04 of test_v2:
//   pio run -d firmware/test_v3/node_01     # 指揮者ノード
//   pio run -d firmware/test_v3/node_02     # 輪唱 声部 1

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
