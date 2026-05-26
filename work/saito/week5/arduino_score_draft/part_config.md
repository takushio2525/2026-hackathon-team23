# 金管パート設定案

楽器ノード側の統合時には、同じ `kScore[]` を全金管ノードで利用し、
`ProjectConfig.h` 内の `partId` と `headRestBeats` を差分とします。

## 対応表

| ノード | 役割 | `partId` | `headRestBeats` |
|---|---|---:|---:|
| `node_02` | 主旋律 | `0x02` | `0` |
| `node_03` | 第1輪唱 | `0x03` | `4` |
| `node_04` | 第2輪唱 | `0x04` | `8` |
| `node_05` | 第3輪唱 | `0x05` | `12` |

## `ProjectConfig.h` への反映例

次は `node_03` の場合の設定例です。`node_02`, `node_04`, `node_05` では表の値へ
差し替えます。

```cpp
inline const OrcReceiverConfig ORC_RECEIVER_CONFIG = {
    /*partId=*/              0x03,
    /*headRestBeats=*/       4,
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

`instrumentId` は Processing 側の音色定義との対応で確定する値なので、上記は
金管パートを区別して試験する場合の仮値です。

