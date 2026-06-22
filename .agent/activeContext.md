# Active Context

- 2026-06-21: `work/saito/week9/kaeru_score_debug/` に、week7 をもとにした4声輪唱版の Processing スケッチを作成済み。
- 共通の `MELODY_SCORE` をトランペット、ホルン、トロンボーン、チューバで共有し、各パートはオクターブ補正と開始拍だけを変える。
- ドラムは56拍まで延長し、音量を下げて裏拍ハイハットと終止前フィルを追加した。音色JSONは week9 内の `data/` に同梱し、起動時の自動再生を削除済み。
- クラッシュシンバルは `crash.tweaked.instrument.json` の `drum_sample`（3秒・44.1 kHz）を Minim `AudioSample` で直接再生する。`Sampler` の実行時例外を回避し、`processing-java --run` で起動時例外が出ないことを確認済み。実音の確認は未実施。
- 解析アプリは停止済み。音色JSON 8ファイルと説明書は `work/saito/week9/kaeru_score_debug/data/` に同梱済み。
- 4声の入り順はトランペット → ホルン → トロンボーン → チューバ（0 / 8 / 16 / 24拍）。チューバは24拍遅れで最後に入り、Processing ビルド済み。
