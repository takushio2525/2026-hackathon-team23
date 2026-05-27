# かえるのうた Arduino 楽譜案

計画書 `23plan.pdf` の楽譜データ形式に合わせた、金管4パート用の受け渡し案です。
実機用 `firmware/` を直接変更せず、塩澤担当の楽器ノードへ統合する前にレビュー
できるよう `work/saito/` 配下に置いています。

## 設計との対応

| 計画書の項目 | この案での扱い |
|---|---|
| 楽譜は Arduino のプログラムメモリに埋め込む | `const ScoreEvent kScore[]` として定義 |
| 1イベント = 1拍 | 主旋律は32拍、低音は40拍を各拍スロットで保持 |
| 音高は MIDI ノート番号 | 主旋律は `C4=60`〜`A4=69`、低音は `F2=41`, `G2=43`, `C3=48` |
| 発音長は `durationQ8` | `128=半拍`, `256=1拍`, `512=2拍`, `1024=4拍` |
| 休符 | `noteNumber=0`, `flags` の休符ビットを設定 |
| 細分音符 | 主旋律終盤の半拍音符を `sub` 系フィールドで表現 |
| 輪唱 | 主旋律3台は同じ配列を持ち、`headRestBeats` だけ変える |
| 低音 | チューバだけ `C3`, `F2`, `G2` の40拍低音配列を持ち、ホルンの終了まで和声を支える |

課題曲は「かえるのうた」とし、トランペット、ホルン、トロンボーンが輪唱の
主旋律を担当し、チューバが低音伴奏を担当します。

## パート構成

| ノード | `partId` | `headRestBeats` | 役割 |
|---|---:|---:|---|
| `node_02` | `0x02` | `0` | トランペット / 主旋律1 |
| `node_03` | `0x03` | `8` | ホルン / 主旋律2 |
| `node_04` | `0x04` | `16` | トロンボーン / 主旋律3 |
| `node_05` | `0x05` | `0` | チューバ / 低音伴奏 |

## ファイル

| ファイル | 内容 |
|---|---|
| `score_data.h` | 計画書準拠の `ScoreEvent` 定義と配列宣言 |
| `score_data.cpp.draft.txt` | かえるのうた32拍分の主旋律。`node_02`〜`node_04` 用ドラフト |
| `bass_score_data.cpp.draft.txt` | かえるのうた40拍分のチューバ低音。`node_05` 用ドラフト |
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
主旋律担当ノードには `score_data.cpp.draft.txt`、チューバ担当ノードには
`bass_score_data.cpp.draft.txt` を `score_data.cpp` として統合します。
