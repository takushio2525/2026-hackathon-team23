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
