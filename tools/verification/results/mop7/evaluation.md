# MOP7: 起動時間 評価記録

## 目標値
電源投入から演奏可能状態まで <= 5 秒

## 検証方法の妥当性

### ファーム出力の設計

MOP_TEST=7 でノードごとに起動マイルストーンを `M7,<nodeId>,<event>,<millis>` 形式でシリアル出力する。
millis() はハードウェアリセットからの経過時間なので、READY の millis 値がそのまま「電源投入→演奏可能」の起動時間になる。

**指揮者 (nodeId=1):** BOOT → INIT → READY (Calibrating 完了で Conducting/Menu 遷移)
- WIFI イベントは出力しない（指揮者は SoftAP 側なので、AP 起動は INIT に含まれる）
- READY は Calibrating 以降の状態（Conducting / Menu 等）への遷移で発火
- ユーザー操作（拍検出）は含まない = 純粋なシステム起動時間を計測

**楽器 (nodeId=2〜6):** BOOT → INIT → WIFI → SYNC → READY (初回 BEAT 受信)
- WIFI: SoftAP への接続完了
- SYNC: 時刻同期の EMA が収束
- READY: 初回 BEAT パケット受信 = 演奏可能（音を鳴らせる状態）

### 計測時間の精度

- device_ms (millis()) を使用し、PC 側のシリアル伝送遅延を排除
- Python スクリプトは device_ms を優先して起動時間を算出する
- SERIAL_DEBUG フォールバック時は PC タイムスタンプを代用（精度はやや劣る）

### 既知の制約

1. **ensureSerial() オーバーヘッド**: MOP_TEST>0 のとき Serial 初期化で最大 1500ms 待つ。
   BOOT の millis 値にはこの待ちが含まれるため、READY millis は本番より最大 1500ms 大きくなる。
   PASS/FAIL 判定は保守的（厳しい側）に倒れるので、本番では目標をより余裕をもって達成できる。

2. **楽器の READY 定義**: MOP 定義では「最初の CTRL 受信」だが、ファームは `hasFirstBeat`
   （初回 BEAT 受信）を使用する。BEAT は CTRL より後に届くため、こちらの方がより保守的な
   計測になる。BEAT 受信 = 実際に音を鳴らせる状態であり、「演奏可能」の実質的な定義に合致する。

3. **途中起動の誤検出防止**: スクリプトは「ノードの電源を入れ直してください」と案内し、
   BOOT 未検出ノードは「BOOT 未検出」と明示する。既に起動済みのノードの部分データで
   起動時間を算出することはない。

## テスト結果履歴
| 日時 | 結果 | 値 | 備考 |
|---|---|---|---|

## 考察
<!-- 実機テスト後に記入 -->
