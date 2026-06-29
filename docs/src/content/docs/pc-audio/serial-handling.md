---
title: マルチポート同時受信
description: 1 つの Processing で複数の USB シリアルを並行受信する仕組み — PortConn / packetQueue / ConcurrentLinkedQueue
sidebar:
  order: 6
---

実体: `pc_app/common/SerialCore.pde`（107行）。packetの意味付けは
`pc_app/production/orchestra_resynth/orchestra_resynth.pde` の `handlePacket()` が担当する。

このページは **「なぜマルチポートが要るのか、どう実装してあるか、自分で書き直すなら何に注意するか」**
を解剖する。

## 何のために複数ポートを 1 つの Processing で扱うか

productionは **1つのProcessingで複数楽器ノードを開ける** 構成で、次に対応する:

- **リハ会場で楽器 3 台を 1 Mac に USB 直結して動作確認したい**（人手減らす）
- 楽器ノードを USB ハブで集約してデモ机に並べ、1 Mac で全声部を鳴らす
- 故障時のフォールバック（別ノードの PC が壊れたとき、別 PC が複数声部を引き受ける）

これらを **設定変更なし** で済ませるため、Processing 起動後に **画面のポート一覧をクリック**
すれば任意のポートを開閉できる構造にした。

## データ構造

```java
class PortConn {
  String  name;       // OS が見せるポート名 (e.g. /dev/cu.usbmodem14101)
  Serial  port;       // Processing の Serial オブジェクト
  byte[]  rxBuf = new byte[PACKET_SIZE];   // パケット 1 個分のバッファ
  int     rxIdx = 0;                       // rxBuf の書き込み位置
  boolean inFrame = false;                 // magic 同期後 true
  int     rxCount = 0;                     // 受信パケット数（UI 表示用）
  PortConn(String n) { name = n; }
}

String[]                  availablePorts;  // Serial.list() のスナップショット
HashMap<String,PortConn>  openByName;       // 開いているポート（名前で引く）
HashMap<Serial,PortConn>  bySerial;         // serialEvent で逆引き
ConcurrentLinkedQueue<byte[]> packetQueue;  // 完成パケットを draw 側に渡すキュー
```

設計上の要点:

| 構造 | 役割 | なぜそう選んだか |
|---|---|---|
| `PortConn` per ポート | 各ポートが **独立した受信状態** を持つ | 同期 (magic 待ち) は各 USB ストリームで独立。共有すると別ポートのバイトが混ざる |
| `openByName` | 開閉状態の管理 | 同じポートを 2 回開かないため |
| `bySerial` | `serialEvent(Serial p)` から逆引き | Processing の API がポート名でなく `Serial` オブジェクトを渡してくるため |
| `packetQueue` | Serial → Animation の橋 | 複数portから安全にofferでき、drawがpollできる |

## シリアル受信ループ — magic 同期

`serialEvent(Serial p)` は **Serial スレッド** で呼ばれる。

```java
void serialEvent(Serial p){
  PortConn pc = bySerial.get(p);
  if (pc == null){ while (p.available() > 0) p.read(); return; }  // 知らないポートは捨てる

  while (p.available() > 0){
    int b = p.read();

    if (!pc.inFrame){
      // 同期待ち: 'R'(0x52) → 'O'(0x4F) の 2 バイトで magic 確認
      if (pc.rxIdx == 0){
        if ((byte)b == MAGIC_LO){ pc.rxBuf[0] = (byte)b; pc.rxIdx = 1; }
      } else { // rxIdx == 1
        if ((byte)b == MAGIC_HI){
          pc.rxBuf[1] = (byte)b; pc.rxIdx = 2; pc.inFrame = true;
        } else {
          // 失敗: 次のバイトが 0x52 ならまた最初の R 候補に
          pc.rxIdx = ((byte)b == MAGIC_LO) ? 1 : 0;
          if (pc.rxIdx == 1) pc.rxBuf[0] = (byte)b;
        }
      }
    } else {
      // フレーム中: ひたすら 20 B 貯める
      pc.rxBuf[pc.rxIdx++] = (byte)b;
      if (pc.rxIdx >= PACKET_SIZE){
        byte[] copy = new byte[PACKET_SIZE];
        System.arraycopy(pc.rxBuf, 0, copy, 0, PACKET_SIZE);
        packetQueue.offer(copy);
        pc.rxCount++;
        pc.rxIdx = 0;
        pc.inFrame = false;
      }
    }
  }
}
```

