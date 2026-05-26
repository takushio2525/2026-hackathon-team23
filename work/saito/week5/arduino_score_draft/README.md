# きらきら星 Arduino 楽譜案

計画書 `23plan.pdf` の楽譜データ形式に合わせた、金管4パート用の受け渡し案です。
実機用 `firmware/` を直接変更せず、塩澤担当の楽器ノードへ統合する前にレビュー
できるよう `work/saito/` 配下に置いています。

## 設計との対応

| 計画書の項目 | この案での扱い |
|---|---|
| 楽譜は Arduino のプログラムメモリに埋め込む | `const ScoreEvent kScore[]` として定義 |
| 1イベント = 1拍 | 48拍分を48要素で保持 |
| 音高は MIDI ノート番号 | `C4=60`, `D4=62`, `E4=64`, `F4=65`, `G4=67`, `A4=69` |
| 発音長は `durationQ8` | `256=1拍`, `512=2拍` |
| 休符 | `noteNumber=0`, `flags` の休符ビットを設定 |
| 細分音符 | `sub` 系フィールドを含める。きらきら星では全要素 `0` |
| 輪唱 | 全金管が同じ配列を持ち、`headRestBeats` だけ変える |

課題曲について、計画書本文には「かえるのうた」が記載されていますが、班での
最新決定に従い、この案は「きらきら星」を採用します。

## パート構成

| ノード | `partId` | `headRestBeats` | 役割 |
|---|---:|---:|---|
| `node_02` | `0x02` | `0` | 主旋律 |
| `node_03` | `0x03` | `4` | 第1輪唱 |
| `node_04` | `0x04` | `8` | 第2輪唱 |
| `node_05` | `0x05` | `12` | 第3輪唱 |

ドラムの `node_06` は今回の楽譜作成対象外です。

## ファイル

| ファイル | 内容 |
|---|---|
| `score_data.h` | 計画書準拠の `ScoreEvent` 定義と配列宣言 |
| `score_data.cpp.draft.txt` | きらきら星48拍分の共通楽譜。実機確認前の統合用ドラフト |
| `part_config.md` | `ProjectConfig.h` へ統合する際のパート設定案 |

## 統合時の注意

計画書では `BEAT` の `beatNo` を曲頭からの絶対拍として扱い、受信漏れがあっても
次の拍で正しい楽譜位置へ復帰する設計です。統合側では次の形で楽譜を参照します。

```cpp
const int32_t effective =
    (int32_t)firedBeatNo - 1 - (int32_t)ORC_RECEIVER_CONFIG.headRestBeats;

if (effective >= 0) {
    const uint32_t scoreIndex =
        (uint32_t)effective % (uint32_t)kScoreLength;
    const ScoreEvent& event = kScore[scoreIndex];
}
```

`beatAt` はこの参照計算には使わず、楽譜を読みやすくするための1始まりの拍番号です。
