# Active Context

- 2026-06-26: ユーザー指示により、通常作業は `saitou-work` ブランチで行う。`firmware/` と `pc_app/` 配下のプログラムは変更しない。
- 2026-06-26: `work/saito/week10/kaeru_score_week10_adjusted/` に、week9 の個人用 Processing スケッチをもとにした修正版プログラムを作成した。
- week10 修正版の変更点: ドラムを 56 拍の 4/4（1・3拍目キック、2・4拍目スネア）に整理、各声部の入りと最後だけクラッシュ+キック、チューバは共通譜から -24 semitone（C2相当）、全体音量 `MASTER_GAIN=1.35` と各パート音量・ドラム音量を増加。
- 2026-06-27: 金管とドラムの聴感上のズレ対策として、拍位置は変えずに金管の attack だけ短縮。`BRASS_ATTACK_SCALE=0.45` を追加し、`BrassNote` の ADSR attack を `max(0.003, attackSec*0.45)` に変更した。
- 2026-06-27: 音割れ回避のため、week10 修正版のチューバ `amplitude` を `0.38f` から `0.36f` に少し下げた。他パート、拍位置、ドラム譜は変更なし。
- 2026-06-27: ドラムの音量をほんの少し下げるため、`DRUM_AMPLITUDE` を `0.12f` から `0.11f` に変更した。ドラム譜・拍位置・金管側は変更なし。
- 音色 JSON 8 ファイルは `work/saito/week10/kaeru_score_week10_adjusted/data/` に同梱し、外部参照なしで実行できる。`processing-java --sketch="$PWD/work/saito/week10/kaeru_score_week10_adjusted" --build --output=/tmp/kaeru_score_week10_adjusted_build` 成功。
- 未追跡として `firmware/production/node_04/.vscode/` の VS Code 設定ファイルが見えているが、コミット対象にしない。
