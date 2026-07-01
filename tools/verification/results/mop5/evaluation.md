# MOP5: 指揮→楽器 通信遅延 評価記録

## 目標値
最大通信遅延 <= 10 ms（指揮者 BEAT 送信から楽器受信までの遅延）

## 検証方法

### 計測原理（ahead ベース）

指揮者と楽器のクロックは独立しているため、millis() の直接差分では遅延を測れない。
代わりに楽器側の「ahead 値」から概算遅延を導出する。

1. 指揮者: 拍検出時に `playAtMasterMs = masterNow + beatLookaheadMs`（45ms）を計算し BEAT パケットで送信
2. 楽器: 受信時に EMA 同期済みの推定マスタ時計 `localMasterMs = millis() + offsetMs` を算出
3. `ahead = playAtMasterMs - localMasterMs`（発音予定時刻までの残り時間）
4. `推定遅延 = beatLookaheadMs - ahead`

### 方法論の限界（重要）

EMA 時刻同期は片道遅延をオフセットに吸収する。定常状態では:
- EMA 推定オフセット ≈ `真のオフセット θ - 平均片道遅延 d_avg`
- 推定遅延 ≈ `d_current - d_avg`（瞬間遅延と平均遅延の差 = ジッタ成分）

つまりこの方式は **絶対遅延ではなく遅延のジッタ（変動）** を計測している。
絶対遅延は SoftAP 直結 LAN の物理特性（ESP32 SoftAP→STA 間で典型 1-3ms）で保証する。

この制約下でジッタが閾値 10ms 以内であれば、
`絶対遅延 = 定常遅延(1-3ms) + ジッタ(< 10ms)` も 10ms 程度に収まると推定できる。

### 追加の注意点

- **EMA 更新順序**: OrcReceiverModule で `updateClockOffset()` → `ahead` 計算の順で実行されるため、
  当該パケット自身の遅延で EMA が 20%（α=0.20）更新された後に ahead を算出する。
  推定遅延がゼロ方向にわずかにバイアスされるが、影響は限定的
- **EMA 収束前**: 最初の数拍（clockSyncMinSamples=3 拍未満）は offset が不安定。
  計測は演奏開始から数秒経過後のデータを対象とするのが望ましい
- **beatLookaheadMs の値**: Python スクリプトにハードコード（45ms）。
  ProjectConfig.h の値を変更した場合はスクリプト側も手動で合わせる必要がある

## テスト結果履歴
| 日時 | 結果 | 値 | 備考 |
|---|---|---|---|

## 考察
<!-- 実測後に記入: ノード間のばらつき、ahead 分布の偏り、遅延スパイクの有無 -->
