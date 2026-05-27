class UiView {
  int portPanelX = 28;
  int portPanelY = 86;
  int portPanelW = 410;
  int portPanelH = 190;
  int portButtonX = 46;
  int portButtonW = 372;
  int portButtonH = 24;
  int portButtonGap = 6;

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
    text("Orchestra Processing Final", 28, 40);

    textSize(13);
    fill(180);
    text("20-byte NOTE receiver / brass 3 + rhythm 1 / durationMs auto release", 30, 64);
  }

  void drawPorts() {
    fill(34);
    noStroke();
    rect(portPanelX, portPanelY, portPanelW, portPanelH, 6);

    fill(230);
    textSize(16);
    text("Serial", 46, 116);

    textSize(12);
    fill(190);
    if (serialPort == null) {
      text("not connected: click a port to open", 46, 140);
    } else {
      text("connected: " + serialPortName, 46, 140);
    }

    int y = 166;
    if (serialPorts.length == 0) {
      fill(255, 170, 120);
      text("No serial ports. Press r to refresh.", 46, y);
    } else {
      for (int i = 0; i < serialPorts.length && i < 8; i++) {
        drawPortButton(i, y);
        y += portButtonH + portButtonGap;
      }
    }
  }

  void drawPortButton(int index, int y) {
    boolean selected = serialPorts[index].equals(serialPortName);
    boolean hover = serialPort == null
      && mouseX >= portButtonX && mouseX <= portButtonX + portButtonW
      && mouseY >= y && mouseY <= y + portButtonH;

    fill(selected ? color(58, 110, 80) : hover ? color(52, 85, 72) : color(42, 54, 58));
    noStroke();
    rect(portButtonX, y, portButtonW, portButtonH, 5);

    fill(230);
    textSize(12);
    text(index + ": " + fitText(serialPorts[index], 46), portButtonX + 10, y + 16);
  }

  int portIndexAt(int x, int y) {
    if (serialPort != null) return -1;
    for (int i = 0; i < serialPorts.length && i < 8; i++) {
      int by = 166 + i * (portButtonH + portButtonGap);
      if (x >= portButtonX && x <= portButtonX + portButtonW
        && y >= by && y <= by + portButtonH) {
        return i;
      }
    }
    return -1;
  }

  String fitText(String value, int maxChars) {
    if (value.length() <= maxChars) return value;
    return "..." + value.substring(value.length() - maxChars + 3);
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
    text("keys: 1-4 part  |  a all parts  |  t test note  |  g fake NOTE frame  |  m mute  |  r refresh  |  d disconnect", 30, 512);
    text("Click a serial port to connect. NOTE: magic 0x4F52, version 1, type 3, partId 0x02-0x05.", 30, 534);
  }
}
