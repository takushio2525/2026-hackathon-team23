---
title: PC側の設計判断
description: productionで加算合成、共有タブ、即時発音、UI中継を採用した理由とトレードオフ
sidebar:
  order: 1
---

## 入力として確定しているもの

PCは次の契約を受け入れる側です。

| 与件 | 現行仕様 |
|---|---|
| 楽器ノード | UNO R4 WiFi × 5（node_02〜06） |
| 接続 | 各ノードからUSB Serial、115200 bps |
| NOTE | 20 B、type=3 |
| UI | 20 B、type=4。node_02だけが中継 |
| 編成 | trumpet、horn、trombone、tuba、drum |
| 曲 | 32拍譜面を頭ずらしして56拍の輪唱 |
| PCの発音 | 楽器側が45 ms先読みを解消した後なので、受信後すぐ鳴らす |

PC側で自由に設計できるのは、音色の作り方、音声ライフサイクル、画面、ログです。

## なぜ加算合成か

金管音色には、実録音から抽出した倍音振幅、時間包絡、非調和性、残差ノイズ、
ビブラート、トレモロを保存し、再合成する方式を採用しています。

| 方式 | 利点 | 欠点 | production |
|---|---|---|---|
| 加算合成 | 音高を変えやすい、JSONが小さい、解析結果を説明できる | CPU負荷、過渡音の再現が難しい | 金管4音色 |
| 録音再生 | 過渡音や打楽器に強い | 音高ごとの素材、メモリ | ドラムで優先使用 |
| FM/物理モデル | 表現力 | 音色設計と実装が大きい | 未採用 |
| 外部MIDI音源 | 高品質化が容易 | 外部依存、環境差 | 未採用 |

ドラムを金管と同じ方式だけで処理するのは不利です。そのため現行は、JSON内の
`drum_sample` があれば録音を再生し、無ければ倍音＋白色Noise＋ADSRで合成します。
「打楽器は未実装」ではなく、用途に応じてハイブリッド化されています。

## なぜJSONを境界にするか

`sound_lab/analyzer/` はWAVから特徴量を抽出し、
`pc_app/production/orchestra_resynth/data/` のJSONを作ります。リアルタイムアプリは
WAV解析を行わず、起動時にJSONを読みます。

この分離により次が可能です。

- 重いpyin、STFT、非調和性fitを演奏前に済ませる
- 解析器を変更してもJSON契約を維持すれば合成側を変えない
- 同一`InstrModel`を複数voiceから読み取り専用で共有する
- 音色の差分をテキストとして確認する

ファイル名の昇順が `instrumentId` になるので、先頭番号の変更は通信仕様の変更に相当します。

## なぜProcessing + Minimか

ProcessingはSerial列挙、画面、Javaコレクションを一つのスケッチで扱えます。
MinimはUGenを自作でき、1サンプル単位の加算合成とAudioSample再生を同じ出力へ接続できます。

現行設定:

```java
frameRate(90);
out = minim.getLineOut(Minim.STEREO, 512, 44100);
```

512 samplesは約11.6 msです。小さくすると音声遅延は減りますが、処理が間に合わないと
dropoutします。描画90 fpsのフレーム間隔は約11.1 msで、Serialキューを消費する
最大待ち時間も旧構成より短くしています。

## スレッドを分離する理由

3つの実行主体があります。

| 実行主体 | 責務 | 触る状態 |
|---|---|---|
| Serial callback | magic同期、20 B収集、queue投入 | `PortConn`、`packetQueue` |
| Animation `draw()` | packet解釈、発音指示、voice回収、UI | アプリ全体の可変状態 |
| Minim audio | 1サンプル生成 | 各voice内部 |

Serial callbackから`activeVoices`を変更すると、drawやaudioとの競合が発生します。
そのため完成packetだけを`ConcurrentLinkedQueue<byte[]>`へ渡します。drawが
`handlePacket()`を呼ぶことで、発音開始と画面状態変更を単一スレッドに集約します。

## NOTEを受信後すぐ鳴らす理由

WiFi側のBEATには `playAtMasterMs` がありますが、PCはBEATを直接受けません。
楽器ノードがマスター時計とのoffsetを使って指定時刻まで待ち、その時点でNOTEを
USBへ送ります。PCで再び45 ms待つと二重遅延になります。

したがってPCはNOTEを受信した次のdrawで `patch(out)` します。遅延の主な要素は:

```text
USB転送 + Serial callback + draw待ち最大約11.1 ms + audio buffer最大約11.6 ms
```

OSとAudioデバイスのbufferも加わるため、端から端の値は実機測定が必要です。

## なぜdurationとgateの両方を扱うか

通常のNOTEは `gate=1` と `durationMs` を持ちます。`AudioManager`は
`scheduleOffMs = millis() + max(40, durationMs)` を設定し、時間到達でreleaseします。
これによりNoteOffが失われても音が伸び続けません。

`gate=0` も受け付け、同じ`partId`と移調後MIDI音のvoiceをreleaseします。
ドラムはワンショットなのでgate=0を無視します。

## 金管とドラムを分ける理由

金管は連続音で、release中にもスペクトルと包絡を維持する必要があります。
ドラムは短い過渡音で、MIDI note番号が音色選択になります。

| 管理 | 金管 | ドラム |
|---|---|---|
| class | `ResynthVoice` | `AudioSample` または `DrumNote` |
| 上限 | 24 non-releasing voices | 12 synthesized voices |
| 音色選択 | `instrumentId` 0〜3 | note 36/38/42/49 |
| 終了 | duration → release → done | sample終了または500 ms以上 → release |
| オクターブ | 楽器別に移調 | なし |

同じ`triggerNote()`入口で分岐するため、上流のSerial・protocolは共通です。

## 共有タブに分割した理由

productionだけでなく検証スケッチでも同じprotocol、Serial、audio、UIを使います。
原本を `pc_app/common/` に置き、各スケッチからsymlinkすることで、コピー間の差分を防ぎます。

共有タブはグローバル変数へ依存します。これはProcessingタブが一つのスケッチとして
コンパイルされる性質を利用したものです。再利用は容易ですが、独立Javaライブラリほど
依存が明示的ではありません。各ファイル冒頭の「グローバル依存」を契約として扱います。

## UI状態を別パケットにした理由

PC画面は指揮者の状態を知る必要がありますが、node_01はPCとUSB接続しません。
そこでnode_02が受けたCTRLをUI type=4へ詰め替えて中継します。

- 音楽同期のUDP経路を変えない
- NOTE type=3のoffsetを変えない
- 変化時は最短33 ms、無変化時は1秒heartbeatとし、Serialを圧迫しない
- 画面番号ではなく`state`と`mode`を送り、PCで画面を導出する
- 2秒途絶えたら安全側へ戻して全音停止する

## 変更可能な境界

| 変更 | 影響範囲 |
|---|---|
| UIの色や配置 | `SharedUI`とmainの描画関数 |
| voice stealing | `AudioManager.triggerNote()` |
| 合成方式 | `SynthVoice`と必要なら`InstrModel` |
| 音色解析 | `sound_lab/analyzer/`、JSON契約を維持 |
| Serial以外の入力 | `SerialCore`相当の入口、`handlePacket`契約を維持 |
| パケットoffsetや状態値 | firmwareとPCを同時変更、文書・fixtureも更新 |

次は [信号フロー](/pc-audio/signal-flow/) で実行順を追います。
