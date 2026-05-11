import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import java.util.*;

Minim minim;
AudioOutput out;
Serial serialPort;
SerialFrameReader frameReader;
PartManager partManager;
UiView ui;
Logger logger;

String[] serialPorts = new String[0];
String serialPortName = "";
String appState = "PortSelect";
String lastWarning = "";

int expectedPartId = 0x02;
boolean acceptAllParts = false;
boolean muted = false;
long lastSeq = -1;
int receivedPackets = 0;
int droppedPackets = 0;
int wrongPartPackets = 0;
int missingPackets = 0;

void setup() {
  size(1000, 560);
  surface.setTitle("orchestra_processing_test");

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);

  frameReader = new SerialFrameReader();
  partManager = new PartManager();
  ui = new UiView();
  logger = new Logger();

  refreshSerialPorts();
}

void draw() {
  background(18);
  partManager.update();
  ui.draw();
}

void serialEvent(Serial p) {
  while (p.available() > 0) {
    frameReader.pushByte(p.read());
    NotePacket packet = frameReader.pollPacket();
    while (packet != null) {
      handlePacket(packet);
      packet = frameReader.pollPacket();
    }
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
  if (!acceptAllParts && packet.partId != expectedPartId) {
    wrongPartPackets++;
    droppedPackets++;
    lastWarning = "wrong partId 0x" + hex(packet.partId, 2);
    logger.logPacket("wrong_part", packet);
    return;
  }
  if (lastSeq >= 0) {
    if (packet.seq == lastSeq) {
      dropPacket("duplicate seq: " + packet.seq, packet);
      return;
    }
    if (packet.seq > lastSeq + 1) {
      missingPackets += (int)(packet.seq - lastSeq - 1);
    }
  }
  lastSeq = packet.seq;
  receivedPackets++;
  logger.logPacket("note", packet);
  partManager.handleNote(packet);
  appState = "Playing";
}

void dropPacket(String reason, NotePacket packet) {
  droppedPackets++;
  lastWarning = reason;
  logger.logPacket(reason, packet);
}

void refreshSerialPorts() {
  serialPorts = Serial.list();
  appState = "PortSelect";
  lastWarning = "select serial port with number key, or press t to test sound";
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
}

void keyPressed() {
  if (key >= '0' && key <= '9' && serialPort == null) {
    connectSerial(key - '0');
    return;
  }

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
    frameReader.clear();
    refreshSerialPorts();
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
