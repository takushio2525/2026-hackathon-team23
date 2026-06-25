/* ==========================================================================
   SharedUI — 共通 UI 描画コンポーネント
   共有タブ: 各スケッチから symlink で参照。

   グローバル依存: out (AudioOutput) — drawScope で使用
   ========================================================================== */

PFont loadJapaneseFont(float sizePx){
  String[] candidates = {
    "Hiragino Sans", "Hiragino Kaku Gothic ProN", "HiraginoSans-W3",
    "Yu Gothic", "Yu Gothic Medium", "Meiryo",
    "Noto Sans CJK JP", "Noto Sans JP", "Arial Unicode MS"
  };
  String[] avail = PFont.list();
  for (String c : candidates)
    for (String a : avail)
      if (a.equalsIgnoreCase(c)){ println("UI font: " + c); return createFont(c, sizePx, true); }
  println("(!) 日本語対応フォントが見つかりませんでした。");
  return null;
}

void drawBackground(){
  background(238, 247, 255);
  noStroke();
  fill(255, 221, 100, 120); ellipse(72, 70, 150, 150);
  fill(82, 194, 255, 95);   ellipse(934, 92, 220, 220);
  fill(132, 224, 146, 95);  ellipse(884, 526, 260, 180);
  fill(255, 125, 132, 80);  ellipse(76, 520, 230, 160);
  stroke(210, 228, 240, 90); strokeWeight(1);
  for (int gx = 0; gx <= width; gx += 50) line(gx, 0, gx, height);
  for (int gy = 0; gy <= height; gy += 50) line(0, gy, width, gy);
  noStroke();
}

void drawPanel(float x, float y, float w, float h){
  noStroke();
  fill(23, 60, 95, 34); rect(x + 8, y + 10, w, h, 18);
  fill(255); rect(x, y, w, h, 18);
  stroke(134, 184, 218); strokeWeight(3); noFill();
  rect(x, y, w, h, 18);
  strokeWeight(1); noStroke();
}

boolean mouseOver(float x, float y, float w, float h){
  return mouseX>=x && mouseX<=x+w && mouseY>=y && mouseY<=y+h;
}

int lighten(int c, int amount){
  return color(min(255, red(c)+amount), min(255, green(c)+amount), min(255, blue(c)+amount));
}

void drawScope(float x, float y, float w, float h){
  drawPanel(x, y, w, h);
  fill(18, 54, 88); textSize(14); textAlign(LEFT, BASELINE);
  text("出力波形", x + 22, y + 24);
  stroke(24, 111, 196); strokeWeight(2.5); noFill();
  float cy = y + h * 0.55f;
  beginShape();
  for (int i = 0; i < out.bufferSize(); i++)
    vertex(x + 20 + (w - 40) * i / (float)(out.bufferSize() - 1), cy - out.left.get(i) * (h * 0.35f));
  endShape();
  strokeWeight(1); noStroke();
}

void drawPageTitle(String title, String subtitle){
  fill(18, 54, 88); textSize(34); textAlign(LEFT, BASELINE);
  text(title, 168, 52);
  fill(61, 86, 111); textSize(15);
  text(subtitle, 170, 78);
  textAlign(LEFT, BASELINE);
}
