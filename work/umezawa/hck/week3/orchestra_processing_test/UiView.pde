class UiView {
  void draw() {
    drawHeader();
    drawPorts();
    drawStatus();
    drawWaveform();
    drawHelp();
  }

  void drawHeader() {
    fill(245);
    textSize(24);
    text("Orchestra Processing Test", 28, 40);

    textSize(13);
    fill(170);
    text("NOTE 20-byte serial receiver / brass 3 + rhythm 1", 30, 64);
  }

  void drawPorts() {
    fill(34);
    noStroke();
    rect(28, 86, 410, 190, 6);

    fill(230);
    textSize(16);
    text("Serial", 46, 116);

    textSize(12);
    fill(190);
    if (serialPort == null) {
      text("not connected", 46, 140);
    } else {
      text("connected: " + serialPortName, 46, 140);
    }

    int y = 166;
    if (serialPorts.length == 0) {
      fill(255, 170, 120);
      text("No serial ports. Press r to refresh.", 46, y);
    } else {
      fill(200);
      for (int i = 0; i < serialPorts.length && i < 8; i++) {
        text(i + ": " + serialPorts[i], 46, y);
        y += 18;
      }
    }
  }

  void drawStatus() {
    fill(34);
    noStroke();
    rect(462, 86, 510, 190, 6);

    fill(230);
    textSize(16);
    text("Status", 480, 116);

    textSize(13);
    fill(210);
    int y = 144;
    text("state: " + appState, 480, y); y += 22;
    text("expected: " + (acceptAllParts ? "ALL" : "0x" + hex(expectedPartId, 2) + " " + partName(expectedPartId)), 480, y); y += 22;
    text("muted: " + muted, 480, y); y += 22;
    text("voices: " + partManager.activeVoiceCount(), 480, y); y += 22;
    text("received: " + receivedPackets + "  dropped: " + droppedPackets + "  wrong part: " + wrongPartPackets, 480, y); y += 22;
    text("last seq: " + lastSeq + "  missing: " + missingPackets, 480, y); y += 22;

    fill(255, 190, 95);
    text(lastWarning, 480, y);
  }

  void drawWaveform() {
    fill(22);
    noStroke();
    rect(28, 304, 944, 170, 6);

    stroke(100, 210, 255);
    strokeWeight(1.5);
    int left = 44;
    int right = 956;
    int mid = 389;
    int span = right - left;
    for (int i = 0; i < out.bufferSize() - 1; i++) {
      float x1 = left + map(i, 0, out.bufferSize() - 1, 0, span);
      float x2 = left + map(i + 1, 0, out.bufferSize() - 1, 0, span);
      line(x1, mid - out.left.get(i) * 68, x2, mid - out.left.get(i + 1) * 68);
    }

    stroke(80);
    line(left, mid, right, mid);
  }

  void drawHelp() {
    fill(180);
    textSize(13);
    text("keys: 1-4 part  |  a all parts  |  t test note  |  g fake NOTE frame  |  m mute  |  r refresh serial", 30, 512);
    text("When serial is disconnected, number keys select a serial port index.", 30, 534);
  }
}
