# Active Context

- 2026-06-26: ユーザー指示により、通常作業は `saitou-work` ブランチで行う。`firmware/` と `pc_app/` 配下のプログラムは変更しない。
- 2026-06-26: `work/saito/week10/kaeru_score_week10_adjusted/` に、week9 の個人用 Processing スケッチをもとにした修正版プログラムを作成した。
- week10 修正版の変更点: ドラムを 56 拍の 4/4（1・3拍目キック、2・4拍目スネア）に整理、各声部の入りと最後だけクラッシュ+キック、チューバは共通譜から -24 semitone（C2相当）、全体音量 `MASTER_GAIN=1.35` と各パート音量・ドラム音量を増加。
- 音色 JSON 8 ファイルは `work/saito/week10/kaeru_score_week10_adjusted/data/` に同梱し、外部参照なしで実行できる。`processing-java --sketch="$PWD/work/saito/week10/kaeru_score_week10_adjusted" --build --output=/tmp/kaeru_score_week10_adjusted_build` 成功。
- 未追跡として `firmware/production/node_04/.vscode/` の VS Code 設定ファイルが見えているが、コミット対象にしない。
