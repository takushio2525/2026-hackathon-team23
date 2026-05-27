# processing

梅澤担当の Processing 音源サブシステムです。

Arduino などから送られてくる 20 byte の NOTE フレームを Processing 側で受け取り、Minim を使って音を鳴らします。3つの金管パートと1つのリズムパートを扱う構成です。

## このプログラムでできること

- シリアル通信で NOTE データを受け取る
- `partId` によって担当パートを判定する
- `noteNumber` を音の高さに変換して鳴らす
- `velocity` を音量に変換する
- `durationMs` の時間が過ぎたら自動で音を止める
- 受信状態、エラー数、波形を画面に表示する
- 受信内容を CSV ログとして保存する
- Arduino がなくてもテスト音や疑似 NOTE フレームで動作確認できる
- タイトル画面、ポート選択、モード選択、演奏画面を切り替えられる

## 実行に必要なもの

- Processing 4
- Processing の `Serial` ライブラリ
- Minim ライブラリ
- NOTE フレームを送る Arduino などの外部機器

`Serial` は Processing に標準で入っています。`Minim` が入っていない場合は、Processing の Library Manager から追加してください。

## 使い方

1. Processing 4 を開く。
2. `processing.pde` を開く。
3. `Minim` ライブラリがない場合は、Library Manager から `Minim` をインストールする。
4. 実行ボタンを押す。
5. タイトル画面で `Node1 全体進行` または `Node2-5 演奏ノード` を選ぶ。
6. ポート選択画面で Arduino のポートをクリックする。
7. Node1 の場合は、モード選択画面で `演奏モード` を選ぶ。`ゲームモード` は準備中です。
8. Node2-5 の場合は、接続後にそのまま演奏画面へ進む。
9. Arduino から NOTE フレームが届くと、状態が `再生中` になり音が鳴ります。

Arduino を接続していない場合でも、`t` キーでテスト音、`g` キーで疑似 NOTE フレームを試せます。

## キー操作

| キー | 動作 |
| --- | --- |
| `1` | 受け付けるパートを `Brass 1`、`partId = 0x02` にする |
| `2` | 受け付けるパートを `Brass 2`、`partId = 0x03` にする |
| `3` | 受け付けるパートを `Brass 3`、`partId = 0x04` にする |
| `4` | 受け付けるパートを `Rhythm`、`partId = 0x05` にする |
| `a` | 全パートを受け付けるモードに切り替える |
| `m` | ミュートのオン/オフを切り替える |
| `t` | 現在選択中のパートでテスト音を鳴らす |
| `g` | 現在選択中のパートで疑似 NOTE フレームを作り、受信処理に流す |
| `r` | Serial ポート一覧を更新する |
| `d` | Serial 接続を切断する |

キー操作は演奏画面で使えます。通常の確認では、まず `1` から `4` で確認したいパートを選び、`t` で音が鳴るかを見ると分かりやすいです。複数パートをまとめて受信したいときは `a` を押します。

## 画面の見方

起動すると `タクトーン` のタイトル画面が表示されます。ここで Node の役割を選びます。

ポート選択画面では Serial ポート一覧が表示されます。未接続のときは、ここをクリックして接続します。

Node1 はポート接続後にモード選択画面へ進みます。`演奏モード` は演奏画面へ進み、`ゲームモード` は準備中として表示だけしています。

Node2-5 はポート接続後に演奏画面へ進みます。

演奏画面の `受信ステータス` には、現在の状態が表示されます。

| 表示 | 意味 |
| --- | --- |
| `状態` | ポート選択、待機中、再生中、エラーなどの現在状態 |
| `受信パート` | 今受け付ける予定のパート |
| `ミュート` | ミュート中かどうか |
| `発音数` | 現在鳴っている音の数 |
| `受信` | 正常に受け取った NOTE の数 |
| `破棄` | 捨てた NOTE の数 |
| `パート違い` | 期待したパートと違って捨てた数 |
| `最後のseq` | 最後に受け取ったシーケンス番号 |
| `欠落` | 抜けた可能性があるシーケンス数 |

下側には、現在出力されている音の波形が表示されます。音が鳴っていると線が上下に動きます。

## ファイル構成

Processing では、同じスケッチフォルダにある `.pde` ファイルはまとめて1つのプログラムとして扱われます。このフォルダでは、役割ごとにファイルを分けています。

