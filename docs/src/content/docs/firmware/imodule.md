---
title: IModule と ModuleTimer
description: 全モジュールが継承する抽象基底クラスと、周期判定に使う軽量タイマの内部実装
sidebar:
  label: 共通 — IModule / ModuleTimer
  order: 1
---

:::note[この章で分かること]
- 全モジュールが必ず継承する `IModule` の 4 つの仮想関数の役割
- なぜ `init()` / `updateInput()` / `updateOutput()` / `deinit()` の 4 つに分かれているのか
- `ModuleTimer` が `millis()` のラップアラウンドにどう対処しているか
:::

## 実体

| ファイル | 行数 | 内容 |
|---|---|---|
| `firmware/test_v2/common/lib/ModuleCore/IModule.h` | 28 | 抽象基底クラス |
| `firmware/test_v2/common/lib/ModuleCore/ModuleTimer.h` | 25 | 周期判定タイマ |

両方ともヘッダオンリーで `.cpp` を持たない。テンプレート的に「全コードを見せる」ので、
構造を覚えてしまえばモジュール拡張時に迷わない。

## IModule の全コード

```cpp
struct SystemData;   // 前方宣言 (循環 include 回避)

class IModule {
public:
    bool enabled = true;
    virtual ~IModule() = default;

    virtual bool init()                              { return true; }
    virtual void updateInput(SystemData& data)       { (void)data; }
    virtual void updateOutput(SystemData& data)      { (void)data; }
    virtual void deinit()                            {}
};
```

たった 4 つの仮想関数だけ。`SystemData` は前方宣言で済ませているのがポイント。
`IModule.h` 自体は `SystemData` の **中身を知らなくてよい**（参照を通すだけだから）。
これによって各モジュールは独立してコンパイルでき、`SystemData` の構造を変えても
モジュールヘッダの再コンパイルは要らない。

### 4 つの仮想関数の使い分け

| メソッド | 呼ばれるタイミング | やってよいこと | やってはいけないこと |
|---|---|---|---|
| `init()` | `setup()` の起動シーケンス内で 1 回 | ハードウェア初期化 (Wire / WiFi / pinMode)、`true/false` を返す | `SystemData` のフィールドを書く |
| `updateInput()` | `loop()` の **入力フェーズ** で毎周期 | センサ読み、パケット受信、`SystemData` に書く | 他モジュールを直接呼ぶ、出力 (`Serial.write` 等) |
| `updateOutput()` | `loop()` の **出力フェーズ** で毎周期 | `SystemData` を読んでハード出力に反映 | 入力（センサ読み、パケット受信） |
| `deinit()` | リセットや無効化時（実装は任意） | リソース解放 (`udp_.stop()` 等) | 副作用のある通信 |

### enabled フラグの意味

```cpp
bool enabled = true;
```

これは `main.cpp` の `initWithRetry()` が `init()` 失敗時に false に倒すためのフラグ。

```cpp
void initWithRetry(IModule* m, const char* name) {
    bool ok = false;
    for (size_t i = 0; i < MAX_RETRY && !ok; ++i) {
        ok = m->init();
        if (!ok) delay(50);
    }
    m->enabled = ok;   // ← 失敗時 false。残りのループでスキップされる
}
```

これにより **1 個のモジュールが死んでも他は動き続ける**。たとえば IMU が壊れていても
WiFi / LED / 送信モジュールはそのまま走る。デバッグ時に切り分けがしやすい。

### なぜ純粋仮想ではないのか

`init()` も `updateInput()` も `updateOutput()` も、デフォルト実装が「何もしない」になっている
（純粋仮想 `= 0` ではない）。これは **入力専用 / 出力専用モジュールが片方だけ override で済む** ように
するため。

例えば `ImuModule` は `updateInput()` だけ override する（`updateOutput()` は空のまま）。
逆に `OrcSenderModule` は `updateOutput()` だけ override する。
`OrcNetModule` だけが両方を override する（受信 = 入力、送信 = 出力）。

純粋仮想にすると、入力専用モジュールでも空の `updateOutput()` を書かされてノイズになる。

## ModuleTimer の全コード

