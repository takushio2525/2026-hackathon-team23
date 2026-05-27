class UiView {
  int backX = 28;
  int backY = 24;
  int backW = 118;
  int backH = 38;

  int titleNodeY = 282;
  int titleNodeW = 300;
  int titleNodeH = 104;
  int titleNode1X = 170;
  int titleNodePlayerX = 530;

  int portButtonX = 190;
  int portButtonY = 188;
  int portButtonW = 620;
  int portButtonH = 40;
  int portButtonGap = 12;

  int playModeX = 190;
  int gameModeX = 540;
  int modeY = 230;
  int modeW = 270;
  int modeH = 135;

  void draw() {
    textFont(uiFont);
    drawGameBackground();
    if (screenState == SCREEN_TITLE) {
      drawTitleScreen();
    } else if (screenState == SCREEN_PORT_SELECT) {
      drawPortSelectScreen();
    } else if (screenState == SCREEN_MODE_SELECT) {
      drawModeSelectScreen();
    } else {
      drawPerformanceScreen();
    }
  }

  void drawGameBackground() {
    background(238, 247, 255);
    noStroke();
    fill(255, 221, 100, 120);
    ellipse(72, 70, 150, 150);
    fill(82, 194, 255, 95);
    ellipse(934, 92, 220, 220);
    fill(132, 224, 146, 95);
    ellipse(884, 526, 260, 180);
    fill(255, 125, 132, 80);
    ellipse(76, 520, 230, 160);

    stroke(210, 228, 240, 90);
    strokeWeight(1);
    for (int x = 0; x <= width; x += 50) line(x, 0, x, height);
    for (int y = 0; y <= height; y += 50) line(0, y, width, y);
    strokeWeight(1);
  }

  void drawTitleScreen() {
    textAlign(CENTER, BASELINE);
    textSize(72);
    fill(255, 196, 54);
    text("タクトーン", width / 2 + 5, 214);

    drawBigButton(titleNode1X, titleNodeY, titleNodeW, titleNodeH, "Node1", "全体進行", color(31, 123, 220), true);
    drawBigButton(titleNodePlayerX, titleNodeY, titleNodeW, titleNodeH, "Node2-5", "演奏ノード", color(24, 156, 104), true);
    fill(43, 66, 91);
    textSize(17);
  }

  void drawPortSelectScreen() {
    drawBackButton();
    drawPageTitle("シリアルポート選択", nodeRoleLabel());

    drawPanel(140, 136, 720, 348);
    fill(44, 64, 84);
    textSize(15);
    text("Arduino のポートをクリックしてください", 180, 164);

    if (serialPorts.length == 0) {
      fill(190, 76, 46);
      textSize(18);
      text("ポートが見つかりません。r キーで再読み込みできます。", 180, 238);
    } else {
      for (int i = 0; i < serialPorts.length && i < 7; i++) {
        drawPortButton(i, portButtonY + i * (portButtonH + portButtonGap));
      }
    }

    drawNotice(lastWarning, 180, 515);
  }

  void drawModeSelectScreen() {
    drawBackButton();
    drawPageTitle("ゲームモード選択", "Node1 全体進行");

    drawModeButton(playModeX, modeY, "演奏モード", "波形と受信状態を表示", color(64, 159, 255), true);
    drawModeButton(gameModeX, modeY, "ゲームモード", "準備中", color(166, 176, 188), false);

    drawNotice(lastWarning, 190, 452);
  }

  void drawPerformanceScreen() {
    drawPageTitle("演奏モード", nodeRoleLabel());
    drawStatusPanel();
    drawWaveformPanel();
    drawHelpPanel();
  }

  void drawPageTitle(String title, String subtitle) {
    fill(18, 54, 88);
    textSize(34);
    text(title, 168, 52);
    fill(61, 86, 111);
    textSize(15);
    text(subtitle, 170, 78);
  }

  void drawBackButton() {
    boolean hover = inRect(mouseX, mouseY, backX, backY, backW, backH);
    drawSmallButton(backX, backY, backW, backH, "もどる", hover ? color(255, 221, 100) : color(255, 238, 170), color(70, 67, 42));
  }

  void drawPanel(int x, int y, int w, int h) {
    noStroke();
    fill(23, 60, 95, 34);
    rect(x + 8, y + 10, w, h, 18);
    fill(255);
    rect(x, y, w, h, 18);
    stroke(134, 184, 218);
    strokeWeight(3);
    noFill();
    rect(x, y, w, h, 18);
    strokeWeight(1);
  }

  void drawBigButton(int x, int y, int w, int h, String mainText, String subText, int baseColor, boolean enabled) {
    boolean hover = enabled && inRect(mouseX, mouseY, x, y, w, h);
    noStroke();
    fill(23, 52, 84, 55);
    rect(x + 8, y + 10, w, h, 20);
    fill(hover ? lighten(baseColor, 22) : baseColor);
    rect(x, y, w, h, 20);
    stroke(255);
    strokeWeight(3);
    noFill();
    rect(x + 4, y + 4, w - 8, h - 8, 16);
    strokeWeight(1);
    fill(255);
    textAlign(CENTER, BASELINE);
    textSize(32);
    text(mainText, x + w / 2, y + 46);
    textSize(18);
    text(subText, x + w / 2, y + 78);
    textAlign(LEFT, BASELINE);
  }

  void drawModeButton(int x, int y, String mainText, String subText, int baseColor, boolean enabled) {
    boolean hover = enabled && inRect(mouseX, mouseY, x, y, modeW, modeH);
    noStroke();
    fill(23, 52, 84, 45);
    rect(x + 8, y + 10, modeW, modeH, 18);
    fill(enabled ? (hover ? lighten(baseColor, 24) : baseColor) : color(226, 231, 236));
    rect(x, y, modeW, modeH, 18);
    stroke(enabled ? color(255) : color(186, 196, 206));
    strokeWeight(3);
    noFill();
    rect(x + 4, y + 4, modeW - 8, modeH - 8, 14);
    strokeWeight(1);
    fill(enabled ? color(255) : color(120, 130, 140));
    textAlign(CENTER, BASELINE);
    textSize(28);
    text(mainText, x + modeW / 2, y + 58);
    textSize(15);
    text(subText, x + modeW / 2, y + 92);
    textAlign(LEFT, BASELINE);
  }

  void drawSmallButton(int x, int y, int w, int h, String label, int fillColor, int textColor) {
    noStroke();
    fill(fillColor);
    rect(x, y, w, h, 12);
    fill(textColor);
    textAlign(CENTER, BASELINE);
    textSize(14);
    text(label, x + w / 2, y + 24);
    textAlign(LEFT, BASELINE);
  }

  void drawPortButton(int index, int y) {
    boolean selected = serialPorts[index].equals(serialPortName);
    boolean hover = serialPort == null && inRect(mouseX, mouseY, portButtonX, y, portButtonW, portButtonH);
    int base = selected ? color(24, 156, 104) : hover ? color(210, 240, 255) : color(255);
    fill(base);
    stroke(selected ? color(17, 118, 78) : color(120, 183, 224));
    strokeWeight(2);
    rect(portButtonX, y, portButtonW, portButtonH, 12);
    strokeWeight(1);
    fill(selected ? color(255) : color(23, 52, 84));
    textSize(15);
    text(index + ": " + fitText(serialPorts[index], 58), portButtonX + 16, y + 25);
  }

  void drawStatusPanel() {
    drawPanel(28, 96, 944, 152);
    fill(18, 54, 88);
    textSize(20);
    text("受信ステータス", 50, 126);

    textSize(14);
    fill(28, 54, 80);
    text("状態: " + stateLabel(appState), 50, 158);
    text("受信パート: " + expectedPartLabel(), 260, 158);
    text("ミュート: " + (muted ? "オン" : "オフ"), 520, 158);
    text("発音数: " + partManager.activeVoiceCount(), 690, 158);
    text("受信: " + receivedPackets, 50, 195);
    text("破棄: " + droppedPackets, 170, 195);
    text("パート違い: " + wrongPartPackets, 290, 195);
    text("最後のseq: " + lastSeq, 500, 195);
    text("欠落: " + missingPackets, 690, 195);

    drawNotice(lastWarning, 50, 228);
  }

  void drawWaveformPanel() {
    drawPanel(28, 276, 944, 174);
    fill(18, 54, 88);
    textSize(20);
    text("出力波形", 50, 306);

    stroke(24, 111, 196);
    strokeWeight(2.5);
    int left = 50;
    int right = 950;
    int mid = 370;
    int span = right - left;
    for (int i = 0; i < out.bufferSize() - 1; i++) {
      float x1 = left + map(i, 0, out.bufferSize() - 1, 0, span);
      float x2 = left + map(i + 1, 0, out.bufferSize() - 1, 0, span);
      line(x1, mid - out.left.get(i) * 64, x2, mid - out.left.get(i + 1) * 64);
    }

    stroke(216, 225, 233);
    strokeWeight(1);
    line(left, mid, right, mid);
  }

  void drawHelpPanel() {
    fill(255);
    noStroke();
    rect(28, 476, 944, 58, 16);
    stroke(134, 184, 218);
    strokeWeight(2);
    noFill();
    rect(28, 476, 944, 58, 16);
    strokeWeight(1);
    fill(28, 54, 80);
    textSize(14);
    text("キー: 1-4 パート選択  |  a 全パート受信  |  t テスト音  |  g 疑似NOTE  |  m ミュート  |  r ポート再選択", 50, 511);
  }

  void drawNotice(String message, int x, int y) {
    if (message == null || message.length() == 0) return;
    fill(197, 83, 31);
    textSize(13);
    text(message, x, y);
  }

  int nodeRoleAt(int x, int y) {
    if (inRect(x, y, titleNode1X, titleNodeY, titleNodeW, titleNodeH)) return NODE_FLOW;
    if (inRect(x, y, titleNodePlayerX, titleNodeY, titleNodeW, titleNodeH)) return NODE_PLAYER;
    return NODE_NONE;
  }

  boolean backButtonAt(int x, int y) {
    return inRect(x, y, backX, backY, backW, backH);
  }

  boolean performanceModeAt(int x, int y) {
    return inRect(x, y, playModeX, modeY, modeW, modeH);
  }

  boolean gameModeAt(int x, int y) {
    return inRect(x, y, gameModeX, modeY, modeW, modeH);
  }

  int portIndexAt(int x, int y) {
    for (int i = 0; i < serialPorts.length && i < 7; i++) {
      int by = portButtonY + i * (portButtonH + portButtonGap);
      if (inRect(x, y, portButtonX, by, portButtonW, portButtonH)) return i;
    }
    return -1;
  }

  boolean inRect(int x, int y, int rx, int ry, int rw, int rh) {
    return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh;
  }

  int lighten(int c, int amount) {
    return color(min(255, red(c) + amount), min(255, green(c) + amount), min(255, blue(c) + amount));
  }

  String nodeRoleLabel() {
    if (nodeRole == NODE_FLOW) return "Node1 全体進行";
    if (nodeRole == NODE_PLAYER) return "Node2-5 演奏ノード";
    return "Node未選択";
  }

  String fitText(String value, int maxChars) {
    if (value.length() <= maxChars) return value;
    return "..." + value.substring(value.length() - maxChars + 3);
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
