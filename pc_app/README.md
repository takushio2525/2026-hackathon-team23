# pc_app — PC 側サブシステム

| サブディレクトリ | 目的 |
|---|---|
| [`production/`](production/) | 本番想定の素のテンプレート (Processing スケッチ雛形) |
| [`test/`](test/) | 仕様書準拠のテスト用音再生 (Processing) |

## test 版 (推奨)

`firmware/test/` の楽器ノード (UNO R4 WiFi) から USB Serial で送られる
NOTE パケットを受けて Minim でサイン波合成して鳴らす。

```
pc_app/test/orchestra_player/orchestra_player.pde
```

詳細は [`test/README.md`](test/README.md) を参照。

## production 版

クリーンな Processing スケッチ雛形。各班が音色合成や可視化を自由に書く前提。
