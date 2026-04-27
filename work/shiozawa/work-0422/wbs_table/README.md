# WBS 表（再設計版） — チーム23 ハッカソン1

## このフォルダの目的

第2回議事録（`meetings/0422_2回/23_第2回議事録_24G1075.pdf`）の
**表1 WBS（作業分担表）** を、授業資料の正解形式（時間的フェーズ＝開発工程軸）
で再構成した版を、**1 つの表**として提示する。

`wbs_proposal/main.pdf` 第4章「新 WBS（提案版）」と内容は同じだが、
こちらは GitHub 上で 1 つのスクロール可能な表として一覧したい用途。

- 当初は LaTeX で「議事録 表1 と同じ multirow 構造」を再現していたが、
  活動タスク 51 行が複数ページに分かれてしまい紙面では一覧性が悪かったため、
  Markdown 表に差し替えた。
- さらに Markdown 標準表ではセル結合（multirow）ができず、
  「時間的フェーズ」「番号」「要素成果物」列で同じ値が縦に並ぶと
  境界が見づらかったので、**HTML 表 + `rowspan`** で議事録 表1 と
  同じ縦結合形式に再変更した（GitHub・VSCode プレビューで自然に
  レンダリングされる）。
- 議事録 表1 ↔ 本表 の対応関係（議事録 17 行のうち何が新 WBS のどこに移ったか）
  は `wbs_proposal/main.pdf` 第 5 章を参照。

## 担当者表記

- **塩澤**: 25G1065 塩澤匠生（Arduino 全般）
- **齋藤**: 25G1053 齋藤翔太（楽譜データ・音階）
- **梅澤**: 25G1021 梅澤颯太（Processing 音色合成）
- **全員**: 実装 3 人全員（塩澤・齋藤・梅澤）

24G 勢（片岡・地曵・御代川）は議事録持ち回りと 300 テストフェーズ以降の
実機検証・発表準備に合流するため、本表の活動タスク列には記載しない。

## 表1 WBS（作業分担表）

