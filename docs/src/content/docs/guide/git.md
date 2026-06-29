---
title: Gitで共同作業する
description: 変更前の同期から確認、コミットまで
---

## 基本フロー

```bash
git status
git pull --ff-only
# 編集・確認
git diff --check
git status --short
git add <変更したファイル>
git commit -m "[ドキュメント] production仕様へ更新"
```

## 注意点

- 作業開始前に現在のブランチと差分を確認する
- 他人の未コミット変更を削除・上書きしない
- `node_modules/`、`.astro/`、`dist/`をコミットしない
- 大量の自動整形を仕様変更と同じコミットへ混ぜない
- マージ前に`cd docs && npm run build`を実行する

コンフリクトが起きたら、両方の意図を確認してから解消します。判断できない内容を片側採用で消さないでください。
