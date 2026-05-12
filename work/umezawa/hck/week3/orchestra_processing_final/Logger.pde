class Logger {
  PrintWriter writer;

  Logger() {
    String filename = "orchestra_processing_final_log_" + year() + nf(month(), 2) + nf(day(), 2)
      + "_" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".csv";
    writer = createWriter(filename);
    writer.println("millis,event,seq,timestampMs,partId,noteNumber,velocity,gate,durationMs");
    writer.flush();
  }

  void logPacket(String event, NotePacket p) {
    if (writer == null || p == null) return;
    writer.println(millis() + "," + clean(event) + "," + p.seq + "," + p.timestampMs
      + ",0x" + hex(p.partId, 2) + "," + p.noteNumber + "," + p.velocity + "," + p.gate + "," + p.durationMs);
    writer.flush();
  }

  void logEvent(String event) {
    if (writer == null) return;
    writer.println(millis() + "," + clean(event) + ",,,,,,,");
    writer.flush();
  }

  String clean(String value) {
    return value.replace(',', '_');
  }

  void close() {
    if (writer == null) return;
    writer.flush();
    writer.close();
    writer = null;
  }
}
