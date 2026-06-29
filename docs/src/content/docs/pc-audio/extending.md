---
title: 別方針で実装するためのガイド
description: 現行実装を踏まえつつ、PC側を書き直すときの判断軸とチェックリスト
sidebar:
  order: 10
---

ここまでに解説した `orchestra_resynth.pde` と `sound_lab/analyzer/` は **現行の実装例**。
他のメンバーが別のアプローチで PC 側を作るときに「**どこを変えていいか / どこを変えると
連鎖的に壊れるか**」を整理する。

## 不変条件（変えると全部やり直し）

次の 2 つは **ファーム側と PC 側で対称的に決まっている**。片方を動かすなら両方同時に直す。

### 1. シリアルパケットフォーマット（20 B 固定）

ヘッダ 12 B ＋ ペイロード 8 B、`magic=0x4F52`、type=NOTE で `instrumentId` を含む。
- 詳細: [通信プロトコル](/system/protocol/) / [バイナリパケット](/deep-dive/binary-packet/)
- 触る場所（PC）: `handlePacket()` のオフセット
- 触る場所（ファーム）: `firmware/production/common/lib/OrcProtocol/`

### 2. 同期戦略（マスタクロック・先読み・冗長送信）

PC 側には直接届かない（楽器が時刻合わせ済みで NOTE を出してくる）が、これに依存して
「PC は受信即発音でいい」設計になっている。
- 詳細: [時刻同期メカニズム](/deep-dive/time-sync/)
- もし PC 側で時刻補正をしたいなら、CTRL/BEAT も PC に流すよう **ファーム側を変える** 必要がある

## 半不変（バージョンを上げれば変えていい）

### JSON フォーマット (`sound_lab.instrument/1`)

解析側と再合成側の **境界**。バージョン文字列でぶら下げ管理。

- 変更手順: `format` を `/2` に上げ、解析側で新規生成、`InstrModel` のコンストラクタを
  バージョン分岐
- 旧バージョンの JSON もしばらく動かす（バージョン共存期間を 1〜2 週間置く）

詳細: [音色定義モデルと JSON](/pc-audio/instr-model/)

## 自由に変えていい（一例だから）

### A. 合成方式

現行は **加算合成 (resynth)** を選んでいるが、別案として:

| 方式 | 向き不向き | 必要な変更 |
|---|---|---|
| **サンプル再生** | 打楽器・大規模音源・既製音源 | `InstrModel` を「波形バッファ + ピッチシフト係数」に。`ResynthVoice.uGenerate` をテーブル読み出しに |
| **FM 合成** | 金属音・電子音・古典 DX 風 | 倍音ループを `sin(carrier + I·sin(modulator))` に。JSON に carrier/modulator/I を追加 |
| **物理モデリング** | リアルな擦弦・吹奏 | Voice を完全に別クラス、Karplus-Strong 等のアルゴリズムを実装 |
| **ウェーブテーブル** | 中間。倍音解析を経由しない | `InstrModel.noiseTable` のように 1 周期テーブルを持ち、ピッチで読み出し速度を変える |

**変えない部分**: パケット受信、`triggerNote` の入口、`MAX_POLYPHONY` 管理。
**変える部分**: `InstrModel` と Voice クラス、JSON フォーマット（必要なら）。

### B. 解析手法

現行は **Python + librosa** で書いているが、別案として:

| 手法 | 向き不向き | 必要な変更 |
|---|---|---|
| **C++ + FFTW** | リアルタイム解析もしたい場合 | パイプライン全体を移植、JSON を維持 |
| **Web Audio + AnalyserNode** | ブラウザで完結したい | pyin に相当する基音検出は別途実装（YIN 等） |
| **MATLAB / Octave** | プロトタイプ用 | 関数を 1 対 1 で書き直し、JSON 出力 |
| **既存プラグイン** (SPEAR / Audacity の Vamp) | 既製品の力を借りる | 出力 CSV を JSON 変換するスクリプト |

**変えない部分**: JSON フォーマット、解析パイプラインの段の順序。
**変える部分**: 各段の中身の実装言語。

### C. UI / プラットフォーム

現行は **Processing 4** を選んでいるが、別案として:

| 環境 | 向き不向き | 必要な変更 |
|---|---|---|
| **JUCE (C++)** | プロ志向、AU/VST 化 | UI と Voice を全部書き直し、シリアルは Boost / system call |
| **openFrameworks** | C++、ofSerial 使えば近い構造 | Processing → C++ への移植 |
| **Web Audio + Web Serial** | ブラウザで動く | Chrome 限定、Minim 相当の合成エンジンを実装 |
| **SuperCollider** | 合成は最強、UI は別途 | OSC で SC に NOTE を投げるブリッジを Processing で書く |
| **Max/MSP** | リアルタイム DSP 玄人向け | パッチング、シリアル受信は `serial` オブジェクト |

**変えない部分**: シリアル経由でパケットを受ける、`triggerNote` 相当の発音指示。
**変える部分**: それ以外全部。

### D. 同時発音管理

現行は **古いvoiceからrelease** しているが、別案として:

| 方針 | 向き不向き |
|---|---|
| **音量が小さい順に切る** | 自然に聞こえる、計算少し増える |
| **同 partId の先発を切る** | 楽器 1 台 1 声に縛る（輪唱に不向き） |
| **動的にプール拡大** | プチノイズを許容する代わりに切らない |
| **release 中も含めて上限管理** | 残響を犠牲にして CPU を守る |

