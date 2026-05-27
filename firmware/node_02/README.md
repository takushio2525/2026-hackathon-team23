# node_02

このマイコンは、「かえるのうた」の主旋律1をトランペット音色で担当する楽器ノードです。

## 役割

- 役割: トランペット / 主旋律1（0拍開始）
- 担当者: 未定

## 楽譜データ

- `include/score_data.h`: `kInstrumentId = 0`、`kHeadRestBeats = 0` と `ScoreEvent` を定義
- `src/score_data.cpp`: 32拍の主旋律を保持
- 終盤の半拍音符は `subNote` などの `sub` 系フィールドで表現

## ハードウェア構成

- ボード: 未定（暫定: Arduino Uno R4 WiFi）
- 接続部品: 未定

## ピンアサイン

| ピン | 用途 | 備考 |
|---|---|---|
| - | - | - |

## ビルド・書き込み

VSCode に PlatformIO 拡張を入れた状態で、このディレクトリを開くか、ターミナルで以下を実行する。

```bash
cd firmware/node_02
pio run                 # ビルドのみ
pio run -t upload       # 書き込み
pio device monitor      # シリアルモニタ
```

## 共通ライブラリを使いたくなったら

`firmware/common/lib/` にチーム共通のライブラリを置けるようになっている。
使う場合は `platformio.ini` に次の1行を足す。

```ini
lib_extra_dirs = ../common/lib
```

詳しくは [`firmware/common/README.md`](../common/README.md) を参照。