| ファイル | 役割 |
| --- | --- |
| `processing.pde` | メイン処理。初期化、描画、シリアル受信、キー操作、全体の流れを担当 |
| `P02_ConstantsAndParts.pde` | 通信仕様、パートID、音量、音程変換などの定数をまとめる |
| `P03_NoteProtocol.pde` | 20 byte NOTE フレームを Java/Processing の値に変換する |
| `P04_SerialNoteFrameReader.pde` | シリアルのバイト列から、正しい NOTE フレームを切り出す |
| `P05_SoundPartManager.pde` | NOTE を受け取り、どの種類の音を鳴らすか決める |
| `P06_SoundVoices.pde` | 実際に1つの音を鳴らすクラス群 |
| `P07_ScreenView.pde` | タイトル、ポート選択、モード選択、演奏画面の表示を担当する |
| `P08_EventLogger.pde` | 受信内容やイベントを CSV に保存する |
| `sketch.properties` | Processing のスケッチ設定 |
| `ProgramExplanation.html` | プログラム解説用の HTML |

## 各プログラムの詳しい解説

### `processing.pde`

このスケッチ全体の入口です。

最初に `processing.serial.*`、`ddf.minim.*`、`ddf.minim.ugens.*` を読み込んでいます。`Serial` は Arduino などとの通信、`Minim` は音を鳴らすために使います。

主な変数は次の通りです。

- `minim`: Minim 本体
- `out`: 音を出す出力先
- `serialPort`: 接続中の Serial ポート
- `frameReader`: 受信バイト列を NOTE フレームにまとめる係
- `partManager`: 音を鳴らす係
- `ui`: 画面を描く係
- `logger`: ログを保存する係
- `packetQueue`: 受け取った NOTE を一時的に入れておくキュー

`setup()` は起動時に1回だけ呼ばれます。画面サイズを決め、音声出力を作り、各クラスを初期化し、Serial ポート一覧を取得します。

`draw()` は毎フレーム呼ばれます。背景を塗り直し、受信済み NOTE を処理し、鳴っている音を更新し、最後に UI を描画します。

`serialEvent()` は Serial からデータが届いたときに呼ばれます。届いたバイトを `SerialFrameReader` に渡し、NOTE フレームとして完成したものを `packetQueue` に入れます。

`handlePacket()` は NOTE の中身を確認する場所です。バージョン、タイプ、gate、partId、重複 seq などをチェックして、問題がなければ `partManager.handleNote(packet)` に渡します。

`keyPressed()` には演奏画面で使うキー操作がまとまっています。`1` から `4` のパート切り替え、`a` の全パート受信、`m` のミュート、`t` のテスト音、`g` の疑似 NOTE などはここで処理されます。

### `P02_ConstantsAndParts.pde`

プログラム全体で使う定数をまとめたファイルです。

通信関係では、次の値を定義しています。

- `SERIAL_BAUD = 115200`: Serial 通信速度
- `PROTOCOL_VERSION = 1`: NOTE フレームのバージョン
- `TYPE_NOTE = 3`: NOTE フレームの種類
- `NOTE_FRAME_SIZE = 20`: NOTE フレームの長さ
- `MAGIC = 0x4F52`: フレーム先頭の識別値

パートIDは次の4つです。

| パート | partId |
| --- | --- |
| Brass 1 | `0x02` |
| Brass 2 | `0x03` |
| Brass 3 | `0x04` |
| Rhythm | `0x05` |

音関係では、次の値を定義しています。

- `MAX_VOICES_PER_PART = 4`: 1パートあたり最大4音まで同時に鳴らす
- `MIN_DURATION_MS = 120`: 音の最短長さ
- `DEFAULT_TEST_DURATION_MS = 550`: テスト音の長さ
- `MASTER_GAIN = 0.55`: 全体音量

`partName()` は `partId` を人間が読める名前に変換します。`isKnownPart()` は受け取った `partId` がこのプログラムで扱えるものか確認します。`midiToHz()` は MIDI の音番号を周波数に変換します。

### `P05_SoundPartManager.pde`

音の管理役です。NOTE を受け取り、鳴らす音を作り、鳴り終わった音を消します。

`handleNote()` は、NOTE がオンかオフかを見ます。`gate` が `0`、`velocity` が `0`、または `noteNumber` が `0` の場合は音を止める命令として扱います。それ以外は音を鳴らす命令として扱います。

`noteOn()` では、まず同時発音数を確認し、`velocity` から音量を作り、`durationMs` が短すぎる場合は `MIN_DURATION_MS` まで伸ばします。

そのあと、`partId` によって音の種類を選びます。

- `PART_RHYTHM` の場合: `RhythmVoice`
- それ以外の場合: `BrassVoice`

つまり現在の実装では、`Brass 1`、`Brass 2`、`Brass 3` は同じ金管系の音色を使っています。3つの違いは、基本的には外から送られてくる `noteNumber` や `partId` の違いです。

`playTestNote()` は `t` キーで使われます。リズムパートなら `36`、金管パートなら `60`、`64`、`68` 付近の音を鳴らします。

### `P06_SoundVoices.pde`

1つの音を表すクラスをまとめたファイルです。