### magic 同期のしくみ — なぜ 2 バイト必要か

シリアルは「途中から読み始める」「ノイズが混ざる」が常態。1 バイトの magic では誤同期する。

`OrcProtocol` のヘッダは `magic = 0x4F52`（リトルエンディアン送信）なので、PC は
**`0x52` (`R`) → `0x4F` (`O`)** の順で受信する。両方一致して初めて「これがパケット先頭」と
判断する。

```
入ってきたバイト列 (例):
   ?? ?? 52 4F .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..    ← パケット 1
   .. 52 4F .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..    ← パケット 2
       ↑↑ ここで同期
```

最初の `0x52` を見つけたら次を見て、`0x4F` でなければ「**そのバイトがまた `0x52` なら**
そこから再試行」というロジックを入れている（連続する `0x52` への対応）:

```java
pc.rxIdx = ((byte)b == MAGIC_LO) ? 1 : 0;
if (pc.rxIdx == 1) pc.rxBuf[0] = (byte)b;
```

### なぜ `buffer(1)` を呼んでいるか

```java
pc.port = new Serial(this, name, SERIAL_BAUD);
pc.port.buffer(1);
```

`buffer(1)` は「**1 バイト届くたびに `serialEvent` を呼べ**」という指示。これを呼ばないと
Processing は内部で勝手にバッファして呼び出し頻度を絞るので、遅延が増える。

20 バイト溜まるたびに 1 度呼ばせる `buffer(20)` の方が呼び出しオーバーヘッドは少ないが、
**フレーム境界がずれた場合の同期が遅れる** ので 1 バイトずつ取る。

## なぜ ConcurrentLinkedQueue か

`packetQueue: ConcurrentLinkedQueue<byte[]>` を選んだ理由:

| 候補 | 評価 |
|---|---|
| `synchronized` ブロック | 動くが、Serial スレッドと Animation スレッドのロック競合が発音遅延に直結 |
| `ArrayBlockingQueue` | 容量上限で **`offer` が失敗する** リスク（NOTE 取りこぼし） |
| **`ConcurrentLinkedQueue`** | ロックフリーで容量無制限、`offer` は必ず成功、`poll` は空なら null |
| `LinkedBlockingQueue` | `take` がブロックするので Animation スレッドが固まる |

採用したのは `ConcurrentLinkedQueue`。Serial callback側のproducerとAnimation側の
consumerが同じ配列を直接触らずに済む。

容量無制限が怖い場合もあるが、20 B × 万単位なら数十 MB で、ハッカソン用途では問題なし。
draw が毎フレーム必ず poll するので無限に伸びることはない。

## パケット → NOTEまたはUIへの変換

```java
void drainPackets(){
  byte[] pkt;
  while ((pkt = packetQueue.poll()) != null) handlePacket(pkt);
}

void handlePacket(byte[] buf){
  totalReceived++;
  int type = packetType(buf);
  if (type == TYPE_UI){
    UiEvent ui = new UiEvent(buf);
    // state/mode/cursor/target/score/BPMを更新して画面判定へ
    return;
  }
  if (type != TYPE_NOTE) return;
  NoteEvent n = new NoteEvent(buf);
  if (n.gate == 1)
    triggerNote(n.partId, n.instrumentId, n.noteNumber, n.velocity, n.durationMs);
  else if (!isDrumInstrument(n.instrumentId))
    releaseMatching(n.partId, n.noteNumber + brassOctaveShift(n.instrumentId));
}
```