<table border="1">
  <thead>
    <tr>
      <th align="center">時間的フェーズ</th>
      <th align="center">番号</th>
      <th align="center">要素成果物</th>
      <th align="center">活動タスク</th>
      <th align="center">担当者</th>
    </tr>
  </thead>

  <tbody>
    <tr>
      <td rowspan="12" align="center"><strong>100<br>設計フェーズ</strong></td>
      <td rowspan="7" align="center">110</td>
      <td rowspan="7">基本設計</td>
      <td>111 FBS（機能分解構造）の最終化</td>
      <td align="center">全員</td>
    </tr>
    <tr><td>112 PBS（製品分解構造）の最終化</td><td align="center">全員</td></tr>
    <tr><td>113 MOE / MOP / TPM の最終化</td><td align="center">全員</td></tr>
    <tr><td>114 システムアーキテクチャ設計（EMA 準拠）</td><td align="center">塩澤</td></tr>
    <tr><td>115 通信プロトコル基本設計（CTRL/BEAT/NOTE）</td><td align="center">塩澤</td></tr>
    <tr><td>116 楽譜データ形式 基本設計（4 パート/ROM 埋込）</td><td align="center">齋藤</td></tr>
    <tr><td>117 音色合成 基本設計（金管倍音 + ADSR）</td><td align="center">梅澤</td></tr>
    <tr>
      <td rowspan="5" align="center">120</td>
      <td rowspan="5">詳細設計</td>
      <td>121 共通層 API 詳細（IModule / SystemData / ProjectConfig）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>122 <code>node_01</code> 詳細設計（IMU→拍検出→テンポ推定→送出）</td><td align="center">塩澤</td></tr>
    <tr><td>123 <code>node_02-05</code> 詳細設計（受信→楽譜進行→NOTE 送出）</td><td align="center">塩澤</td></tr>
    <tr><td>124 Processing 詳細設計（NOTE 受信→ボイス管理→出力）</td><td align="center">梅澤</td></tr>
    <tr><td>125 楽譜データ詳細設計（課題曲のパート割・データ表化）</td><td align="center">齋藤</td></tr>
  </tbody>

  <tbody>
    <tr>
      <td rowspan="19" align="center"><strong>200<br>製造フェーズ</strong></td>
      <td rowspan="3" align="center">210</td>
      <td rowspan="3">共通層実装</td>
      <td>211 IModule / ModuleTimer 実装</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>212 SystemData / ProjectConfig テンプレ整備</td><td align="center">塩澤</td></tr>
    <tr><td>213 OrcNetModule（UDP 送受信ラッパ：CTRL/BEAT/NOTE 共通）</td><td align="center">塩澤</td></tr>
    <tr>
      <td rowspan="5" align="center">220</td>
      <td rowspan="5">指揮者ノード（<code>node_01</code>）</td>
      <td>221 IMU ドライバモジュール</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>222 信号前処理（重力分離・LPF）モジュール</td><td align="center">塩澤</td></tr>
    <tr><td>223 拍検出モジュール（候補方式比較含む）</td><td align="center">塩澤</td></tr>
    <tr><td>224 テンポ推定モジュール</td><td align="center">塩澤</td></tr>
    <tr><td>225 コマンド送出モジュール（CTRL/BEAT）</td><td align="center">塩澤</td></tr>
    <tr>
      <td rowspan="4" align="center">230</td>
      <td rowspan="4">楽器ノード（<code>node_02-05</code>）</td>
      <td>231 CTRL/BEAT 受信モジュール</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>232 楽譜データ保持・進行ロジック</td><td align="center">塩澤</td></tr>
    <tr><td>233 NOTE 送出モジュール</td><td align="center">塩澤</td></tr>
    <tr><td>234 パート別差分適用（<code>node_03/04/05</code> への展開）</td><td align="center">塩澤</td></tr>
    <tr>
      <td rowspan="3" align="center">240</td>
      <td rowspan="3">楽譜データ準備</td>
      <td>241 課題曲 4 パートの選定</td>
      <td align="center">齋藤</td>
    </tr>
    <tr><td>242 4 パート楽譜のヘッダ配列化（PROGMEM 形式）</td><td align="center">齋藤</td></tr>
    <tr><td>243 楽譜データの ROM 埋込確認</td><td align="center">齋藤</td></tr>
    <tr>
      <td rowspan="4" align="center">250</td>
      <td rowspan="4">Processing 側実装</td>
      <td>251 NOTE 受信モジュール</td>
      <td align="center">梅澤</td>
    </tr>
    <tr><td>252 金管音色合成エンジン（倍音 + ADSR）</td><td align="center">梅澤</td></tr>
    <tr><td>253 4 パート同時発音管理（ボイスマネージャ）</td><td align="center">梅澤</td></tr>
    <tr><td>254 UI / モード表示（最小限）</td><td align="center">梅澤</td></tr>
  </tbody>

  <tbody>
    <tr>
      <td rowspan="15" align="center"><strong>300<br>テストフェーズ</strong></td>
      <td rowspan="4" align="center">310</td>
      <td rowspan="4">単体テスト</td>
      <td>311 共通層単体（OrcProtocol / ModuleTimer）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>312 拍検出ゴールデンテスト（記録 IMU 波形→期待発火）</td><td align="center">塩澤</td></tr>
    <tr><td>313 楽譜進行 状態機械テスト</td><td align="center">塩澤</td></tr>
    <tr><td>314 音色生成 単体確認（聴感+波形目視）</td><td align="center">梅澤</td></tr>
    <tr>
      <td rowspan="4" align="center">320</td>
      <td rowspan="4">結合テスト</td>
      <td>321 <code>node_01</code> 単体デモ（手振り→ログ拍出力）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>322 <code>node_01</code> + <code>node_02</code> 結合（BEAT 送受信）</td><td align="center">塩澤</td></tr>
    <tr><td>323 4 ノード同時 同期誤差計測</td><td align="center">全員</td></tr>
    <tr><td>324 全ノード + Processing 全結合（実音出し）</td><td align="center">全員</td></tr>
    <tr>
      <td rowspan="7" align="center">330</td>
      <td rowspan="7">システムテスト</td>
      <td>331 TP-1 拍検出精度（80 / 120 / 160 BPM）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>332 TP-2 通信遅延</td><td align="center">塩澤</td></tr>
    <tr><td>333 TP-3 同期誤差（4 ノード時刻合わせ）</td><td align="center">全員</td></tr>
    <tr><td>334 TP-4 テンポ追従（80→120 BPM 階段変化）</td><td align="center">塩澤</td></tr>
    <tr><td>335 TP-5 パケロス耐性（5% 擬似パケロス）</td><td align="center">塩澤</td></tr>
    <tr><td>336 TP-6 CPU 負荷（入力フェーズ 2ms 以下）</td><td align="center">塩澤</td></tr>
    <tr><td>337 TP-7 起動時間（電源→演奏可能 5s 以下）</td><td align="center">塩澤</td></tr>
  </tbody>

  <tbody>
    <tr>
      <td rowspan="3" align="center"><strong>400<br>ストレッチフェーズ</strong></td>
      <td rowspan="3" align="center">410</td>
      <td rowspan="3">強弱推定</td>
      <td>411 振幅 → velocity 推定アルゴ実装</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>412 CTRL パケットへの velocity 乗せ込み</td><td align="center">塩澤</td></tr>
    <tr><td>413 TP-8 強弱制御テスト（3 段階分離）</td><td align="center">塩澤</td></tr>
  </tbody>

  <tbody>
    <tr>
      <td rowspan="2" align="center"><strong>500<br>運用・発表</strong></td>
      <td align="center">510</td>
      <td>発表</td>
      <td>511 発表準備・デモ調整</td>
      <td align="center">全員</td>
    </tr>
    <tr>
      <td align="center">520</td>
      <td>報告書</td>
      <td>521 成果報告書（個人）</td>
      <td align="center">全員</td>
    </tr>
  </tbody>
</table>

## 不要になったら

`wbs_proposal/` と同じく**チーム内議論用**。計画書本体（`提出用計画書/plan_template.tex`）
の §3.1「作業分解構造 WBS と管理番号」に WBS が反映され、役割を終えたら
削除して構わない。