基本クラスの `Voice` は、どのパートの何番の音を、どの音量で、どれくらい鳴らすかを持っています。`start()` で開始時刻を記録し、`update()` で時間切れを確認し、`release()` で音を止める準備をします。

`BrassVoice` は金管パート用の音です。`Oscil` で波形を鳴らし、`Line` を使って音量変化を作ります。

金管音の特徴は次の値で決まります。

- `attackMs = 20`: 音が立ち上がる時間
- `decayMs = 40`: 少し音量が落ちる時間
- `releaseMs = 60`: 音を止めるときに小さくなる時間
- `sustain = 0.75`: 鳴り続けるときの音量割合

`RhythmVoice` はリズムパート用の音です。短く鳴ってすぐ消える音になっています。`noteNumber` によって、減衰時間、周波数、波形を変えています。

| noteNumber の範囲 | 周波数 | 波形 | 用途のイメージ |
| --- | --- | --- | --- |
| `37` 以下 | `85 Hz` | `SINE` | 低い打楽器 |
| `38` から `40` | `180 Hz` | `SQUARE` | 中低域の打楽器 |
| `41` から `44` | `900 Hz` | `SAW` | 短い高めの音 |
| `45` 以上 | `520 Hz` | `SAW` | その他のリズム音 |

### `P03_NoteProtocol.pde`

Serial で届いた 20 byte の NOTE フレームを、Processing で扱いやすい `NotePacket` に変換するファイルです。

`NotePacket` には次の値が入ります。

- `version`: プロトコルのバージョン
- `type`: フレームの種類
- `seq`: 何番目のフレームかを表す番号
- `timestampMs`: 送信側の時刻
- `partId`: どのパートか
- `noteNumber`: 音の高さ
- `velocity`: 音の強さ
- `gate`: 音を鳴らすか止めるか
- `durationMs`: 鳴らす長さ

`decodeNote()` は、20 byte の配列からこれらの値を取り出します。`makeNoteFrame()` はテスト用に NOTE フレームを作る関数で、`g` キーの疑似 NOTE フレーム注入に使われます。

### `P04_SerialNoteFrameReader.pde`

Serial 通信では、データが必ず20 byte ぴったりで届くとは限りません。途中から届いたり、余計なバイトが混ざることもあります。

`SerialFrameReader` は、届いたバイトを一度 `buffer` にためます。そして、先頭に `0x52 0x4f` が来る場所を探します。これは `MAGIC = 0x4F52` を little-endian で送ったときの並びです。

正しい先頭が見つかり、20 byte たまったら `decodeNote()` に渡して `NotePacket` にします。

バッファが 512 byte を超えた場合は、古いデータを捨てて `serial buffer overflow` として扱います。

### `P07_ScreenView.pde`

画面表示を担当するファイルです。

`draw()` から次の処理を順番に呼びます。

- `drawHeader()`: タイトルと説明を描く
- `drawPorts()`: Serial ポート一覧を描く
- `drawStatus()`: 状態、受信数、エラー数などを描く
- `drawWaveform()`: 現在の音声波形を描く
- `drawHelp()`: キー操作の説明を描く

Serial ポート一覧のクリック判定もこのファイルにあります。`portIndexAt()` が、マウス位置からどのポートが押されたかを返します。

### `P08_EventLogger.pde`

ログ出力用のファイルです。

起動すると、`processing_log_年月日_時分秒.csv` という名前の CSV ファイルを作ります。NOTE を受け取ったとき、エラーで捨てたとき、Serial に接続したときなどにログを書き込みます。

CSV の列は次の通りです。

```text
millis,event,seq,timestampMs,partId,noteNumber,velocity,gate,durationMs
```

実験中に「NOTE が届いているか」「partId が違っていないか」「seq が飛んでいないか」を確認するのに使えます。

## NOTE フレーム仕様

このプログラムが受け取る NOTE フレームは 20 byte 固定長です。数値は little-endian で送ります。

| byte位置 | サイズ | 名前 | 意味 |
| --- | ---: | --- | --- |
| `0-1` | 2 byte | `magic` | `0x4F52`。NOTE フレームの目印 |
| `2` | 1 byte | `version` | `1` |
| `3` | 1 byte | `type` | `3`。NOTE を表す |
| `4-7` | 4 byte | `seq` | フレーム番号 |
| `8-11` | 4 byte | `timestampMs` | 送信側の時刻 |
| `12` | 1 byte | `partId` | `0x02` から `0x05` |
| `13` | 1 byte | `noteNumber` | MIDI 音番号 |
| `14` | 1 byte | `velocity` | 音の強さ。`0` から `127` |
| `15` | 1 byte | `gate` | `1` で発音、`0` で消音 |
| `16-17` | 2 byte | `durationMs` | 鳴らす長さ |
| `18-19` | 2 byte | reserved | 予約領域。現在は `0` |

