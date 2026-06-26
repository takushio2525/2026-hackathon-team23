# kaeru_score_week10_adjusted

week9 の `kaeru_score_debug` をもとにした、week10 用の修正版 Processing スケッチ。

## 変更点

- ドラムパートを 4 分の 4 拍子として整理
  - 1・3 拍目: キック
  - 2・4 拍目: スネア
  - 各声部の入り（0 / 8 / 16 / 24 拍）と最後の拍だけクラッシュ + キックで強調
- チューバは共通譜 C4 基準から 2 オクターブ下（C2 相当）のまま演奏
- 全パートの音量を week9 より大きめに調整
  - `MASTER_GAIN = 1.35`
  - 金管 4 声の各 `amplitude` を増加
  - `DRUM_AMPLITUDE` と `RECORDED_DRUM_GAIN` も増加
- 金管とドラムの聴感上のズレ対策
  - 拍位置は変更しない
  - 金管の `attackSec` だけ `BRASS_ATTACK_SCALE = 0.45` で短くし、立ち上がりを速くする

## 実行方法

Processing 4 で `kaeru_score_week10_adjusted.pde` を開き、Run する。

- `P`: 全パート再生
- `1`〜`4`: 金管各パートを単独再生
- `5`: ドラムを単独再生

音色 JSON はこのフォルダ内の `data/` に同梱しているため、外部フォルダへの参照は不要。
