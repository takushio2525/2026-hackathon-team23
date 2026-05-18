---
title: pc_app の歩き方
description: orchestra_resynth.pde の setup/draw、シリアル受信、加算合成
sidebar:
  order: 3
---

:::note[この章で分かること]
- Processing スケッチの骨格
- NOTE バイナリの受信パース
- 加算合成と ADSR の仕組み
:::

:::tip[読了目安]
**約 10 分**。前提: Java 風の言語が読めること（Processing は Java ベース）。
:::

このツアーは `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` を扱う。

## Processing スケッチの基本

Processing は `setup()`（起動 1 回）と `draw()`（毎フレーム）の 2 関数構成。
本スケッチもその枠に沿って書かれている。

```
pc_app/test_v2/orchestra_resynth/
├── orchestra_resynth.pde       ← メイン
├── data/
│   ├── 0.json                  ← 楽器番号 0 の音色定義
│   ├── 1.json                  ← 楽器番号 1
│   └── 2.json
└── sketch.properties
```

## 1. 起動: `setup()`

```java
void setup() {
    size(800, 400);             // ウィンドウサイズ
    listSerialPorts();           // 利用可能なシリアルポートを列挙
    openSerial(PORT_INDEX);      // 選択したポートを開く
    loadInstruments();           // data/*.json をロード
    initSynth();                 // 加算合成エンジンを初期化
    initAdsr();                  // ADSR エンベロープを準備
}
```

`PORT_INDEX` は楽器ノードの USB シリアルポート番号。
スケッチ上部の定数を直接編集する（または UI で選択）。

## 2. メインループ: `draw()` と `serialEvent()`

Processing では **シリアル受信は `serialEvent()` が自動で呼ばれる**。
NOTE パケットの組み立てはここで完結する：

```java
void serialEvent(Serial port) {
    while (port.available() > 0) {
        int b = port.read();
        rxBuffer.append(b);
        if (rxBuffer.size() >= 20) {
            parseNotePacket(rxBuffer);
            rxBuffer.clear();
        }
    }
}
```

20 バイトたまったらパースして発音キューに積む。

`draw()` は描画専用：

```java
void draw() {
    background(255);
    drawVisualizer();   // 波形 or 発音状態の可視化
}
```

## 3. NOTE パケットのパース

```java
void parseNotePacket(IntList buf) {
    int magic = buf.get(0) | (buf.get(1) << 8);
    if (magic != 0x4F52) return;         // OR でなければ無視
    int type = buf.get(3);
    if (type != 0x03) return;            // NOTE 以外無視

    int midiNote     = buf.get(12);
    int velocity     = buf.get(13);
    int durationMs   = buf.get(14) | (buf.get(15) << 8);
    int partId       = buf.get(16);
    int instrumentId = buf.get(17);

    triggerNote(midiNote, velocity, durationMs, instrumentId);
}
```

詳しいフィールド意味は [通信プロトコル](/architecture/protocol/) 参照。

## 4. 加算合成: `triggerNote()` → `synthOscillator()`

```java
void triggerNote(int midiNote, int velocity, int durMs, int instId) {
    Instrument inst = instruments[instId];
    Voice v = allocateVoice();
    v.frequency = midiToHz(midiNote);
    v.amp = velocity / 127.0;
    v.duration = durMs / 1000.0;
    v.instrument = inst;
    v.state = ADSR.ATTACK;
}
```

各 `Voice` は次のように音を生成する：

```java
float synthOscillator(Voice v, float t) {
    float sample = 0;
    for (Harmonic h : v.instrument.harmonics) {
        sample += h.amp * sin(2 * PI * v.frequency * h.ratio * t);
    }
    return sample * v.amp * adsrEnvelope(v, t);
}
```

倍音の足し合わせ（加算合成）。
各倍音は基音 × `ratio` の周波数で、`amp` 比で振幅を持つ。

## 5. ADSR エンベロープ

```java
float adsrEnvelope(Voice v, float t) {
    float a = v.instrument.adsr.attack;
    float d = v.instrument.adsr.decay;
    float s = v.instrument.adsr.sustain;
    float r = v.instrument.adsr.release;

    if (t < a) return t / a;                                    // Attack
    if (t < a + d) return 1 - (1 - s) * (t - a) / d;            // Decay
    if (t < v.duration) return s;                                // Sustain
    if (t < v.duration + r) return s * (1 - (t - v.duration)/r);// Release
    v.state = ADSR.OFF;
    return 0;
}
```

これで自然な「立ち上がり → 減衰 → 持続 → 消音」が表現される。

## 6. オーディオ出力

Processing 標準の `Minim` ライブラリ（または `Sound` ライブラリ）でリアルタイム出力：

