import processing.serial.*;
import ddf.minim.*;
import ddf.minim.ugens.*;
import java.awt.Font;
import java.awt.GraphicsEnvironment;
import java.util.*;
import java.util.concurrent.ConcurrentLinkedQueue;

Minim minim;
AudioOutput out;
PFont uiFont;
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

final int SCREEN_TITLE = 0;
final int SCREEN_PORT_SELECT = 1;
final int SCREEN_MODE_SELECT = 2;
final int SCREEN_PERFORMANCE = 3;

final int NODE_NONE = 0;
final int NODE_FLOW = 1;
final int NODE_PLAYER = 2;

int screenState = SCREEN_TITLE;
int nodeRole = NODE_NONE;

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
  surface.setTitle("processing");
  uiFont = createJapaneseUiFont(14);
  textFont(uiFont);

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);

  Arrays.fill(lastSeqByPart, -1);
  frameReader = new SerialFrameReader();
  partManager = new PartManager();
  ui = new UiView();
  logger = new Logger();

  refreshSerialPorts();
}

PFont createJapaneseUiFont(int size) {
  String[] candidates = {
    "Hiragino Sans",
    "Hiragino Kaku Gothic ProN",
    "Hiragino Maru Gothic ProN",
    "Yu Gothic",
    "Meiryo",
    "Noto Sans CJK JP",
    "SansSerif"
  };

  Font[] fonts = GraphicsEnvironment.getLocalGraphicsEnvironment().getAllFonts();
  for (String candidate : candidates) {
    for (Font font : fonts) {
      if ((font.getFamily().equals(candidate)
          || font.getFontName().equals(candidate)
          || font.getPSName().equals(candidate))
          && font.canDisplay('あ')
          && font.canDisplay('漢')) {
        return createFont(font.getFontName(), size, true);
      }
    }
  }
  return createFont("SansSerif", size, true);
}

void draw() {
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
    dropPacket("バージョンエラー: " + packet.version, packet);
    return;
  }
  if (packet.type != TYPE_NOTE) {
    dropPacket("NOTE以外のtype: " + packet.type, packet);
    return;
  }
  if (packet.gate != 0 && packet.gate != 1) {
    dropPacket("gateエラー: " + packet.gate, packet);
    return;
  }
  if (!isKnownPart(packet.partId)) {
    dropPacket("不明なpartId: 0x" + hex(packet.partId, 2), packet);
    return;
  }
  if (!acceptAllParts && packet.partId != expectedPartId) {
    wrongPartPackets++;
    droppedPackets++;
    lastWarning = "パート違い: 0x" + hex(packet.partId, 2);
    logger.logPacket("wrong_part", packet);
    return;
  }
  if (screenState != SCREEN_PERFORMANCE) {
    lastWarning = "演奏モードを選択してください";
    return;
  }
  long partLastSeq = lastSeqByPart[packet.partId & 0xff];
  if (partLastSeq >= 0) {
    if (packet.seq == partLastSeq) {
      dropPacket("重複seq: " + packet.seq, packet);
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
  lastWarning = "シリアルポートをクリック、または t キーでテスト音";
}

void connectSerial(int index) {
  if (index < 0 || index >= serialPorts.length) {
    lastWarning = "シリアル番号が範囲外です";
    return;
  }
  closeSerial();
  try {
    serialPortName = serialPorts[index];
    serialPort = new Serial(this, serialPortName, SERIAL_BAUD);
    serialPort.buffer(1);
    serialPort.clear();
    appState = "Ready";
    lastWarning = "接続しました: " + serialPortName;
    screenState = nodeRole == NODE_FLOW ? SCREEN_MODE_SELECT : SCREEN_PERFORMANCE;
    logger.logEvent("serial_connected," + serialPortName);
  } catch (Exception e) {
    appState = "Error";
    lastWarning = "シリアル接続に失敗: " + e.getMessage();
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
  if (screenState == SCREEN_TITLE) {
    int selectedRole = ui.nodeRoleAt(mouseX, mouseY);
    if (selectedRole != NODE_NONE) {
      nodeRole = selectedRole;
      closeSerial();
      refreshSerialPorts();
      screenState = SCREEN_PORT_SELECT;
      lastWarning = nodeRole == NODE_FLOW ? "Node1 全体進行を選択" : "Node2-5 演奏ノードを選択";
    }
    return;
  }

  if (screenState == SCREEN_PORT_SELECT) {
    if (ui.backButtonAt(mouseX, mouseY)) {
      closeSerial();
      nodeRole = NODE_NONE;
      screenState = SCREEN_TITLE;
      lastWarning = "";
      return;
    }
    if (serialPort != null) return;
    int index = ui.portIndexAt(mouseX, mouseY);
    if (index >= 0) connectSerial(index);
    return;
  }

  if (screenState == SCREEN_MODE_SELECT) {
    if (ui.backButtonAt(mouseX, mouseY)) {
      closeSerial();
      refreshSerialPorts();
      screenState = SCREEN_PORT_SELECT;
      return;
    }
    if (ui.performanceModeAt(mouseX, mouseY)) {
      screenState = SCREEN_PERFORMANCE;
      lastWarning = "演奏モードを開始";
      return;
    }
    if (ui.gameModeAt(mouseX, mouseY)) {
      lastWarning = "ゲームモードは準備中です";
      return;
    }
  }
}

void keyPressed() {
  if (screenState == SCREEN_PORT_SELECT && (key == 'r' || key == 'R')) {
    refreshSerialPorts();
    return;
  }
  if (screenState != SCREEN_PERFORMANCE) return;

  if (key == '1') setExpectedPart(PART_BRASS_1);
  else if (key == '2') setExpectedPart(PART_BRASS_2);
  else if (key == '3') setExpectedPart(PART_BRASS_3);
  else if (key == '4') setExpectedPart(PART_RHYTHM);
  else if (key == 'a' || key == 'A') {
    acceptAllParts = !acceptAllParts;
    lastWarning = acceptAllParts ? "全パートを受信します" : "選択中のパートだけ受信します";
  } else if (key == 'm' || key == 'M') {
    muted = !muted;
    if (muted) partManager.releaseAll();
    lastWarning = muted ? "ミュート中" : "ミュート解除";
  } else if (key == 'r' || key == 'R') {
    closeSerial();
    refreshSerialPorts();
    screenState = SCREEN_PORT_SELECT;
  } else if (key == 'd' || key == 'D') {
    closeSerial();
    appState = "PortSelect";
    screenState = SCREEN_PORT_SELECT;
    lastWarning = "切断しました";
  } else if (key == 't' || key == 'T') {
    partManager.playTestNote(expectedPartId);
  } else if (key == 'g' || key == 'G') {
    injectTestFrame(expectedPartId);
  }
}

void setExpectedPart(int partId) {
  expectedPartId = partId;
  acceptAllParts = false;
  lastWarning = "受信パート: 0x" + hex(partId, 2) + " " + partName(partId);
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
