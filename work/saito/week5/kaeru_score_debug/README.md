# かえるのうた 楽譜デバッグ版

Arduino に組み込む前に、金管3声の輪唱、低音伴奏、ドラム伴奏、
解析済み音色を Processing 上で確認するための仮スケッチです。

## 前提

| 項目 | 内容 |
|---|---|
| 曲 | かえるのうた（ハ長調） |
| テンポ | 固定 96 BPM |
| パート | トランペット / ホルン / トロンボーン（主旋律の輪唱）、チューバ（低音伴奏）、ドラム（リズム伴奏） |
| 入り拍 | 主旋律 = 0 / 8 / 16 拍、低音・ドラム = 0 拍 |
| 楽譜形式 | Arduino の `ScoreEvent` に合わせた形式 |
| 音色 | `data/` に置いた解析 JSON を Processing 側で読み込む |

`ScoreEvent` は `beatAt`, `noteNumber`, `velocity`, `durationQ8`, `flags` に加え、
計画書にある細分音符用の `subNote`, `subVelocity`, `subOffsetQ8`,
`subDurationQ8` を持ちます。最後の「ドドレレミミファファ」の半拍音符では
`sub` 系フィールドを使用します。ドラムでは `subOffsetQ8 = 0` として、
キックまたはスネアと同じ拍頭にハイハット／シンバルを重ねます。
`durationQ8` は `256 = 1拍`、`noteNumber = 0` と `flags = REST` は休符です。
伸ばす音の後ろには休符スロットを置き、Arduino で `beatNo` から位置を求める
場合にも拍位置がずれないようにしています。チューバの低音は `C3`, `F2`, `G2` の
長音で輪唱を支え、終止部分は `G2` から `C3` へ進めて着地させます。
低音は40拍まで演奏し、8拍遅れて始まるホルンと同じ時点で終了します。

ドラムは最後に入るトロンボーンが終止するまでの48拍を演奏します。
各拍にクローズドハイハットを置き、奇数拍側をキック、偶数拍側をスネアで
支える単純なリズム伴奏です。最後の拍だけクラッシュシンバルを重ねます。
打楽器の `noteNumber` は General MIDI の番号（`36=キック`, `38=スネア`,
`42=クローズドハイハット`, `49=クラッシュシンバル`）を使用しています。

## 解析音色データ

`data/` には、実音解析で作成した各楽器の JSON を置いています。パートとファイルの
対応は次のとおりです。

| パート | 音色ファイル |
|---|---|
| 主旋律1 | `trumpets.tweaked.instrument.json` |
| 主旋律2 | `horns.tweaked.instrument.json` |
| 主旋律3 | `trombones.tweaked.instrument.json` |
| 低音 | `tuba.tweaked.instrument.json` |

スケッチは各 JSON の `harmonics` から第1〜第12倍音を読み取り、
比率 `ratio` と振幅 `amp` で合成音を作ります。また、`envelope` の
`attack_sec`, `decay_sec`, `sustain_level`, `release_sec` を Minim の
`ADSR` に渡し、楽器ごとの音の立ち上がりと減衰を反映します。
ドラムは解析 JSON を使用せず、Minim のサイン波とホワイトノイズによる
簡易合成でリズムの確認ができるようにしています。

JSON に含まれる `waveform`, `noise`, `modulation`, `fx` は元データとして保持しますが、
この試聴用スケッチではまだ合成に使用していません。

## 実行方法

1. Processing 4 で `kaeru_score_debug.pde` を開く。
2. Minim ライブラリが未導入の場合は、Contribution Manager から `Minim` を追加する。
3. Run 後、`P` キーで5パートの再生、`1`〜`5` キーで各パート単独再生を行う。
   再生中にもう一度キーを押すと音が重なるため、1回の再生が終わってから再試聴する。

画面上には各パートの楽器、入り拍、解析音色を利用していること、および Arduino 用に
転記できる `ScoreEvent` 配列の前提を表示します。

## Arduino へ移す際の扱い

このスケッチの `MELODY_SCORE` は主旋律担当ノードの `kScore[]` に、`BASS_SCORE`
はチューバ担当ノードの `kScore[]` に、`DRUM_SCORE` はドラム担当ノードの
`kScore[]` に転記できる粒度で作っています。
主旋律3声は同じ配列を利用し、`startBeatNo` だけを `0`, `8`, `16` に
差し替えます。チューバは `startBeatNo = 0` で40拍の低音配列、ドラムは
`startBeatNo = 0` で48拍のリズム配列を使用します。

現行の `firmware/` は指揮者1台と楽器4台（主旋律3声・チューバ）を対象として
いるため、ドラム担当ノードへ統合する場合はパート割当の合意後に行ってください。
