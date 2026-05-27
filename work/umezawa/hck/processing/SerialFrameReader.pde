class SerialFrameReader {
  ArrayList<Integer> buffer = new ArrayList<Integer>();

  void pushByte(int value) {
    buffer.add(value & 0xff);
    if (buffer.size() > 512) {
      buffer.remove(0);
      droppedPackets++;
      lastWarning = "serial buffer overflow";
    }
  }

  NotePacket pollPacket() {
    while (buffer.size() >= 2) {
      int b0 = buffer.get(0);
      int b1 = buffer.get(1);
      if (b0 == 0x52 && b1 == 0x4f) break;
      buffer.remove(0);
    }

    if (buffer.size() < NOTE_FRAME_SIZE) return null;

    byte[] frame = new byte[NOTE_FRAME_SIZE];
    for (int i = 0; i < NOTE_FRAME_SIZE; i++) {
      frame[i] = (byte)(int)buffer.remove(0);
    }
    return decodeNote(frame);
  }

  void clear() {
    buffer.clear();
  }
}