ポイント:

- **`u8` / `u16le` で符号無しに正規化**（Java の byte は符号付き）
- **version が違うと無視**（互換性の壁を作ってある）
- **type=UI は画面状態へ反映、type=NOTE は発音へ反映**
- CTRL/BEATや未知typeは無視する
- `instrumentId` が 0 から始まる 1 バイト整数

`u16le(lo, hi)` の中身:

```java
int u8(byte v){ return v & 0xFF; }
int u16le(byte lo, byte hi){ return u8(lo) | (u8(hi) << 8); }
```

リトルエンディアンで 2 バイトを 16 bit 符号無し整数にする。

## ポートの開閉

```java
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
    try { pc.port.stop(); } catch (Exception e){ /* 無視 */ }
  }
  println("Closed: " + name);
}
```

要点:

- **`new Serial(...)` を try/catch で囲む**: ポートが他のプロセスに掴まれていると例外が出る。Processing 全体が落ちないように吸う
- **両方の HashMap を同期して更新**: 片方だけ操作すると `serialEvent` で逆引きが
  ずれて事故る
- **close は `port.stop()` を try で囲む**: 既に切断されたポートを stop しようとすると例外

## ポート列挙の挙動

```java
void refreshPorts(){
  availablePorts = Serial.list();
  ...
}
```

`Serial.list()` は **呼んだ瞬間のスナップショット** を返す。USB を抜き挿しすると
ここに反映されないので、**ユーザーが `r` キーで明示的に再列挙** する設計にした。

「自動で更新したい」なら `setup()` で `Thread` を立てて 1 秒ごとに `Serial.list()` を
監視するのもアリだが、Processing で別スレッド管理を増やすとデバッグが辛くなるので
人力リフレッシュにしている。

## ハマりやすい箇所

### 同じポートを 2 つの Processing が開く

OS が「ポートが busy」エラーを投げる。Processing の Serial は **排他的に開く**。
別ウィンドウが既に開いていないか確認。

### Processing を強制終了するとポートがロックされる

`dispose()` が呼ばれずに死ぬと OS 側のロックが残ることがある。Mac なら `lsof | grep cu.usbmodem`
で誰が握っているか調べ、不要ならそのプロセスを kill。再起動すれば確実。

### USB ハブ越しで `serialEvent` が遅い

セルフパワー USB ハブを使う。バスパワー安物ハブで遅延・取りこぼしが出た事例あり。

### `Serial.list()` に CHIPOPEN や WirelessiAP1 が混ざる

macOS は仮想シリアルポートをいろいろ出す。UI で全部出してしまっているが、間違って
開いても **magic 同期で待ち続けるだけ** で実害なし（バイト列が流れてこないので、
ずっと `inFrame=false` のまま）。

## どこを書き換えるか

| やりたいこと | 触る場所 |
|---|---|
| UDP で受信する（楽器が直接送る） | `serialEvent` を廃止、`UDP.read` ループに置き換え、`packetQueue.offer` の契約は維持 |
| MIDI USB で受信する | Processing の `themidibus` を使い、`triggerNote` を直接呼ぶ。`packetQueue` 経由は不要 |
| 1 ポートだけに固定する | `setup()` の最後で `openPort(Serial.list()[0])` を呼ぶ、UI を全部消す |
| 受信パケットの完全ログを取る | `handlePacket` の冒頭でファイルに 20 B を追記。**Serial スレッドで I/O は重い** ので、追記はキューに別途投げる |
| パケットフォーマットを変える | `PACKET_SIZE` と `handlePacket` のオフセットを書き換え、ファーム側 `OrcProtocol/` も同期して直す |

## 次のページ

- スケッチ全体構造に戻る → [orchestra_resynth.pde の全体構造](/pc-audio/resynth-main/)
- 解析側を読む → [音声解析パイプライン全体](/pc-audio/analyzer-overview/)
- 設計判断の文脈 → [設計の出発点と全体方針](/pc-audio/design/)
