# firmware/test_v2 — きらきら星の輪唱 + 楽器番号付き NOTE

`firmware/test`（現 `firmware/test_v1`）の続編。**指揮者 1 + 楽器 3** の 4 ノード構成は
そのままに、次の点を変えた版：

- **楽譜は「きらきら星」全曲**を Arduino に内蔵（`node_02/03/04/src/score_data.cpp`）
- **3 声部の輪唱（カノン）**：node_02 が先頭から、node_03 は 8 拍遅れ、node_04 は 16 拍遅れで
  入る。「頭に休符を入れてずらす」方式で、各ノードの `headRestBeats`（ProjectConfig.h）で決まる
- **NOTE パケットに `instrumentId`（楽器番号）を追加**。各ノードが自分の声部に対応する楽器番号
  （node_02→0 / node_03→1 / node_04→2）を送る。PC 側（`pc_app/test_v2/orchestra_resynth`）は
  この番号で `data/*.json`（sound_lab の楽器定義）を選んで加算合成する
- **PC アプリは 1 個**：本番は 1 Mac : 1 ノード（1 声部）の想定だが、テスト用に
  「1 Mac に複数ノードを USB 接続 → orchestra_resynth で複数シリアルポートを同時に開く」もできる
- **初期テンポ 100 BPM**：最初の 1 音（最初の拍）は 100 BPM で送り、2 拍目で「1→2 拍目の間隔」を
  そのまま簡易テンポとして確定、以降は拍ごとに EMA で随時補正（`node_01/src/applyPattern.cpp`）
- **拍番号駆動**：楽器ノードは指揮者の拍番号から自分の楽譜位置を計算するので、PC 側
  Processing をいつ起動しても「曲の現在位置」から鳴り始める（途中参加 OK）

| ディレクトリ | 内容 |
|---|---|
| [`common/`](common/) | 全ノード共通ライブラリ（`OrcProtocol` / `OrcNetModule` / `StatusLedModule` / `ModuleCore`）。`OrcProtocol` の `NotePayload` に `instrumentId` が増えている |
| [`node_01/`](node_01/) | 指揮者ノード（XIAO ESP32-S3 Sense + GY-521）。初期テンポ 100 BPM |
| [`node_02/`](node_02/) | 輪唱 声部 1（partId=0x02, headRestBeats=0, instrumentId=0） |
| [`node_03/`](node_03/) | 輪唱 声部 2（partId=0x03, headRestBeats=8, instrumentId=1） |
| [`node_04/`](node_04/) | 輪唱 声部 3（partId=0x04, headRestBeats=16, instrumentId=2） |

声部の楽譜（`score_data.cpp`）は 3 台とも同一（= 輪唱）。差分は ProjectConfig.h だけ。

## クイックスタート

```bash
# 1. 指揮者ノードを書き込む
pio run -d firmware/test_v2/node_01 -t upload

# 2. 楽器ノードを書き込む (本番は 1 ノード = 1 Mac。テストは 1 Mac に複数挿してもよい)
pio run -d firmware/test_v2/node_02 -t upload   # 声部 1
pio run -d firmware/test_v2/node_03 -t upload   # 声部 2
pio run -d firmware/test_v2/node_04 -t upload   # 声部 3

# 3. Mac で Processing を起動し pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde を Run
#    画面下の「シリアルポート」一覧で、繋いだ Arduino のポートをクリックして開く
#    (複数ノードを同じ Mac に挿しているなら、それぞれのポートをクリックして全部開く)
```

まずは node_02 だけ 1 台で動作確認するのが安全。鳴ったら node_03 / 04 を順に足す。
node_02/03/04 の `platformio.ini` は既定で `SERIAL_DEBUG=0`（= バイナリ NOTE を Serial に流す）。
ファーム自体の挙動を `pio device monitor` で読みたいときだけ `SERIAL_DEBUG=1` にする
（その間は Processing には音が来ない）。

## 起動順

1. 楽器ノード（node_02 / 03 / 04）を電源 ON → `Idle`（LED 1 Hz 点滅）
2. 指揮者ノード（node_01）を電源 ON → SoftAP 起動 → `Calibrating`（2 Hz 点滅, 2 秒）→ `Conducting`（点灯）
3. 各楽器ノードが SoftAP 接続 → `WaitStart`（2 Hz）→ 指揮棒を振って初回 BEAT 到来で `Playing`（点灯）
4. node_02 はすぐ「きらきら星」を弾き始める。node_03 は 8 拍後、node_04 は 16 拍後に入って輪唱になる
   （それまでは `Playing` だが休符＝無音）

## マスタクロック方式（test_v1 から踏襲）

指揮者の `millis()` をマスタ時刻として全ノードで共有する。BEAT は「マスタ時刻
`playAtMasterMs` に発音せよ」という未来時刻指定で送り、楽器側は CTRL/BEAT 受信時に offset を EMA で
学習し、`masterNow = millis() + offset` が `playAtMasterMs` に到達した瞬間に楽譜を 1 拍進める。
楽譜の進み具合は指揮者の拍番号で決まるので、何拍目から鳴り始めても（= PC を途中起動しても）
正しい位置から再生される。

## 詳細

- 楽譜・輪唱の仕組み：`node_02/src/score_data.cpp`, `node_02/src/applyPattern.cpp`
- 楽器番号（プロトコル）：`common/lib/OrcProtocol/OrcProtocol.h` の `NotePayload`
- 初期テンポ：`node_01/src/applyPattern.cpp`, `node_01/include/SystemData.h`
- PC 側の合成・複数ポート：`pc_app/test_v2/orchestra_resynth/`
- 楽器定義 JSON のフォーマット：`sound_lab/library_format.md`
