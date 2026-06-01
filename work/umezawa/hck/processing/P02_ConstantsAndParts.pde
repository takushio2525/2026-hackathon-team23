final int SERIAL_BAUD = 115200;

final int PROTOCOL_VERSION = 1;
final int TYPE_NOTE = 3;
final int NOTE_FRAME_SIZE = 20;
final int MAGIC = 0x4F52;

final int PART_BRASS_1 = 0x02;
final int PART_BRASS_2 = 0x03;
final int PART_BRASS_3 = 0x04;
final int PART_RHYTHM = 0x05;
final int PART_BRASS_4 = 0x06;

final int MAX_VOICES_PER_PART = 4;
final int MIN_DURATION_MS = 120;
final int DEFAULT_TEST_DURATION_MS = 550;
final float MASTER_GAIN = 0.55;

String partName(int partId) {
  if (partId == PART_BRASS_1) return "Tuba";
  if (partId == PART_BRASS_2) return "Trombone";
  if (partId == PART_BRASS_3) return "Horn";
  if (partId == PART_RHYTHM) return "Rhythm";
  if (partId == PART_BRASS_4) return "Trumpet";
  return "Unknown";
}

boolean isKnownPart(int partId) {
  return partId == PART_BRASS_1
    || partId == PART_BRASS_2
    || partId == PART_BRASS_3
    || partId == PART_RHYTHM
    || partId == PART_BRASS_4;
}

float midiToHz(int noteNumber) {
  return 440.0f * pow(2.0f, (noteNumber - 69) / 12.0f);
}
