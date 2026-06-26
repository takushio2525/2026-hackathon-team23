# Active Context

- 2026-06-26: ユーザー指示により、以後の作業は `saitou-work` ブランチで行う。
- 2026-06-26: `firmware/` と `pc_app/` 配下のプログラムは変更しない。齋藤個人作業は `work/saito/` 配下を中心に扱う。
- 2026-06-26: `saitou-work` へ切り替え済み。ブランチは `origin/saitou-work` と同期済み。未追跡として `firmware/production/node_04/.vscode/` のVS Code設定ファイルが見えているが、コミット対象にしない。
- 2026-06-26: main に入れた `1093f04 [改善] 本番版のドラム拍子と全楽器音量を調整` の取り消し前調査を実施。対象は `firmware/production/README.md`、`firmware/production/node_06/include/score_data.h`、`firmware/production/node_06/src/score_data.cpp`、`pc_app/production/README.md`、`pc_app/production/orchestra_resynth/orchestra_resynth.pde`。後続の #32/#33 で Processing 処理は `pc_app/common/AudioManager.pde` に移動し、音量・チューバ移調のコードは現在ほぼ元値へ戻っているが、README の説明には C2/1.40/4/4 記述が残っている。
- 2026-06-21: `work/saito/week9/kaeru_score_debug/` に、week7 をもとにした4声輪唱版の Processing スケッチを作成済み。
- 共通の `MELODY_SCORE` をトランペット、ホルン、トロンボーン、チューバで共有し、各パートはオクターブ補正と開始拍だけを変える。
- ドラムは56拍まで延長し、音量を下げて裏拍ハイハットと終止前フィルを追加した。音色JSONは week9 内の `data/` に同梱し、起動時の自動再生を削除済み。
- キック、スネア、ハイハット、クラッシュは再解析済みJSONの `drum_sample` を Minim `AudioSample` で直接再生する。サンプルがないJSONは、倍音・ノイズ・ADSRによる従来の合成へ自動的に戻る。`Sampler` の実行時例外を回避し、`processing-java --run` で起動時例外が出ないことを確認済み。実音の確認は未実施。
- 解析アプリは停止済み。音色JSON 8ファイルと説明書は `work/saito/week9/kaeru_score_debug/data/` に同梱済み。
- 4声の入り順はトランペット → ホルン → トロンボーン → チューバ（0 / 8 / 16 / 24拍）。チューバは24拍遅れで最後に入り、Processing ビルド済み。
- `work/saito/week9/作業ログ/` にweek7相当の詳細構成を持つLaTeX作業ログを追加済み。主要作業4項目、GC、課題、AI利用と検証、次回計画、付録を記入し、作業時間のみ未計測として残した。uplatex・dvipdfmxでPDF生成を確認した。
- 作業ログはweek7と同じ `geometry`、`array`、`tabularx`、`booktabs`、`enumitem`、`graphicx`、`titlesec` のパッケージ構成と体裁設定を使用する。PDF生成を確認済み。
- week9作業ログに `Figs/GC.png` を追加し，「前回の作業ログから担当内容・作業計画・進捗に変更なし」と明記したGC節を掲載した。
- 2026-06-24: `work/saito/week10/` に、発表スライドではなく事前理解用のPDF資料を作成した。共通楽譜、4声輪唱、ドラム譜、音色JSONのパラメータ、金管とドラムの処理差、本番前の確認項目を4ページに整理し、PDFレンダリングで日本語表示とレイアウトを確認済み。
