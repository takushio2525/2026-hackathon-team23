# 金管パート設定案

楽器ノード側の統合時には、主旋律3ノードが同じ `kScore[]` を利用し、
`ProjectConfig.h` 内の `partId` と `headRestBeats` を差分とします。
チューバだけは低音専用の `kScore[]` を利用します。

## 対応表

| ノード | 役割 | 楽譜 | `partId` | `headRestBeats` | `instrumentId` |
|---|---|---|---:|---:|---:|
| `node_02` | トランペット / 主旋律1 | 主旋律 | `0x02` | `0` | `0` |
| `node_03` | ホルン / 主旋律2 | 主旋律 | `0x03` | `8` | `1` |
| `node_04` | トロンボーン / 主旋律3 | 主旋律 | `0x04` | `16` | `2` |
| `node_05` | チューバ / 低音 | 低音 | `0x05` | `0` | `3` |

## `ProjectConfig.h` への反映例

次は `node_03` の場合の設定例です。ほかのノードでは表の値へ差し替えます。
`node_05` のみ、設定値に加えて楽譜配列を低音用に差し替えます。

```cpp
inline const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    /*partId=*/              0x03,
    /*headRestBeats=*/       8,
    /*clockSyncEmaAlpha=*/   0.10f,
    /*clockSyncMinSamples=*/ 5,
    /*loopIntervalMs=*/      5,
};

inline const NoteSenderConfig NOTE_SENDER_CONFIG = {
    /*baudRate=*/     115200,
    /*partId=*/       0x03,
    /*instrumentId=*/ 1,
};
```

`instrumentId` は Processing 側の音色ファイルの並びに合わせ、`0=トランペット`,
`1=ホルン`, `2=トロンボーン`, `3=チューバ` とします。
