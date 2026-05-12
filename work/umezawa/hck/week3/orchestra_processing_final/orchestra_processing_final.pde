import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import java.util.*;
import java.util.concurrent.ConcurrentLinkedQueue;

Minim minim;
AudioOutput out;
Serial serialPort;
SerialFrameReader frameReader;
PartManager partManager;
UiView ui;
Logger logger;
ConcurrentLinkedQueue<NotePacket> packetQueue = new ConcurrentLinkedQueue<NotePacket>();

String[] serialPorts = new String[0];
String serialPortName = "";
String appState = "PortSelect";
String lastWarning = "";

int expectedPartId = 0x02;
boolean acceptAllParts = false;
boolean muted = false;
long lastSeq = -1;
long[] lastSeqByPart = new long[256];
int receivedPackets = 0;
int droppedPackets = 0;
int wrongPartPackets = 0;
int missingPackets = 0;
int lastNoteAtMs = 0;

void setup() {
  size(1000, 560);
  surface.setTitle("orchestra_processing_final");

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);

  Arrays.fill(lastSeqByPart, -1);
  frameReader = new SerialFrameReader();
  partManager = new PartManager();
  ui = new UiView();
  logger = new Logger();

  refreshSerialPorts();
}

void draw() {
  background(18);
  drainPackets();
  partManager.update();
  updateAppState();
  ui.draw();
}

void serialEvent(Serial p) {
  while (p.available() > 0) {
    frameReader.pushByte(p.read());
    NotePacket packet = frameReader.pollPacket();
    while (packet != null) {
      packetQueue.offer(packet);
      packet = frameReader.pollPacket();
    }
  }
}

void drainPackets() {
  NotePacket packet = packetQueue.poll();
  while (packet != null) {
    handlePacket(packet);
    packet = packetQueue.poll();
  }
}

void updateAppState() {
  if (serialPort == null) return;
  if (appState.equals("Playing") && millis() - lastNoteAtMs > 1000) {
    appState = "Ready";
  }
}

void handlePacket(NotePacket packet) {
  if (packet.version != PROTOCOL_VERSION) {
    dropPacket("version error: " + packet.version, packet);
    return;
  }
  if (packet.type != TYPE_NOTE) {
    dropPacket("non NOTE type: " + packet.type, packet);
    return;
  }
  if (packet.gate != 0 && packet.gate != 1) {
    dropPacket("gate error: " + packet.gate, packet);
    return;
  }
  if (!isKnownPart(packet.partId)) {
    dropPacket("unknown part: 0x" + hex(packet.partId, 2), packet);
    return;
  }
  if (!acceptAllParts && packet.partId != expectedPartId) {
    wrongPartPackets++;
    droppedPackets++;
    lastWarning = "wrong partId 0x" + hex(packet.partId, 2);
    logger.logPacket("wrong_part", packet);
    return;
  }
  long partLastSeq = lastSeqByPart[packet.partId & 0xff];
  if (partLastSeq >= 0) {
    if (packet.seq == partLastSeq) {
      dropPacket("duplicate seq: " + packet.seq, packet);
      return;
    }
    if (packet.seq > partLastSeq + 1) {
      missingPackets += (int)(packet.seq - partLastSeq - 1);
    }
  }
  lastSeqByPart[packet.partId & 0xff] = packet.seq;
  lastSeq = packet.seq;
  receivedPackets++;
  logger.logPacket("note", packet);
  partManager.handleNote(packet);
  appState = "Playing";
  lastNoteAtMs = millis();
}

void dropPacket(String reason, NotePacket packet) {
  droppedPackets++;
  lastWarning = reason;
  logger.logPacket(reason, packet);
}

void refreshSerialPorts() {
  serialPorts = Serial.list();
  appState = "PortSelect";
  lastWarning = "click serial port, or press t to test sound";
}

void connectSerial(int index) {
  if (index < 0 || index >= serialPorts.length) {
    lastWarning = "serial index out of range";
    return;
  }
  closeSerial();
  try {
    serialPortName = serialPorts[index];
    serialPort = new Serial(this, serialPortName, SERIAL_BAUD);
    serialPort.buffer(1);
    serialPort.clear();
    appState = "Ready";
    lastWarning = "connected: " + serialPortName;
    logger.logEvent("serial_connected," + serialPortName);
  } catch (Exception e) {
    appState = "Error";
    lastWarning = "serial open failed: " + e.getMessage();
    logger.logEvent("serial_error," + e.getMessage());
  }
}

void closeSerial() {
  if (serialPort != null) {
    try {
      serialPort.stop();
    } catch (Exception e) {
    }
  }
  serialPort = null;
  serialPortName = "";
  packetQueue.clear();
  frameReader.clear();
}

void mousePressed() {
  if (serialPort != null) return;
  int index = ui.portIndexAt(mouseX, mouseY);
  if (index >= 0) connectSerial(index);
}

void keyPressed() {
  if (key == '1') setExpectedPart(PART_BRASS_1);
  else if (key == '2') setExpectedPart(PART_BRASS_2);
  else if (key == '3') setExpectedPart(PART_BRASS_3);
  else if (key == '4') setExpectedPart(PART_RHYTHM);
  else if (key == 'a' || key == 'A') {
    acceptAllParts = !acceptAllParts;
    lastWarning = acceptAllParts ? "accept all parts" : "single part mode";
  } else if (key == 'm' || key == 'M') {
    muted = !muted;
    if (muted) partManager.releaseAll();
    lastWarning = muted ? "muted" : "unmuted";
  } else if (key == 'r' || key == 'R') {
    closeSerial();
    refreshSerialPorts();
  } else if (key == 'd' || key == 'D') {
    closeSerial();
    appState = "PortSelect";
    lastWarning = "disconnected";
  } else if (key == 't' || key == 'T') {
    partManager.playTestNote(expectedPartId);
  } else if (key == 'g' || key == 'G') {
    injectTestFrame(expectedPartId);
  }
}

void setExpectedPart(int partId) {
  expectedPartId = partId;
  acceptAllParts = false;
  lastWarning = "expected partId 0x" + hex(partId, 2) + " " + partName(partId);
}

void injectTestFrame(int partId) {
  byte[] frame = makeNoteFrame(partId, partId == PART_RHYTHM ? 36 : 60, 96, 1, 500, millis());
  for (int i = 0; i < frame.length; i++) frameReader.pushByte(frame[i] & 0xff);
  NotePacket packet = frameReader.pollPacket();
  if (packet != null) handlePacket(packet);
}

void stop() {
  partManager.releaseAll();
  logger.close();
  closeSerial();
  out.close();
  minim.stop();
  super.stop();
}
