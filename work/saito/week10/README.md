# week10

担当した楽譜データ、4声輪唱、ドラム伴奏、音色再現の処理を事前に理解するための資料です。
最初に作成したweek9版の説明に加えて、week10で作成した修正版スケッチと、
week11で整理したフルート・オルガン追加後の構成も反映しています。

- `generate_understanding_pdf.py`: 編集用のPDF生成スクリプト
- `内容理解ノート_25G1053.pdf`: 配布用PDF

PDFを作り直す場合は、このフォルダで次を実行します。

```sh
python3 generate_understanding_pdf.py
```

内容は主に次の実装を基にしています。

- 旧版: `work/saito/week9/kaeru_score_debug/`
- 最新版: `work/saito/week10/kaeru_score_week10_adjusted/`

最新版では、フルート、トランペット、トロンボーン、オルガンの4声構成、
フルートの `tone_sample` 再生、ドラム音量調整を反映しています。
