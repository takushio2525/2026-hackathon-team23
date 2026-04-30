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

- **114** システムアーキテクチャ設計
- **115** 通信プロトコル基本設計（CTRL/BEAT/NOTE）
- **121** 共通層 API 詳細（IModule / SystemData / ProjectConfig）
- **122** `node_01` 詳細設計（IMU→拍検出→テンポ推定→送出）
- **123** `node_02-05` 詳細設計（受信→楽譜進行→NOTE 送出）

### 齋藤（4 タスク）

- **116** 楽譜データ形式 基本設計：
  **4 種類の楽器パートを Arduino のメモリに埋め込む方針** を決める
- **128** 楽譜データ詳細設計：**課題曲を 4 つの楽器パートに振り分ける**
  （誰がどのメロディを演奏するか）
- **129** 楽譜データ詳細設計：**テンポ・音の高さ・拍（リズム）** を
  どんな形でデータに書くか決める
- **130** 楽譜データ詳細設計：
  **Arduino（`node_02-05`）から PC（Processing）へ送る「音データの中身」**
  （何を、どんな粒度で、どのタイミングで送るか）

### 梅澤（5 タスク／うち 127 は任意）

- **117** 音色合成 基本設計：
  **金管楽器っぽい音色を作る方針**（重ねる倍音と、
  音の立ち上がり・伸び・余韻のカーブ）を決める
- **124** Processing 詳細設計：
  **Arduino から届く「音の指令（NOTE）」を受け取って鳴らす仕組み**
- **125** Processing 詳細設計：
  **4 種類の楽器パートを鳴らす管理**
  （どの音をどの発音枠で鳴らすかを決めるロジック）
- **126** Processing 詳細設計：
  **金管楽器っぽい音色を作る仕組み**
  （重ねる倍音と、音の立ち上がり・伸び・余韻のカーブの具体値）
- **127** *（余裕があれば）* **Python で実際の金管楽器音を周波数分解（FFT）**：
  倍音と音量カーブの実データを取り出し 126 に反映

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
      <td>114 システムアーキテクチャ設計</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>115 通信プロトコル基本設計（CTRL/BEAT/NOTE）</td><td align="center">塩澤</td></tr>
    <tr><td>116 楽譜データ形式 基本設計（4 種類の楽器パートを Arduino のメモリに埋め込む方針）</td><td align="center">齋藤</td></tr>
    <tr><td>117 音色合成 基本設計（金管楽器っぽい音色を作る方針：重ねる倍音と、音の立ち上がり・伸び・余韻のカーブ）</td><td align="center">梅澤</td></tr>
    <tr>
      <td rowspan="10" align="center">120</td>
      <td rowspan="10">詳細設計</td>
      <td>121 共通層 API 詳細（IModule / SystemData / ProjectConfig）</td>
      <td align="center">塩澤</td>
    </tr>
    <tr><td>122 <code>node_01</code> 詳細設計（IMU→拍検出→テンポ推定→送出）</td><td align="center">塩澤</td></tr>
    <tr><td>123 <code>node_02-05</code> 詳細設計（受信→楽譜進行→NOTE 送出）</td><td align="center">塩澤</td></tr>
    <tr><td>124 Processing 詳細設計：Arduino から届く音の指令（NOTE）を受け取って鳴らす仕組み</td><td align="center">梅澤</td></tr>
    <tr><td>125 Processing 詳細設計：4 種類の楽器パートを鳴らす管理（どの音をどの発音枠で鳴らすか）</td><td align="center">梅澤</td></tr>
    <tr><td>126 Processing 詳細設計：金管楽器っぽい音色を作る仕組み（重ねる倍音と、音の立ち上がり・伸び・余韻のカーブ）</td><td align="center">梅澤</td></tr>
    <tr><td>127 <em>（余裕があれば）</em> Python で実際の金管楽器音を周波数分解（FFT）して、倍音と音量カーブの実データを取り出し 126 に反映</td><td align="center">斎藤</td></tr>
    <tr><td>128 楽譜データ詳細設計：課題曲を 4 種類の楽器パートに振り分ける（どのマイコンがどのメロディを演奏するか）</td><td align="center">齋藤</td></tr>
    <tr><td>129 楽譜データ詳細設計：テンポ・音の高さ・拍（リズム）をどんな形でデータに書くか決める</td><td align="center">齋藤</td></tr>
    <tr><td>130 楽譜データ詳細設計：Arduino（<code>node_02-05</code>）から PC（Processing）へ送る音データの中身（何を、どのタイミングで送るか）</td><td align="center">齋藤</td></tr>
  </tbody>
</table>
