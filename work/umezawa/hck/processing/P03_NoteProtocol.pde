class NotePacket {
  int version;
  int type;
  long seq;
  long timestampMs;
  int partId;
  int noteNumber;
  int velocity;
  int gate;
  int durationMs;
}

int u16le(byte[] b, int off) {
  return (b[off] & 0xff) | ((b[off + 1] & 0xff) << 8);
}

long u32le(byte[] b, int off) {
  return ((long)b[off] & 0xff)
    | (((long)b[off + 1] & 0xff) << 8)
    | (((long)b[off + 2] & 0xff) << 16)
    | (((long)b[off + 3] & 0xff) << 24);
}

void put16le(byte[] b, int off, int value) {
  b[off] = (byte)(value & 0xff);
  b[off + 1] = (byte)((value >> 8) & 0xff);
}

void put32le(byte[] b, int off, long value) {
  b[off] = (byte)(value & 0xff);
  b[off + 1] = (byte)((value >> 8) & 0xff);
  b[off + 2] = (byte)((value >> 16) & 0xff);
  b[off + 3] = (byte)((value >> 24) & 0xff);
}

NotePacket decodeNote(byte[] frame) {
  if (frame.length != NOTE_FRAME_SIZE) return null;
  if (u16le(frame, 0) != MAGIC) return null;

  NotePacket p = new NotePacket();
  p.version = frame[2] & 0xff;
  p.type = frame[3] & 0xff;
  p.seq = u32le(frame, 4);
  p.timestampMs = u32le(frame, 8);
  p.partId = frame[12] & 0xff;
  p.noteNumber = frame[13] & 0xff;
  p.velocity = frame[14] & 0xff;
  p.gate = frame[15] & 0xff;
  p.durationMs = u16le(frame, 16);
  return p;
}

byte[] makeNoteFrame(int partId, int noteNumber, int velocity, int gate, int durationMs, long seq) {
  byte[] frame = new byte[NOTE_FRAME_SIZE];
  put16le(frame, 0, MAGIC);
  frame[2] = (byte)PROTOCOL_VERSION;
  frame[3] = (byte)TYPE_NOTE;
  put32le(frame, 4, seq);
  put32le(frame, 8, millis());
  frame[12] = (byte)partId;
  frame[13] = (byte)noteNumber;
  frame[14] = (byte)velocity;
  frame[15] = (byte)gate;
  put16le(frame, 16, durationMs);
  frame[18] = 0;
  frame[19] = 0;
  return frame;
}
