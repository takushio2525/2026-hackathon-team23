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
    fill(28, 44, 58);
    textSize(26);
    text("processing", 28, 40);

    textSize(13);
    fill(82, 101, 119);
    text("20バイトのNOTE受信 / 金管3パート + リズム1パート / durationMsで自動消音", 30, 64);
  }

  void drawPorts() {
    fill(255);
    noStroke();
    rect(portPanelX, portPanelY, portPanelW, portPanelH, 8);
    stroke(211, 220, 230);
    noFill();
    rect(portPanelX, portPanelY, portPanelW, portPanelH, 8);

    fill(35, 53, 68);
    textSize(16);
    text("シリアル接続", 46, 116);

    textSize(12);
    fill(82, 101, 119);
    if (serialPort == null) {
      text("未接続: 下のポートをクリックして接続", 46, 140);
    } else {
      text("接続中: " + serialPortName, 46, 140);
    }

    int y = 166;
    if (serialPorts.length == 0) {
      fill(184, 83, 27);
      text("ポートが見つかりません。r キーで再読み込み。", 46, y);
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

    fill(selected ? color(46, 125, 93) : hover ? color(221, 238, 231) : color(239, 244, 248));
    stroke(selected ? color(46, 125, 93) : color(204, 214, 224));
    rect(portButtonX, y, portButtonW, portButtonH, 6);

    fill(selected ? color(255) : color(35, 53, 68));
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
    fill(255);
    noStroke();
    rect(462, 86, 510, 190, 8);
    stroke(211, 220, 230);
    noFill();
    rect(462, 86, 510, 190, 8);

    fill(35, 53, 68);
    textSize(16);
    text("状態", 480, 116);

    textSize(13);
    fill(64, 81, 97);
    int y = 144;
    text("状態: " + stateLabel(appState), 480, y); y += 22;
    text("受信パート: " + expectedPartLabel(), 480, y); y += 22;
    text("ミュート: " + (muted ? "オン" : "オフ"), 480, y); y += 22;
    text("発音数: " + partManager.activeVoiceCount(), 480, y); y += 22;
    text("受信: " + receivedPackets + "  破棄: " + droppedPackets + "  パート違い: " + wrongPartPackets, 480, y); y += 22;
    text("最後のseq: " + lastSeq + "  欠落: " + missingPackets, 480, y); y += 22;

    fill(184, 83, 27);
    text(lastWarning, 480, y);
  }

  void drawWaveform() {
    fill(255);
    noStroke();
    rect(28, 304, 944, 170, 8);
    stroke(211, 220, 230);
    noFill();
    rect(28, 304, 944, 170, 8);

    fill(35, 53, 68);
    textSize(15);
    text("出力波形", 46, 330);

    stroke(45, 126, 167);
    strokeWeight(1.8);
    int left = 44;
    int right = 956;
    int mid = 389;
    int span = right - left;
    for (int i = 0; i < out.bufferSize() - 1; i++) {
      float x1 = left + map(i, 0, out.bufferSize() - 1, 0, span);
      float x2 = left + map(i + 1, 0, out.bufferSize() - 1, 0, span);
      line(x1, mid - out.left.get(i) * 68, x2, mid - out.left.get(i + 1) * 68);
    }

    stroke(216, 225, 233);
    line(left, mid, right, mid);
  }

  void drawHelp() {
    fill(64, 81, 97);
    textSize(13);
    text("キー: 1-4 パート選択  |  a 全パート受信  |  t テスト音  |  g 疑似NOTE  |  m ミュート  |  r 更新  |  d 切断", 30, 512);
    text("シリアルポートをクリックして接続。NOTE仕様: magic 0x4F52、version 1、type 3、partId 0x02-0x05。", 30, 534);
  }

  String expectedPartLabel() {
    if (acceptAllParts) return "すべて";
    return "0x" + hex(expectedPartId, 2) + " " + partLabel(expectedPartId);
  }

  String partLabel(int partId) {
    if (partId == PART_BRASS_1) return "金管1";
    if (partId == PART_BRASS_2) return "金管2";
    if (partId == PART_BRASS_3) return "金管3";
    if (partId == PART_RHYTHM) return "リズム";
    return "不明";
  }

  String stateLabel(String state) {
    if (state.equals("PortSelect")) return "ポート選択";
    if (state.equals("Ready")) return "待機中";
    if (state.equals("Playing")) return "再生中";
    if (state.equals("Error")) return "エラー";
    return state;
  }
}
