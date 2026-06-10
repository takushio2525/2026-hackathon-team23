# pc_app/test_v3 — ゲームモード対応 Processing アプリ

`firmware/test_v3/` の楽器ノード（Arduino UNO R4 WiFi）から USB Serial で送られてくる
**NOTE パケット**（type=3: 楽器番号 / 高さ / 長さ / 声部 / velocity）と
**UI 状態パケット**（type=4: 指揮者の state/mode/カーソル/目標テンポ/score）を受け、
NOTE は加算合成で発音、UI は画面を**データ駆動で自動判定**して描画する。

```
pc_app/test_v3/orchestra_resynth/orchestra_resynth.pde
```

## test_v2 からの主要変更点

- **役割の手動選択を廃止**: ポートを開くだけで、UI フレーム受信 or NOTE の partId から
  「メイン操作 UI（node_02 接続）」「アナライザ（node_03/04 接続）」を自動判定
- **データ駆動の画面遷移**: 指揮者の `(state, mode)` から毎フレーム画面を再判定する。
  ポート選択 → 待機 → メニュー → 自由演奏 / ゲーム演奏 → 結果、の各画面
- **ゲーム画面**: 目標テンポ・ガイド強度バー・拍進捗・ライブスコアを表示し、
  メトロノームクリック音（ガイド強度に応じてフェードアウト）をローカル生成
- **マスターリセット検知**: UI フレームが `UI_TIMEOUT_MS`（2 秒）途絶えると待機画面へ
  戻し、発音を止めて指揮者の再起動に追従する

## 必要なもの

- [Processing IDE](https://processing.org/download)（4.x）
- Minim ライブラリ（`スケッチ → ライブラリをインポート → ライブラリを追加` から `Minim`）

## ディレクトリ

| パス | 内容 |
|---|---|
| `orchestra_resynth/` | `firmware/test_v3` から届く NOTE / UI パケットを受信して発音・画面表示する本体 Processing スケッチ |

## 実行手順

1. 指揮者ノード（`firmware/test_v3/node_01`）と楽器ノード（`node_02`〜`node_04`）を電源 ON
2. 楽器ノードを Mac に USB 接続する（本番想定は 1 Mac : 1 ノード）
3. Processing IDE で `orchestra_resynth/orchestra_resynth.pde` を開いて Run
4. ポート一覧で繋いだ Arduino のポートをクリックして開く（もう一度クリックで閉じる）
5. 指揮者を振ってモードを選ぶと、PC の画面が自動で追従する
   - node_02 を開いた Mac: メニュー → 演奏/ゲーム画面が出る
   - node_03/04 を開いた Mac: アナライザ画面（波形 + 受信状況）が出る
   - `pio device monitor` を開いているとポートが二重に開けないので閉じておく

### キー操作

- `r`: ポートを全部閉じて再列挙（画面リセット） / `f`: USB ポートのみ表示の切替
- `t`: テスト和音 / `0`〜`3`: その番号の楽器で C4 を 1 発
- `p`: 全パート同一音色モード（`0_trumpets.tweaked.instrument.json`）の ON/OFF
- `a`: 振幅包絡の方式切替（実エンベロープ ↔ ADSR4 値）
- `+` `-`: マスター音量 / `Space`: 全音停止 / `i`: 楽器定義の再スキャン

## パケット仕様（受信, 20 バイト固定, リトルエンディアン）

ヘッダ 12B（magic 0x4F52 / version 0x01 / type / seq / timestampMs）+ ペイロード 8B。

| type | 内容 | ペイロード |
|---|---|---|
| 3 (NOTE) | 発音指示 | partId / noteNumber / velocity / gate / durationMs / instrumentId |
| 4 (UI) | 指揮者状態の中継（node_02 のみ） | state / mode / navCursor / targetBpm / score / partId / bpmQ8 |

- UI の `state`: 0=Idle / 1=Calibrating / 2=Conducting / 3=Fallback / 4=Menu / 5=Result
- `navCursor`/`score` がメニュー値/得点として有効なのは Menu/Result のときだけ
- 詳細は `.agent/api.md` と `firmware/test_v3/common/lib/OrcProtocol/OrcProtocol.h`

## トラブルシュート

- 音が鳴らない → コンソールに `Failed to open` が出ていないか確認。`pio device monitor` を
  閉じる。楽器ノードの `platformio.ini` が `SERIAL_DEBUG=0`（既定）か確認
  （`=1` だとバイナリが流れず人間可読テキストになる）
- メニュー画面が出ない → 開いたポートが node_02 か確認（UI フレームは node_02 だけが
  中継する）。node_03/04 はアナライザ画面になる
- ノイズ / 割れる → `-` キーでマスター音量を下げる（3 声部合算で大きくなりがち）
- 画面が「待機中」のまま → 指揮者の LED が Menu 点滅（約 1.7Hz）になっているか確認。
  Idle 1Hz 点滅のままなら SoftAP 起動失敗、2Hz ならキャリブレーション中
