# 8. ファイル構成

`firmware/` 配下は **「共通層」と「ノード別プロジェクト」** の 2 段構造にする。
EMA 準拠で、PlatformIO の `lib_extra_dirs` を使って共通層を全ノードから参照する。

```text
firmware/
├── README.md
├── common/
│   ├── README.md
│   └── lib/
│       ├── IModule/              # 基底 I/F（IModule.h のみ）
│       ├── ModuleTimer/          # 非ブロッキング周期管理
│       ├── OrcProtocol/          # CTRL / BEAT / NOTE のパケット定義
│       └── OrcNet/               # WiFi 接続と UDP 送受信ラッパ
├── node_01/                      # 指揮者
│   ├── platformio.ini            # lib_extra_dirs = ../common/lib
│   ├── src/
│   │   ├── main.cpp              # 3 フェーズループ、モジュール登録
│   │   ├── SystemData.h          # node_01 内で共有する状態
│   │   └── ProjectConfig.h       # ピン・ポート・閾値など
│   └── lib/
│       ├── ImuDriver/            # F1.1 IMU 読み取り
│       ├── SignalFilter/         # F1.2 前処理
│       ├── BeatDetector/         # F1.3 拍検出
│       ├── TempoEstimator/       # F1.4 テンポ推定
│       ├── VelocityEstimator/    # F1.5 強弱推定（ストレッチ、初期はスタブ）
│       └── ConductorSender/      # F2.1/F2.2 CTRL / BEAT 送出
├── node_02/                      # 楽器 A
│   ├── platformio.ini
│   ├── src/
│   │   ├── main.cpp
│   │   ├── SystemData.h
│   │   ├── ProjectConfig.h       # part_id = A
│   │   └── score_data.h          # パート A の楽譜データ
│   └── lib/
│       ├── CtrlReceiver/         # F3.1 CTRL / BEAT 受信
│       ├── ScorePlayer/          # F3.2/F3.3 楽譜保持と進行
│       └── NoteSender/           # F4.1/F4.2 NOTE 送出
├── node_03/                      # 楽器 B (同構造、ProjectConfig と score_data.h が差分)
├── node_04/                      # 楽器 C
└── node_05/                      # 楽器 D
```

- node_02〜05 は **構造コピー** で、差分は `ProjectConfig.h`（part_id、UDP 宛先）と
  `score_data.h`（パート別楽譜）のみ。
- 楽器 4 台分の `CtrlReceiver` / `ScorePlayer` / `NoteSender` は **common 側に昇格させず**
  各ノードの `lib/` に置く（実装ごく初期は差分がなくとも、楽器個別のカスタマイズ余地を
  残す運用とする）。ただし重複が無意味と判明した時点で common へ昇格させてよい。
- `test/`（PlatformIO の単体テスト）は共通層のみ整備し、ノード側は最小限に留める
  （第 13.1 章参照）。
