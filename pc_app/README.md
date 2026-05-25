# pc_app — PC 側サブシステム

| サブディレクトリ | 目的 |
|---|---|
| [`production/`](production/) | 本番想定の素のテンプレート（Processing スケッチ雛形）|
| [`test_v1/`](test_v1/) | `firmware/test_v1/` の楽器ノードからの NOTE を Minim でサイン波合成して鳴らす（旧 `pc_app/test`）。1 楽器 = 1 Mac = 1 Processing |
| [`test_v2/`](test_v2/) | `firmware/test_v2/`（きらきら星 輪唱）の NOTE を、sound_lab の楽器定義（`data/*.json`）で加算合成して鳴らす。**PC アプリ 1 個で複数シリアルポートを同時に開ける** |

**新しく動かすなら `test_v2/` を使う。**

## test_v2（推奨）

```
pc_app/test_v2/orchestra_resynth/orchestra_resynth.pde
```

`firmware/test_v2/` の楽器ノード（UNO R4 WiFi）から USB Serial で送られる NOTE パケット
（**楽器番号 / 高さ / 長さ / 声部 / velocity**）を受け、`data/*.json`（sound_lab の楽器定義）を
番号で選んでポリフォニックに加算合成する（倍音加算 + 非調和性 + スペクトル整形ノイズ + 全体
エンベロープ + ビブラート/トレモロ — `instrument_player` と同じ合成方式）。画面下のポート一覧を
クリックして複数ポートを同時に開けるので、テスト時は 1 Mac に複数ノードを挿してもよい。

詳細は [`test_v2/README.md`](test_v2/README.md) を参照。

## test_v1

`firmware/test_v1/` の楽器ノードからの NOTE を Minim のサイン波で鳴らす最小実装。
複数ノードを鳴らすときは Mac と Processing インスタンスをノードごとに用意する（1 楽器 = 1 Mac）。
詳細は [`test_v1/README.md`](test_v1/README.md) を参照。

## production 版

クリーンな Processing スケッチ雛形。各班が音色合成や可視化を自由に書く前提。

## 音色の作り込み（関連）

楽器の単音から音色定義（JSON）を作るツールは [`../sound_lab/`](../sound_lab/) を参照。
`test_v2/orchestra_resynth` の `data/*.json` も sound_lab の出力フォーマット
（[`../sound_lab/library_format.md`](../sound_lab/library_format.md)）。`InstrModel` / `ResynthVoice` は
`sound_lab/processing/instrument_player` から移植している。
