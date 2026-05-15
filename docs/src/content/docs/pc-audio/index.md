---
title: PC アプリ・音声処理（塩澤の実装例）
description: orchestra_resynth.pde と sound_lab/analyzer の実コードを題材に、設計判断と差し替えポイントを解説する章
sidebar:
  label: 読み順ガイド
  order: 0
---

:::note[この章で分かること]
- 楽器ノードから来る NOTE バイナリを受け、PC で音にするまでの **設計判断の出発点**
- `pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde` の **構造と内部実装**
- `sound_lab/analyzer/analyzer.py` の **音声解析パイプライン** とそこで使っている手法
- **別方針** で実装し直したいときに、どの部品をどう差し替えればいいか
:::

:::tip[この章の位置づけ]
ここに書いてあるのは **塩澤が一例として組んだ実装** の解剖。「これが唯一の正解」ではない。
**他のメンバーが自分の方針で PC 側を書き直すとき**、どこを参考にしてどこから違う道を選ぶかを
判断するための足場として読んでほしい。
:::

## 全体像

PC 側で起きていることは、ざっくり 3 段階に分かれる。

```
┌─ Arduino UNO R4 WiFi (楽器ノード) ─┐
│  BEAT 受信 → 楽譜参照 → NOTE 送信  │
└────────────────────────────────────┘
                │  USB Serial / 115200 bps / 20 B バイナリパケット
                ▼
┌─ PC: orchestra_resynth.pde ───────────────────────────────────┐
│  ① serialEvent: マルチポート同時受信 → packetQueue          │
│  ② draw 開始: drainPackets → triggerNote()                    │
│  ③ ResynthVoice: 加算合成 (倍音 + ノイズ + 非調和性 + 揺れ)   │
│  ④ Minim AudioOutput → スピーカー                            │
└───────────────────────────────────────────────────────────────┘

┌─ オフライン: sound_lab/analyzer/analyzer.py (Python) ──────────┐
│  WAV → 無音トリム → 基音検出 (pyin) → ADSR 当てはめ          │
│   → 倍音抽出 (FFT + STFT) → 非調和性フィット                  │
│   → 残差ノイズ → ビブラート/トレモロ → JSON 出力              │
└───────────────────────────────────────────────────────────────┘
                │  data/<id>.json
                ▼  (orchestra_resynth.pde の data/ にコピー)
        Processing 側で InstrModel として読み込み
```

実装は大きく 2 つに分かれる:

| 区分 | 場所 | 言語 | 役割 |
|---|---|---|---|
| **リアルタイム再合成** | `pc_app/test_v2/orchestra_resynth/` | Processing 4 (Java) | NOTE を受けてその場で加算合成 |
| **オフライン音声解析** | `sound_lab/analyzer/` | Python (librosa + numpy) | 実楽器の単音録音から音色 JSON を作る |

両者は **JSON 1 ファイルで疎結合**（`sound_lab/library_format.md` がフォーマット仕様）。
解析側を別言語で書き直しても、JSON 仕様さえ守れば再合成側はそのまま動く。

## 読み順（推奨）

### Step 1 — まず設計判断とデータの流れを掴む

| # | ページ | 何が分かるか |
|---|---|---|
| 1 | [設計の出発点と全体方針](/pc-audio/design/) | なぜ加算合成 resynth を選んだか・対案・トレードオフ |
| 2 | [NOTE 受信から発音までの信号フロー](/pc-audio/signal-flow/) | パケット受信→発音→消音までのタイムライン |

### Step 2 — Processing 側の実装を読む

| # | ページ | 何が分かるか |
|---|---|---|
| 3 | [orchestra_resynth.pde の全体構造](/pc-audio/resynth-main/) | setup / draw / UI / キー操作の責務分割 |
| 4 | [加算合成ボイス（ResynthVoice）](/pc-audio/resynth-voice/) | 1 音を作る数式と実装（倍音・揺れ・包絡） |
| 5 | [音色定義モデル（InstrModel）と JSON](/pc-audio/instr-model/) | JSON を配列に展開する手続きと格納するフィールド |
| 6 | [マルチポート同時受信](/pc-audio/serial-handling/) | 複数 USB を 1 つの Processing で扱う仕組み |

### Step 3 — Python 側の音声解析を読む

| # | ページ | 何が分かるか |
|---|---|---|
| 7 | [音声解析パイプライン全体](/pc-audio/analyzer-overview/) | analyzer.py の入出力と処理段の俯瞰 |
| 8 | [倍音抽出・非調和性・残差ノイズ](/pc-audio/analyzer-harmonics/) | FFT と STFT で倍音と残差を分離する数学 |
| 9 | [基音検出・ADSR・ビブラート](/pc-audio/analyzer-modulation/) | pyin、自己相関フォールバック、エンベロープ当てはめ |

### Step 4 — 自分で書き直すための整理

| # | ページ | 何が分かるか |
|---|---|---|
| 10 | [別方針で実装するためのガイド](/pc-audio/extending/) | 解析手法・合成方式・パケットを差し替えるための判断軸 |

## このリポジトリにおける「正解」と「一例」の区別

| カテゴリ | 内容 | 性質 |
|---|---|---|
| **正解（守るべき）** | UDP / シリアル パケットフォーマット（20 B 固定） | これを変えるとファームと PC の両方を直す必要がある |
| 正解 | `data/*.json` のスキーマ（`sound_lab/library_format.md`） | 解析と再合成の境界。バージョン文字列 `sound_lab.instrument/1` で管理 |
| **一例（書き直し可）** | 加算合成 (`ResynthVoice`) | 同じ JSON を読んで別方式（FM・サンプル再生など）で鳴らしてよい |
| 一例 | 音声解析 (`analyzer.py`) | librosa を使った塩澤の一案。手書き FFT・市販プラグイン・別ライブラリでもよい |
| 一例 | Processing で実装 | Web Audio・SuperCollider・openFrameworks・JUCE などへの移植も可 |

この章は **「一例」と書いた箇所を理解して、自分の好む方向に倒すための材料** を集めてある。

## このあとに読むもの

- 加算合成のアルゴリズム解説（数学寄り）は別章にある: [アルゴリズム詳説 — 加算合成エンジン](/deep-dive/additive-synthesis/)
- バイナリパケットの解析側の挙動: [アルゴリズム詳説 — バイナリパケット](/deep-dive/binary-packet/)
- ファームウェア側（楽器ノードがどう NOTE を作るか）: [ファームウェア — NoteSenderModule](/firmware/note-sender/)