```java
import ddf.minim.*;
Minim minim;
AudioOutput out;

void setup() {
    minim = new Minim(this);
    out = minim.getLineOut();
}

// 各サンプル時刻で
out.queueSignal(new AudioSignal() {
    public void generate(float[] left, float[] right) {
        for (int i = 0; i < left.length; i++) {
            float s = mixAllVoices(globalTime + i / sampleRate);
            left[i] = s;
            right[i] = s;
        }
    }
});
```

サンプリングレートは 44.1 kHz が一般的。

## 7. 音色 JSON の読み込み

```java
import processing.data.JSONObject;

void loadInstruments() {
    instruments = new Instrument[3];
    for (int i = 0; i < 3; i++) {
        JSONObject json = loadJSONObject("data/" + i + ".json");
        instruments[i] = parseInstrument(json);
    }
}

Instrument parseInstrument(JSONObject json) {
    Instrument inst = new Instrument();
    inst.name = json.getString("name");

    JSONArray harms = json.getJSONArray("harmonics");
    inst.harmonics = new Harmonic[harms.size()];
    for (int i = 0; i < harms.size(); i++) {
        JSONObject h = harms.getJSONObject(i);
        inst.harmonics[i] = new Harmonic(h.getFloat("ratio"), h.getFloat("amp"));
    }

    JSONObject adsr = json.getJSONObject("adsr");
    inst.adsr = new Adsr(adsr.getFloat("attack"), adsr.getFloat("decay"),
                         adsr.getFloat("sustain"), adsr.getFloat("release"));
    return inst;
}
```

配置先は `pc_app/test_v2/orchestra_resynth/data/`。ファイル名そのものが
`<instrumentId>.json` ではなく、**ディレクトリ内をファイル名昇順でソートした配列の
index** が `instrumentId` として参照される（`compareToIgnoreCase` 利用）。
先頭の `0_`, `1_` は人間が並び順を把握するための慣例。実体は
`0_organ.json` / `1_flute.json` / `2_bell.json` / `3_flute_tweaked.json`。

## 複数声部の同時発音

`Voice` プールを用意して、各 NOTE で空きスロットを確保：

```java
Voice[] voices = new Voice[16];   // 16 声同時発音

Voice allocateVoice() {
    for (Voice v : voices) {
        if (v.state == ADSR.OFF) return v;
    }
    // すべて埋まっていたら最古を奪う
    return voices[0];
}
```

16 声あれば 3 声輪唱 + ADSR Release の余韻でも余裕。

## 描画

`draw()` で発音中の `Voice` を可視化：

```java
void drawVisualizer() {
    fill(0);
    text("Active voices: " + countActiveVoices(), 10, 20);

    int x = 50;
    for (Voice v : voices) {
        if (v.state != ADSR.OFF) {
            fill(getColorForInstrument(v.instrument));
            ellipse(x, 200, 30, 30);
            x += 50;
        }
    }
}
```

実際のスケッチでは波形描画 / 楽譜表示など、好みで拡張。

## test_v1 用との違い

`pc_app/test_v1/orchestra_player/` は：

- 倍音 JSON なし、サイン波 1 個だけ
- `instrumentId` 概念なし（全パート同じ音色）
- ADSR は単純な矩形 or 線形フェード

test_v2 のほうが圧倒的にリアルな音だが、コード量は数倍。
**新しく動かすなら test_v2 を使う**。

## 拡張のアイデア

- **エフェクト**: ディレイ / リバーブを後段に挟む
- **エフェクトオートメーション**: 拍に合わせてカットオフを動かす
- **波形録音**: 演奏を `.wav` に書き出す（`Minim.AudioRecorder`）
- **可視化強化**: 周波数スペクトルを描画

## 次に読むべきページ

- 音色 JSON を作る → `sound_lab/README.md`（リポジトリ内）
- バージョン差分 → [test_v1 / test_v2 / production の差分](/code/versions/)
- 困ったら → [よく出るトラブルと対処](/code/troubleshooting/)

### さらに深掘りしたい

- 加算合成 / ADSR / 非調和性 / ボイスプールの実装 → [加算合成エンジン](/deep-dive/additive-synthesis/)
- NOTE パケットのバイトレベル受信 → [バイナリパケット](/deep-dive/binary-packet/)
- **PC アプリと音声解析の実装解剖（塩澤の実装例）**: 設計判断と各クラス・各解析段の中身を 11 ページで深掘り
  → [PC アプリ・音声処理 — 読み順ガイド](/pc-audio/)
  - 設計判断と全体方針 → [設計の出発点と全体方針](/pc-audio/design/)
  - 加算合成ボイスの数学 → [加算合成ボイス（ResynthVoice）](/pc-audio/resynth-voice/)
  - sound_lab の音声解析 → [音声解析パイプライン全体](/pc-audio/analyzer-overview/)
  - 自分で書き直すための判断軸 → [別方針で実装するためのガイド](/pc-audio/extending/)
