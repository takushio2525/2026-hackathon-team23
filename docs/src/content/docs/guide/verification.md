---
title: 評価・検証を行う
description: tools/verificationでMOE/MOPを測定する
---

## 検証対象

`tools/verification/`は計画書のMOP 9項目を測定するためのツールです。

| 項目 | 代表的な基準 |
|---|---|
| 拍検出 | 正解率90%以上 |
| 音階 | 平均3.6 cent未満 |
| 楽譜一致 | 誤ノート0 |
| 楽器間同期 | 20 ms以内 |
| 通信遅延 | 30 ms以内 |
| テンポ追従 | 2拍以内 |
| 起動 | 5秒以内 |
| 入力処理 | 2 ms以内 |
| パケットロス | 5%以下 |

## ログ収集

```bash
cd tools/verification
python3 -m pip install -r requirements.txt
python3 scripts/serial_logger.py
```

この測定では楽器を`SERIAL_DEBUG=1`にします。音階測定だけはProcessingで録音するため`0`へ戻します。

## 解析

```bash
python3 scripts/analyze.py logs/test_YYYYMMDD_HHMMSS.log \
  --expected-bpm 120 --test-duration 60
```

USBシリアル受信時刻を使う同期測定には1〜3 ms程度のUSB遅延も含まれます。
厳密な物理測定が必要ならオシロスコープなどを併用します。
