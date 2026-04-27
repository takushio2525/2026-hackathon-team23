# 基本設計・詳細設計 タスク割振り — チーム23 ハッカソン1

## このファイルの目的

第3回ミーティング前（今週）に、各自が **「基本設計」「詳細設計」として
何を持ち寄るか**を担当者ごとに一目で確認できるよう抜粋したもの。

- 元データは同フォルダの [`README.md`](README.md)（全 51 タスクの WBS 表）。
- そのうち **110 基本設計** と **120 詳細設計** から、各自が個別に分担して
  仕上げてくる対象だけを抜き出している。
- **111 FBS / 112 PBS / 113 MOE・MOP・TPM の最終化** は、
  チーム全員で合意形成するタスクなので個別分担対象から外している
  （ミーティング中に詰める）。

## 担当者表記

- **塩澤**: 25G1065 塩澤匠生（Arduino 全般）
- **齋藤**: 25G1053 齋藤翔太（楽譜データ・音階）
- **梅澤**: 25G1021 梅澤颯太（Processing 音色合成）

## 担当者ごとの分担（誰が何を持ち寄るか）

### 塩澤（5 タスク）

- **114** システムアーキテクチャ設計（EMA 準拠）
- **115** 通信プロトコル基本設計（CTRL/BEAT/NOTE）
- **121** 共通層 API 詳細（IModule / SystemData / ProjectConfig）
- **122** `node_01` 詳細設計（IMU→拍検出→テンポ推定→送出）
- **123** `node_02-05` 詳細設計（受信→楽譜進行→NOTE 送出）

### 齋藤（2 タスク）

- **116** 楽譜データ形式 基本設計（4 パート/ROM 埋込）
- **125** 楽譜データ詳細設計（課題曲のパート割・データ表化）

### 梅澤（2 タスク）

- **117** 音色合成 基本設計（金管倍音 + ADSR）
- **124** Processing 詳細設計（NOTE 受信→ボイス管理→出力）

## フェーズ × 番号順の表

> `README.md` と同じ HTML 縦結合（`rowspan`）形式で 110・120 のみ抜粋。

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
      <td rowspan="9" align="center"><strong>100<br>設計フェーズ</strong></td>
      <td rowspan="4" align="center">110</td>
      <td rowspan="4">基本設計</td>
      <td>114 システムアーキテクチャ設計（EMA 準拠）</td>
      <td align="center">塩澤</td>
    </tr>
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
</table>

## 補足

- 「基本設計」と「詳細設計」の中身（成果物の形式・粒度）は、
  ミーティングで合意したフォーマット（Markdown / 図 / 表 など）で各自まとめる。
- 同じ番号の基本設計と詳細設計は紐付いている
  （例：115 通信プロトコル基本設計 → 121 共通層 API 詳細 → 122/123 ノード詳細）。
- 完成したら `work/<各自のフォルダ>/` 配下に成果物を置き、第3回ミーティングで
  共有する想定。

## 不要になったら

第3回ミーティングで全員の設計が共有され、計画書本体や設計成果物リポジトリに
取り込まれたら役割を終えるので削除して構わない。
