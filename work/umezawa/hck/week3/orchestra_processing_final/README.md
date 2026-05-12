# orchestra_processing_final

梅澤担当の Processing 音源サブシステムです。

## 使い方

1. Processing 4 で `orchestra_processing_final.pde` を開く。
2. Minim ライブラリが入っていない場合は、Processing の Library Manager から `Minim` を追加する。
3. 実行後、画面左の Serial 一覧から Arduino のポートをクリックして接続する。

## キー操作

- `1`--`4`: 期待する partId を `0x02`--`0x05` に切り替える
- `a`: 全 partId を受け付ける検証モードに切り替える
- `m`: ミュート切り替え
- `t`: 選択中パートのテスト音
- `g`: 疑似 NOTE フレーム注入
- `r`: Serial ポート再列挙
- `d`: Serial 切断

## NOTE 仕様

- 20 byte 固定長
- little-endian
- `magic = 0x4F52`
- `version = 1`
- `type = 3`
- `partId = 0x02--0x05`
- `durationMs` 経過後に Processing 側で自動消音する
