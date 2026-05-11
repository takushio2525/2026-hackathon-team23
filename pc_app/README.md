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

## 音色の作り込み（関連）

サイン波ではなく本物っぽい音色で鳴らしたい場合は [`../sound_lab/`](../sound_lab/) を参照。
楽器の単音を Python で解析 → インストゥルメント定義(JSON) → Processing で加算合成 + ノイズ + ADSR
で再合成する一連の実験場で、`InstrModel` / `ResynthVoice` をこちらの `orchestra_player` に
移植すれば受信した NOTE をその音色で鳴らせる。