## 音が鳴るまでの流れ

1. Arduino などから Serial で byte 列が届く。
2. `serialEvent()` が1 byte ずつ `SerialFrameReader` に渡す。
3. `SerialFrameReader` が 20 byte の NOTE フレームを見つける。
4. `P03_NoteProtocol.pde` の `decodeNote()` が `NotePacket` に変換する。
5. `handlePacket()` が version、type、gate、partId、seq をチェックする。
6. 問題がなければ `PartManager` に渡す。
7. `PartManager` が `BrassVoice` または `RhythmVoice` を作る。
8. `Voice` が Minim の `Oscil` を使って音を鳴らす。
9. `durationMs` が過ぎたら自動で release して音を止める。

## 4つのパートと音の設定場所

4つのパートIDは `P02_ConstantsAndParts.pde` にあります。

```java
final int PART_BRASS_1 = 0x02;
final int PART_BRASS_2 = 0x03;
final int PART_BRASS_3 = 0x04;
final int PART_RHYTHM = 0x05;
```

音色の分岐は `P05_SoundPartManager.pde` の `noteOn()` にあります。

```java
if (partId == PART_RHYTHM) {
  voice = new RhythmVoice(partId, noteNumber, amp, dur);
} else {
  voice = new BrassVoice(partId, noteNumber, amp, dur, brassWaveform);
}
```

このため、現状では3つの金管パートは同じ `BrassVoice` を使います。金管音の波形は `P05_SoundPartManager.pde` の `brassWaveform` で作っています。

金管音の立ち上がりや消え方は `P06_SoundVoices.pde` の `BrassVoice` にあります。リズム音の周波数、波形、短さは `P06_SoundVoices.pde` の `RhythmVoice` にあります。

## よく変更する場所

| やりたいこと | 見るファイル |
| --- | --- |
| Serial 通信速度を変えたい | `P02_ConstantsAndParts.pde` の `SERIAL_BAUD` |
| パートIDを変えたい | `P02_ConstantsAndParts.pde` の `PART_BRASS_1` など |
| 全体音量を変えたい | `P02_ConstantsAndParts.pde` の `MASTER_GAIN` |
| 同時に鳴る音数を変えたい | `P02_ConstantsAndParts.pde` の `MAX_VOICES_PER_PART` |
| 金管の音色を変えたい | `P05_SoundPartManager.pde` の `brassWaveform`、`P06_SoundVoices.pde` の `BrassVoice` |
| リズム音を変えたい | `P06_SoundVoices.pde` の `RhythmVoice` |
| キー操作を増やしたい | `processing.pde` の `keyPressed()` |
| 画面表示を変えたい | `P07_ScreenView.pde` |
| NOTE フレーム仕様を変えたい | `P03_NoteProtocol.pde` と `P02_ConstantsAndParts.pde` |

## トラブルシュート

### 音が鳴らない

- `t` キーでテスト音が鳴るか確認する。
- 鳴らない場合は、PC の音量、Processing の音声出力、Minim のインストールを確認する。
- `m` キーでミュートになっていないか確認する。

### Arduino からの NOTE が反応しない

- 画面左で正しい Serial ポートを選んでいるか確認する。
- `r` キーでポート一覧を更新する。
- Arduino 側の baud rate が `115200` になっているか確認する。
- `partId` が現在の `expected` と一致しているか確認する。
- 複数パートを受けたい場合は `a` キーで全パート受信にする。

### `wrong part` が増える

Processing 側が期待している `partId` と、Arduino から届いている `partId` が違います。

`1` から `4` キーで期待するパートを切り替えるか、`a` キーで全パートを受け付けるモードにしてください。

### `missing` が増える

`seq` の番号が飛んでいます。Serial 通信の途中でフレームが抜けた可能性があります。Arduino 側の送信間隔、通信速度、フレーム生成処理を確認してください。

### `serial buffer overflow` が出る

受信バッファにデータがたまりすぎています。送信が速すぎる、フレームの形式が間違っていて先頭を見つけられない、などが原因です。

## 読む順番のおすすめ

初めて読む場合は、次の順番が分かりやすいです。

1. `README.md` の使い方と全体像
2. `P02_ConstantsAndParts.pde` で定数とパートIDを見る
3. `processing.pde` で全体の流れを見る
4. `P03_NoteProtocol.pde` で NOTE フレームの中身を見る
5. `P04_SerialNoteFrameReader.pde` で受信処理を見る
6. `P05_SoundPartManager.pde` で音色の分岐を見る
7. `P06_SoundVoices.pde` で実際の音の作り方を見る
8. `P07_ScreenView.pde` と `P08_EventLogger.pde` で表示とログを見る
