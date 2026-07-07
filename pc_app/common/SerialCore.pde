/* ==========================================================================
   SerialCore — シリアルポート管理・パケットフレーミングの共通部分
   共有タブ: 各スケッチから symlink で参照。

   グローバル依存 (各スケッチの main .pde で宣言が必要):
     HashMap<String,PortConn> openByName;
     HashMap<Serial,PortConn> bySerial;
     ConcurrentLinkedQueue<byte[]> packetQueue;
     String[] availablePorts;
     String[] displayPorts;
     boolean usbOnly;
     float portScrollY;
   ========================================================================== */

class PortConn {
  String  name;
  Serial  port;
  byte[]  rxBuf = new byte[PACKET_SIZE];
  int     rxIdx = 0;
  boolean inFrame = false;
  int     rxCount = 0;
  PortConn(String n) { name = n; }
}

boolean isUsbSerialName(String name){
  if (name == null) return false;
  String n = name.toLowerCase();
  return n.contains("usbmodem") || n.contains("usbserial")
      || n.contains("ttyusb")   || n.contains("ttyacm")
      || n.startsWith("com")    || n.contains("/com");
}

void refreshPorts(){
  try {
    availablePorts = Serial.list();
  } catch (Exception e){
    println("[警告] Serial.list() 失敗 (" + e.getClass().getSimpleName() + "): " + e.getMessage());
    availablePorts = listPortsFallback();
    println("[情報] フォールバック: /dev/cu.* から " + availablePorts.length + " ポート検出");
  }
  rebuildDisplayPorts();
  println("Serial ports (usbOnly=" + usbOnly + "): " + availablePorts.length + " 個");
}

// Serial.list() が JSSC 内部で例外を投げる場合のフォールバック
String[] listPortsFallback(){
  File dev = new File("/dev");
  File[] files = dev.listFiles(new java.io.FilenameFilter(){
    public boolean accept(File dir, String name){ return name.startsWith("cu."); }
  });
  if (files == null) return new String[0];
  String[] result = new String[files.length];
  for (int i = 0; i < files.length; i++) result[i] = files[i].getAbsolutePath();
  java.util.Arrays.sort(result);
  return result;
}

void rebuildDisplayPorts(){
  if (!usbOnly){ displayPorts = availablePorts; }
  else {
    ArrayList<String> kept = new ArrayList<String>();
    for (String n : availablePorts)
      if (isUsbSerialName(n) || openByName.containsKey(n)) kept.add(n);
    displayPorts = kept.toArray(new String[0]);
  }
  if (displayPorts.length == 0) portScrollY = 0;
}

void openPort(String name){
  if (openByName.containsKey(name)) return;
  try {
    PortConn pc = new PortConn(name);
    pc.port = new Serial(this, name, SERIAL_BAUD);
    pc.port.buffer(1);
    openByName.put(name, pc);
    bySerial.put(pc.port, pc);
    println("Opened: " + name);
  } catch (Exception e){
    println("(!) Failed to open " + name + ": " + e.getMessage());
  }
}

void closePort(String name){
  PortConn pc = openByName.remove(name);
  if (pc == null) return;
  if (pc.port != null){
    bySerial.remove(pc.port);
    try { pc.port.stop(); } catch (Exception e){ /* ignore */ }
  }
  println("Closed: " + name);
}

void togglePort(String name){
  if (openByName.containsKey(name)) closePort(name);
  else openPort(name);
}

void closeAllPorts(){
  for (String n : new ArrayList<String>(openByName.keySet())) closePort(n);
}

// ── シリアル受信 (Serial スレッド) ─────────────────────────
void serialEvent(Serial p){
  PortConn pc = bySerial.get(p);
  if (pc == null){ while (p.available() > 0) p.read(); return; }
  while (p.available() > 0){
    int b = p.read();
    if (!pc.inFrame){
      if (pc.rxIdx == 0){
        if ((byte)b == MAGIC_LO){ pc.rxBuf[0] = (byte)b; pc.rxIdx = 1; }
      } else {
        if ((byte)b == MAGIC_HI){ pc.rxBuf[1] = (byte)b; pc.rxIdx = 2; pc.inFrame = true; }
        else { pc.rxIdx = ((byte)b == MAGIC_LO) ? 1 : 0; if (pc.rxIdx == 1) pc.rxBuf[0] = (byte)b; }
      }
    } else {
      pc.rxBuf[pc.rxIdx++] = (byte)b;
      if (pc.rxIdx >= PACKET_SIZE){
        byte[] copy = new byte[PACKET_SIZE];
        System.arraycopy(pc.rxBuf, 0, copy, 0, PACKET_SIZE);
        packetQueue.offer(copy);
        pc.rxCount++;
        pc.rxIdx = 0; pc.inFrame = false;
      }
    }
  }
}
