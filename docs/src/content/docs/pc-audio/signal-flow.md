---
title: NOTE 受信から発音までの信号フロー
description: PortConn → packetQueue → drainPackets → triggerNote → ResynthVoice → noteOff → unpatch のタイムラインを実コードベースで追う
sidebar:
  order: 2
---

`orchestra_resynth.pde` で **シリアルからバイトが入って、スピーカーから音が出て、消える**
までのデータが、どのスレッド・どの関数・どの構造体を経由するか。これを把握しておくと、
バグを踏んだとき「どの層で詰まってるか」の切り分けが一気に楽になる。

## 1 枚絵

```
[Arduino UNO R4 WiFi 楽器ノード]
   USB Serial 115200 bps
   20 B/パケット, magic=0x4F52, type=0x03 (NOTE)
        │
        ▼
┌─ Serial スレッド (Processing が起動) ─────────────────────────┐
│  serialEvent(Serial p) が 1 バイトずつ呼ばれる             │
│   ├─ inFrame=false: 'R'(0x52) を待つ → 'O'(0x4F) で同期確定 │
│   └─ inFrame=true:  PortConn.rxBuf に 20 B 貯める           │
│                       └─ 20 B 揃ったら packetQueue.offer    │
│              ※ PortConn は USB ポートごとに 1 個        │
└────────────────────────────────────────────────────────────┘
        │  ConcurrentLinkedQueue<byte[]>
        ▼
┌─ draw() スレッド (60 fps, Animation thread) ───────────────────┐
│  drainPackets():                                            │
│   ├─ handlePacket(buf): version / type チェック             │
│   ├─ type=NOTE のみ: partId/note/vel/dur/instrumentId 抽出  │
│   └─ gate=1 → triggerNote()                                 │
│                                                            │
│  triggerNote():                                            │
│   ├─ InstrModel = modelForId(instrumentId)                 │
│   ├─ MAX_POLYPHONY 超過なら最古 voice を強制 release       │
│   ├─ new ResynthVoice(model, midi, vel, simpleADSR)        │
│   ├─ v.scheduledOffMs = millis() + durationMs              │
│   └─ v.patch(out)   → Minim 側のグラフに接続               │
│                                                            │
│  draw() 末尾:                                               │
│   ├─ now >= scheduledOffMs の voice に noteOff()           │
│   └─ done==true の voice を activeVoices から除去 + unpatch │
└─────────────────────────────────────────────────────────────┘
        │  patch されたボイスは
        ▼
┌─ Audio スレッド (Minim, サンプル単位) ─────────────────────────┐
│  AudioOutput が 1024 サンプルごとに各 UGen の               │
│  uGenerate(float[] channels) を呼ぶ                         │
│  ResynthVoice.uGenerate():                                 │
│   ├─ 倍音ごとに sin(phase) を加算 (40 個まで)              │
│   ├─ 非調和性: f = n·f0·√(1+B·n²) で位相進める            │
│   ├─ ビブラート: pitchMul = 2^(Δcent/1200)                 │
│   ├─ 振幅: ampAt(tSec) = sustainBodyLevel or release       │
│   ├─ ノイズ: noiseTable を循環参照                         │
│   └─ tremolo: 振幅に sin の AM                             │
│                                                            │
│  out.left / out.right に書き出し → サウンドカード          │
└─────────────────────────────────────────────────────────────┘
```

## 各段の責務（読むフィールド・書くフィールド）

| 段 | 関数/場所 | 読む | 書く | スレッド |
|---|---|---|---|---|
| ① 受信 | `serialEvent(Serial)` | USB バイト列 | `PortConn.rxBuf` / `packetQueue` | Serial |
| ② パケット復号 | `drainPackets()` → `handlePacket(byte[])` | `packetQueue` | (一時変数) | Animation (draw) |
| ③ 発音指示 | `triggerNote(...)` | `models[]` / `activeVoices` | `activeVoices` に追加 | Animation |
| ④ ボイス生成 | `new ResynthVoice(...)` | `InstrModel` | 自分の状態 | Animation |
| ⑤ Minim 接続 | `v.patch(out)` | — | Minim 内部のグラフ | Animation |
| ⑥ サンプル生成 | `ResynthVoice.uGenerate(float[])` | 自分の状態 + `m.*` | `channels[]` | Audio |
| ⑦ 自動 NoteOff | `draw()` 末尾 | `now`, `scheduledOffMs` | `releasing=true` | Animation |
| ⑧ ボイス回収 | `it.remove() / v.unpatch(out)` | `done` | `activeVoices` 縮小 | Animation |

スレッドは 3 種類:

- **Serial スレッド**: `serialEvent` が呼ばれる。Voice には絶対触らない（ロック取らないので）
- **Animation スレッド (draw)**: 発音判断と UI 描画。60 fps で回る
- **Audio スレッド**: Minim が内部で持つ。サンプル単位 (1/44100 秒) で `uGenerate` を呼ぶ

スレッド間の橋渡しは:

