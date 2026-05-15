# 現在の作業文脈

> このファイルは **毎ターン上書き**される動的文脈ファイル。
> 履歴は `progress.md` に追記する形で残す。

## 現在の対象

- **2026-05-15**: docs/ 充実化フェーズ第 6 弾。ユーザー要望「essentials の中で図解が薄いから、
  視覚的に分かりやすい図を積極的に追加して」に応えて、**Mermaid プラグインの導入 + 全 essentials
  4 ページに合計 24 個の Mermaid 図解を追加**。

## 直近の観点

1. **問題発覚**: ユーザー指摘の前提として `flowchart LR` などを既に書いていたが、Starlight は
   標準で Mermaid をレンダリングせず、コードブロックとして生表示されていた（既存ページ含めて
   全部）。dist/architecture/overview/index.html を grep して確認済み。
2. **採用した方式**: クライアントサイドの mermaid.esm.min.mjs を CDN から読み込み、
   `<pre data-language="mermaid">` を `<div class="mermaid">` に置換して `mermaid.run` を
   呼ぶ自前スクリプトを `astro.config.mjs` の `head:` に登録。
   - 採用理由: ① npm 依存追加なし、② ビルド時間に影響なし、③ Playwright/Puppeteer 等の重い
     依存が要らない、④ Starlight 0.39 / Astro 6.3 に副作用を出さない。
3. **躓いた点と対処**:
   - expressive-code が各行を `<div class="ec-line"><div class="code">` に分解するため、
     `pre.textContent` だと改行が失われる → `.ec-line` だけを走査して各行を `\n` で連結
   - 最初のセレクタ `.ec-line .code, .ec-line` が両方マッチして行を二重化 → `.ec-line` のみに修正
   - Mermaid v11 はノードラベル内の `()` `:` を厳密に拒否 → 該当ラベルを `"..."` で囲む形に
     2 箇所修正（project.md の「(1台)」「(4台)」「(未着手)」、processing.md の `y(t)`、
     analyzer.md の「(JSON に書かない)」）
4. **追加した図解（合計 24 個）**:
   - `project.md` +2: 「1 拍が鳴るまでの旅」を sequenceDiagram、「同期は 4 つの層」を flowchart
   - `firmware.md` +4: 状態機械を stateDiagram、拍検出を flowchart、時刻同期を sequenceDiagram、
     輪唱の頭ずらしを ASCII 図
   - `processing.md` +4: 3 スレッドのやりとりを sequenceDiagram、加算合成の信号フローを
     flowchart、揺れの効果比較を ASCII、音色 JSON の流れを flowchart
   - `analyzer.md` +5: ④基音検出、⑤揺れ検出、⑥ADSR フィット、⑦倍音抽出、⑧残差ノイズの
     各段にミニ flowchart を追加
5. **Playwright で動作検証**: dev server を起動して全 4 ページの全 Mermaid 図に対して
   `svg .error-icon` の有無を確認。**24 図すべて hasError: no、SVG サイズも正常**。
   既存ページ（architecture/overview）も同じスクリプトで描画できることを確認。
6. **ビルド**: `npm run build` で 70 ページ生成成功。リンク切れ・slug エラーなし

## 次の一手

- **コミット**: `[改善] essentials 4 ページに Mermaid 図解 24 個を追加（プラグイン込み）` で 1 コミット
- **次に検討したいこと**:
  - 既存ページ（architecture/, deep-dive/, firmware/, pc-audio/）にも Mermaid のレンダリングが
    効くようになったので、それらの章でも追加図解する余地がある（要求があれば）
  - クライアント側 mermaid.js を CDN から取る方式なので、オフラインでは図が出ない。
    GitHub Pages 配信時に CDN 経由で読まれる形になる。気になるなら後で `npm i mermaid` して
    バンドルする選択肢もある

## ユーザーの今回の好み

- **「図解は積極的に使用して」** が明示的な要望
- ASCII 図解だけでなく、Mermaid で **構造化された描画** を求めている（特に状態遷移とシーケンス）
- 質問返しせず即着手の autonomous モード継続

## 既知の論点

- Mermaid のラベル内で `()` `:` `,` などの特殊文字はトラブルの元。今後 Mermaid を書くときは
  ラベル全体を **必ずダブルクォートで囲む**（`Node["ラベル"]`）のがクセとして安全
- `astro.config.mjs` の `head:` に長い script を埋め込んだので、後から保守したくなったら
  `src/components/MermaidScript.astro` を作って `components.Head` から差し込む形に分離できる
- ビルド時プレレンダ（rehype-mermaid + Playwright）に切り替える選択肢もあるが、
  CI 重量化と引き換えなので、現状の CDN クライアント方式で十分