触る場所: `triggerNote()` の `while (countNonReleasing() >= MAX_POLYPHONY)` ループ。

## チェックリスト — 別実装を始める前に

以下を **着手前** に答えておくと、実装中の方向転換を減らせる。

### パケット受信

- [ ] シリアル？ それとも UDP / MIDI / OSC？
- [ ] 受信スレッドで音を作らない（=ジッタ対策）構造を設計したか？
- [ ] バッファサイズと遅延のトレードオフを決めたか？
- [ ] 不正パケット・version mismatch・magic 不一致への対処を決めたか？

### 音色データ

- [ ] 楽器番号と音色の対応表をどう持つか（JSON / SQLite / ハードコード）？
- [ ] 音色を実行時に切り替える必要があるか（あれば再ロード機構が要る）？
- [ ] 同一音色を複数 Voice で共有するときに read-only を強制できるか？

### 合成エンジン

- [ ] サンプル単位 / バッファ単位どちらで処理する？
- [ ] 同時発音上限は何にする？ CPU 予算は？
- [ ] エンベロープは実曲線 / ADSR どちら？
- [ ] ピッチベンド・ビブラートをサポートするか？

### NoteOff の決め方

- [ ] パケットで明示？ それとも durationMs から自動？
- [ ] release 時間は楽器ごと？ それとも固定？
- [ ] パケットが落ちたとき音が伸びっぱなしにならない保険があるか？

### UI（必要なら）

- [ ] 何を可視化する？（波形・スペクトル・発音中ボイス・受信状況）
- [ ] ヘッドレスでも動くべきか？
- [ ] テスト音（Arduino なしで音を出す）の出し方は？

### 解析（オフラインなら）

- [ ] 解析の出力フォーマットを確定したか（JSON / バイナリ / 既存規格）？
- [ ] バージョン管理の仕組みはあるか？
- [ ] 解析の所要時間と、ブラウザ UI/CLI の選択は？

## よくある落とし穴

| 落とし穴 | 症状 | 対処 |
|---|---|---|
| serialEvent から Voice を触る | 音がブツ切り・たまにクラッシュ | キュー経由で Animation スレッドへ |
| MidiNote → Hz の式を間違える | 半音単位でずれた音が鳴る | `f = 440 · 2^((midi-69)/12)` を厳守 |
| ナイキスト超の倍音を生成 | 高音域でエイリアシング | `if (f >= sr/2) continue` を必ず入れる |
| 倍音の正規化を忘れる | 音がクリップして歪む | `harmNorm = 1/Σamp` を `uGenerate` で掛ける |
| `release` 中に loop 進める | 音色が release 中に変わる違和感 | `releaseHoldWarpT` を固定する |
| Processing で `font` を `createFont(...)` の毎フレーム呼ぶ | フリーズ・メモリリーク | `setup()` で 1 度だけロード |
| pyin の `fmin/fmax` を広く取り過ぎ | オクターブエラー多発 | 楽器の音域 + 安全マージン程度に絞る |
| 解析の `MAX_HARMONICS` を 100 等に上げる | JSON が肥大 | 40 で実用十分、聴感差はほぼ無い |

## 既存実装をベースに改造するときの推奨手順

1. **複製してフォークする**: `pc_app/production/` をコピーして `pc_app/test_v3_<your_name>/`
   を作る。本家を壊さない
2. **小さく動かす**: まずproductionをそのまま走らせて音を確認
3. **境界を 1 つだけ動かす**: 例えば「合成だけ FM に」「解析だけ別ライブラリに」と
   **1 軸ずつ** 変える。同時に複数変えると失敗時に切り分けられない
4. **JSON フォーマットを最後に動かす**: フォーマットを変える必要が出てきても、
   一旦は互換を維持しながら新フィールドを追加する形にする
5. **比較できる状態を残す**: 同じNOTEでproductionと変更版を切り替えられるようにしておくと、
   発表時に比較デモができる

## 参考リンク

### このリポジトリ内
- 設計の出発点 → [設計の出発点と全体方針](/pc-audio/design/)
- ファーム側 NOTE 生成 → [ファームウェア — NoteSenderModule](/firmware/note-sender/)
- 加算合成のアルゴリズム解説 → [アルゴリズム詳説 — 加算合成エンジン](/deep-dive/additive-synthesis/)
- UDP マルチキャスト → [アルゴリズム詳説 — UDP マルチキャスト](/deep-dive/udp-multicast/)

### 外部リファレンス
- librosa: <https://librosa.org/>
- Minim (Processing): <https://code.compartmental.net/minim/>
- pYIN: Mauch & Dixon (2014) "pYIN: A Fundamental Frequency Estimator Using Probabilistic Threshold Distributions"
- 加算合成の教科書: Roads, *The Computer Music Tutorial* (MIT Press, 1996) 第 2 章
- 非調和性: Fletcher, *The Physics of Musical Instruments* (Springer, 1998) 第 12 章

## この章の終わり

この章では、PC側の現行実装と、自分で書き直すための判断材料を一通り示した。
**手を動かす前にどこを動かすか決めれば、迷子にならずに済む**。

変更後は同じNOTE入力でproductionと比較し、音、遅延、CPU使用率、画面状態を確認する。