- Serial → Animation: `ConcurrentLinkedQueue` で **ロックフリーに引き渡す**
- Animation → Audio: `patch(out)` で UGen 接続グラフに参加させる（Minim 内部で同期）

:::caution[ここを破ると壊れる]
**serialEvent 内で発音ロジックを呼ばないこと**。Voice の状態を 2 スレッドから触ると
（特に `activeVoices` の add/remove）NullPointerException や race condition で固まる。
塩澤の最初の実装はこれで音がぶつ切りになった経緯がある。
:::

## タイムライン（典型ケース: durationMs = 300 ms の音符 1 発）

時刻 0 を「楽器ノードがパケットを送信した瞬間」とする。

| t (ms) | 何が起きる | どこ |
|---|---|---|
| 0 | Arduino が `NOTE` 20 B 送信 | `firmware/.../NoteSenderModule.cpp` |
| ≈ 1 | USB Serial で PC 到達、`serialEvent` 開始 | OS / Processing |
| 1〜2 | 20 B 受信完了、packetQueue に enqueue | Serial スレッド |
| ≈ 16 | 次の draw 開始、drainPackets で取り出し | Animation スレッド |
| 16 | `triggerNote` 実行、`ResynthVoice` 生成、`patch(out)` | Animation |
| 16 | `scheduledOffMs = 16 + 300 = 316` を記録 | Animation |
| 16+ε | Audio スレッドが `uGenerate` を呼び始める、発音開始 | Audio |
| 316 | draw で `now >= scheduledOffMs` 検出、`noteOff()` → `releasing=true` | Animation |
| 316〜316+releaseMs | uGenerate が `ampAt` で減衰計算 | Audio |
| 316+releaseMs | `done=true` で draw が `unpatch` + `activeVoices` から除去 | Animation |

**PC が見る遅延は おおむね 1〜18 ms**（USB 1〜2 ms ＋ draw 待ち最大 16.7 ms）。
要件 ≤ 10 ms を満たしたいなら、`frameRate(120)` にして draw 周期を 8 ms に下げると確実。
現状は 60 fps で運用していてヒアリングで違和感は無いレベル。

## パケット欠落と異常系の扱い

### NOTE が来ない（楽器がパケットを落とした / シリアル断線）

- PC 側は受信ループの最後の NOTE からの経過時間を `(millis()-lastNoteAtMs)` ms で表示する
  だけで、特殊処理はしない
- 楽器ノードが復帰して次の BEAT で NOTE を投げ直せば、その瞬間から鳴る（途中参加 OK の設計）

### 同時発音上限の超過

- `MAX_POLYPHONY = 24`。これを超えると `triggerNote()` が **最古の non-releasing ボイスを
  強制 `noteOff()`** してから新規ボイスを作る（`countNonReleasing()` で判定）
- ハッカソン規模（3〜4 声輪唱）では到達しない値。**バグの保険** として置いてある

### gate=0（NoteOff 単独パケット）が来た場合

- test_v2 では gate=1 しか来ない前提だが、互換のため `releaseMatching(partId, noteNumber)`
  で **partId と noteNumber が一致するボイスを全て release** する処理は実装してある
- 将来「ペダルを離すまで伸ばす」など可変長を扱いたくなったときに使える

### Voice が `uGenerate` 中に done になった瞬間

- `done==true` でも uGenerate が最後の 1 ブロック分（1024 サンプル ≈ 23 ms）は `0` を返す
- draw が `unpatch` する前にもう一周 uGenerate が呼ばれることがあるが、`channels[i]=0` を
  返すので無音

## どこを差し替えるか（別実装するときの観点）

| やりたいこと | 触る場所 | 注意 |
|---|---|---|
| 別の UDP/MIDI 受信に切り替える | `serialEvent` を別関数に置き換え、`packetQueue.offer(byte[])` の契約を守る | 20 B のレイアウトは `handlePacket` が依存しているので、パケット復号も差し替えが必要 |
| 加算合成以外で鳴らす | `ResynthVoice` を別 UGen に差し替え、`triggerNote` で `new` する型を変える | `InstrModel` の意味も変わるので JSON フォーマットも要再定義 |
| 同時発音数を増やす | `MAX_POLYPHONY` を上げる | CPU 負荷リニア。Mac M1 で 48 程度まで実用、それ以上は計測してから |
| 自動 NoteOff をやめる（外部 NoteOff に従う） | draw の `now >= scheduledOffMs` 判定を消す | Arduino 側が gate=0 を送るよう要修正 |
| draw 周期を細かくする | `frameRate(120)` を `setup()` で呼ぶ | UI 描画と相談（重い描画があると逆効果） |

## 次のページ

- ここまでの **コードに対応する Processing 全体構造** を見る → [orchestra_resynth.pde の全体構造](/pc-audio/resynth-main/)
- 合成の **数学側** を知りたい → [加算合成ボイス（ResynthVoice）](/pc-audio/resynth-voice/)
- シリアル受信の **マルチポート対応** だけ詳しく見る → [マルチポート同時受信](/pc-audio/serial-handling/)
