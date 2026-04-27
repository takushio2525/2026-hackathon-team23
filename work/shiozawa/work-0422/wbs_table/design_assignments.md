# 基本設計・詳細設計 タスク割振り — チーム23 ハッカソン1

## このファイルの目的

第3回ミーティング前（今週）に、各自が **「基本設計」「詳細設計」として
何を持ち寄るか**を担当者ごとに一目で確認できるよう抜粋したもの。


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

### 齋藤（4 タスク）

- **116** 楽譜データ形式 基本設計（4 パート/ROM 埋込）
- **128** 楽譜データ詳細設計：**課題曲の 4 パートへの分配**
- **129** 楽譜データ詳細設計：**テンポ・音程・拍** の情報フォーマット
- **130** 楽譜データ詳細設計：**Arduino**（`node_02-05`）**→ Processing** の音楽データ仕様
  （何を、どんな粒度で、どのタイミングで送るか）

### 梅澤（5 タスク／うち 127 は任意）

- **117** 音色合成 基本設計（金管倍音 + ADSR）
- **124** Processing 詳細設計：**NOTE 受信モジュール** 仕様（パース → キュー）
- **125** Processing 詳細設計：**ボイス管理**（4 パート同時発音／ボイス割り当てロジック）
- **126** Processing 詳細設計：**金管音色合成エンジン** 仕様
  （倍音構成 + ADSR の具体パラメータ）
- **127** *（余裕があれば）* **Python で実音源解析**：
  FFT で倍音構成と ADSR を抽出 → 126 に反映

## フェーズ × 番号順の表

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
      <td rowspan="14" align="center"><strong>100<br>設計フェーズ</strong></td>
      <td rowspan="4" align="center">110</td>
      <td rowspan="4">基本設計</td>
      <td>114 システムアーキテクチャ設計（EMA 準拠）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>115 通信プロトコル基本設計（CTRL/BEAT/NOTE）</td><td align="center">塩澤</td></tr>
    <tr><td>116 楽譜データ形式 基本設計（4 パート/ROM 埋込）</td><td align="center">齋藤</td></tr>
    <tr><td>117 音色合成 基本設計（金管倍音 + ADSR）</td><td align="center">梅澤</td></tr>
    <tr>
      <td rowspan="10" align="center">120</td>
      <td rowspan="10">詳細設計</td>
      <td>121 共通層 API 詳細（IModule / SystemData / ProjectConfig）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>122 <code>node_01</code> 詳細設計（IMU→拍検出→テンポ推定→送出）</td><td align="center">塩澤</td></tr>
    <tr><td>123 <code>node_02-05</code> 詳細設計（受信→楽譜進行→NOTE 送出）</td><td align="center">塩澤</td></tr>
    <tr><td>124 Processing 詳細設計：NOTE 受信モジュール仕様（パース→キュー）</td><td align="center">梅澤</td></tr>
    <tr><td>125 Processing 詳細設計：ボイス管理（4 パート同時発音／ボイス割り当て）</td><td align="center">梅澤</td></tr>
    <tr><td>126 Processing 詳細設計：金管音色合成エンジン仕様（倍音構成 + ADSR 具体パラメータ）</td><td align="center">梅澤</td></tr>
    <tr><td>127 <em>（余裕があれば）</em> Python で実音源を FFT→倍音・ADSR を抽出し 126 に反映</td><td align="center">梅澤</td></tr>
    <tr><td>128 楽譜データ詳細設計：課題曲の 4 パートへの分配</td><td align="center">齋藤</td></tr>
    <tr><td>129 楽譜データ詳細設計：テンポ・音程・拍の情報フォーマット</td><td align="center">齋藤</td></tr>
    <tr><td>130 楽譜データ詳細設計：Arduino（<code>node_02-05</code>）→ Processing の音楽データ仕様</td><td align="center">齋藤</td></tr>
  </tbody>
</table>

