# 検証用ファームウェア（MOP8: CPU 負荷計測）

production の `main.cpp` に 3 フェーズ（入力・ロジック・出力）の micros() 計測を追加したドロップイン版。
MOP8「入力フェーズの処理時間 ≤ 2ms」の計測に使う。

## ファイル

| ファイル | 対象 | 用途 |
|---|---|---|
| `main_conductor_perf.cpp` | 指揮者 node_01 | `firmware/production/node_01/src/main.cpp` の置き換え |
| `main_instrument_perf.cpp` | 楽器 node_02〜06 | `firmware/production/node_02/src/main.cpp` の置き換え |

## 使い方

```bash
# 1. バックアップ
cp firmware/production/node_02/src/main.cpp firmware/production/node_02/src/main.cpp.bak

# 2. 検証用 main.cpp に差し替え
cp tools/verification/firmware/main_instrument_perf.cpp firmware/production/node_02/src/main.cpp

# 3. SERIAL_DEBUG=1 でビルド・書き込み
#    platformio.ini の build_flags に -DSERIAL_DEBUG=1 を設定してから:
pio run -d firmware/production/node_02 -t upload

# 4. ログ収集 & 解析 (serial_logger.py → analyze.py)

# 5. 復元
mv firmware/production/node_02/src/main.cpp.bak firmware/production/node_02/src/main.cpp
```

## 追加される出力

200ms 間隔で区間内の最大値を出力:

```
[N1 PERF] in=120 logic=45 out=380 total=545
[N2 PERF] in=85 logic=30 out=210 total=325
```

- `in`: 入力フェーズ (updateInput) [μs]
- `logic`: ロジック (applyPattern) [μs]
- `out`: 出力フェーズ (updateOutput) [μs]
- `total`: 3 フェーズ合計 [μs]

## 注意

- production 本体のコードは変更しない。計測が終わったら必ず元に戻す
- `SERIAL_DEBUG=1` ではバイナリ NOTE が止まるため Processing 連携は不可
- 他の MOP 項目（1/3/4/5/6/7/9）は production の `SERIAL_DEBUG=1` のままで計測可能