```cpp
class ModuleTimer {
public:
    void setTime(uint32_t offsetMs = 0) {
        referenceMs_ = millis() - offsetMs;
    }
    uint32_t getNowTime() const {
        return millis() - referenceMs_;
    }
private:
    uint32_t referenceMs_ = 0;
};
```

これだけ。「ある基準時刻からの経過 ms」を返す。

### 使い方

周期実行の例（`OrcSenderModule` から抜粋）：

```cpp
ModuleTimer ctrlTimer_;

bool init() override {
    ctrlTimer_.setTime();   // 今を 0 にする
    return true;
}

void updateOutput(SystemData& data) override {
    if (ctrlTimer_.getNowTime() >= cfg_.ctrlIntervalMs) {
        ctrlTimer_.setTime();   // 次の周期のために 0 にリセット
        sendCtrl(data);
    }
}
```

`ctrlIntervalMs = 50` なら CTRL は 50 ms ごとに送信される（= 20 Hz）。
`getNowTime()` が経過 ms を返し、しきい値超えたら処理して時計を巻き戻す、というシンプルなパターン。

### `millis()` のラップアラウンド対策

Arduino の `millis()` は `uint32_t` を返すので約 49.7 日でラップアラウンドする。
このクラスは差分計算 `millis() - referenceMs_` でしか時刻を扱わないため、
**符号なし整数の減算が自然にラップアラウンドを吸収する** 性質が効く。

たとえば現在が `0xFFFFFFFE`（ラップ直前）、基準が `0xFFFFFFFC` なら：

```
getNowTime() = 0xFFFFFFFE - 0xFFFFFFFC = 2
```

これは正しい。ラップアラウンドを跨いだ場合も：

```
現在 = 0x00000003 (ラップアラウンド後)
基準 = 0xFFFFFFFE (ラップアラウンド前)
getNowTime() = 0x00000003 - 0xFFFFFFFE = 0x00000005 = 5  ← 正しい
```

**`uint32_t` の引き算は mod 2^32 で計算される** ので、49.7 日跨ぎでも正常に動く。
プロジェクト全体で `now - lastMs >= interval` のパターンを多用しているのは、
これと同じ理由（符号付きにキャストしてはいけない）。

## どのモジュールがどのクラスを継承するか

| モジュール | `IModule` を継承 | `ModuleTimer` を内部使用 |
|---|---|---|
| ImuModule | ✓ | — (`lastSampleMs_` を直接持つ) |
| OrcNetModule | ✓ | — (`lastReconnectMs_` を直接持つ) |
| OrcSenderModule | ✓ | ✓ (`ctrlTimer_`) |
| StatusLedModule | ✓ | — (`lastToggleMs_` を直接持つ) |
| OrcReceiverModule | ✓ | — (周期実行はループ側で制御) |
| NoteSenderModule | ✓ | — (イベント駆動なので時計不要) |

`ModuleTimer` を使うのは `OrcSenderModule` だけ。他は `uint32_t lastXxxMs_` メンバを直接持っている。
**両者の意味は同じ**（基準時刻からの経過 ms 比較）。`ModuleTimer` を使うのは可読性向上のため。

## 落とし穴

- `init()` で `Wire.begin()` を呼ばないこと。I2C は **1 つのバスを複数モジュールで共有** するので、
  バス初期化は `main.cpp` で 1 回だけ行う（指揮者ノードは `setup()` 内で `Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN)` を実行）。
  モジュール側で `Wire.begin()` を呼ぶと、後続モジュールの初期化を上書きしてバスが死ぬ。
- `updateInput()` と `updateOutput()` のどちらに書くか迷ったら、**何を `SystemData` に書くか** で
  判断する。書くなら入力、読むなら出力。両方やりたい場合はモジュールを 2 つに分ける。
- `enabled = false` のモジュールは `updateInput/updateOutput` が呼ばれないが、`SystemData` の
  フィールド自体は残っている。他モジュールが `data.imu.ready == false` のときの分岐を持っていない
  と、無効化されたモジュールの古い値を参照して誤動作することがある。

## 関連ページ

- 拡張する側 → [モジュール拡張ガイド](/deep-dive/module-extension/)
- 各モジュールの実例 → [OrcNetModule](/firmware/orc-net/) / [ImuModule](/firmware/imu-module/) など
- 全体像 → [Embedded-Module-Architecture](/architecture/ema/)
