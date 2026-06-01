# test_v2 低遅延化・パケロス削減・堅牢化 計画

> 起点ブランチ: `shiozawa-test_v2-latency`（`shiozawa-test_v2-jitter` から分岐）。
> jitter で済んでいる改善（楽器ループ 5→2ms・クロック同期 α・DevKitC 移行・SERIAL_DEBUG=0・
> かえるのうた）は前提。本計画は **その続きの未着手分** のみを扱う。
> 鉄則: main に触らない／push しない。実機 upload と最終確認はユーザー。Claude はコンパイル確認まで。

## 1. 遅延チェーン分解（指揮者の振り下ろし → 音が出るまで）

| 段 | 区間 | 現状の遅延 | 種別 | 改善余地 |
|---|---|---|---|---|
| A | IMU サンプル粒度（200Hz） | 0–5ms | 検出 | 温存（センサ仕様） |
| B | LPF α=0.10 の群遅延 | ~30–50ms | 検出 | **温存**（拍検出の安定性に直結。下げると誤検出増） |
| C | path 0.20m 蓄積で早期発火 | 振り出しから ~100–150ms | 検出 | 温存（振り下ろし途中で鳴る意図的設計） |
| D | lookahead（playAt=now+L） | **50ms** | 同期（意図的） | **30ms へ短縮** |
| E | UDP 連送送信（redundancy=4） | gap0 で ~1ms に集中 | 伝送/ロス | **beatGap 2ms で時間分散** |
| F | WiFi 伝播（SoftAP マルチキャスト） | ~1–15ms（可変・主ロス源） | 伝送 | DevKitC 内蔵アンテナ（jitter で対応済）|
| G | 楽器受信粒度（loop 2ms） | 0–2ms | 伝送 | jitter 済 |
| H | 発火判定（playAt 到達待ち） | D に内包 | 同期 | — |
| I | Serial write + flush | ~2ms | PC伝送 | 温存（flush はバースト防止に必要） |
| J | USB CDC 伝播 | ~1–3ms | PC伝送 | 温存 |
| K | draw drainPackets 粒度 | 0–16.7ms（60fps） | PC処理 | **frameRate 90 で ~11ms** |
| L | Minim audio バッファ | **23.2ms**（1024@44.1k） | PC処理 | **512 で 11.6ms** |

**体感遅延の概算**: C + D + (F+G) + (I+J) + K + L
- 現状 ≈ 130 + 50 + 12 + 4 + 8 + 23 ≈ **約227ms**
- 改善後 ≈ 130 + 30 + 12 + 4 + 5 + 11.6 ≈ **約193ms**（約34ms 短縮、後段だけで約25ms）

**重要な構造**: D(lookahead) は「楽器が NoteOn を Serial に出すタイミングを全機で揃える」ための先読み。
その後段 I〜L（≈45ms）は全楽器共通の固定遅延で、lookahead では吸収されない（＝絶対遅延として残る）。
だから「低遅延化」は **D を実態に合わせて削り、後段 K/L を物理的に削る** の二本立て。

### lookahead を 30ms にする根拠
楽器が連送 BEAT を受信し終えるまで ≈ F(最悪~15ms) + E連送広がり(gap2 で~6ms) + G(2ms) ≈ **23ms**。
lookahead 30ms ならマージン約7ms。連送4発のうち1発でも 30ms 以内に届けば playAt 到達待ちで揃う。
50ms は過剰、30ms が「確実に届く最小＋マージン」。これより下げると遅延環境で即発火（揃え崩れ）が増える。

## 2. パケロス要因と対策

- **主因（仮説）**: SoftAP マルチキャストの radio ロス。jitter で XIAO 外付けIPEX → DevKitC 内蔵アンテナへ
  載せ替え済み（`node_01_devkitc`）。これが根本対策で、実機で効果確認済みとの記録あり。
- **連送のまとめ落ち**: redundancy=4 を gap0（タイトループ）で送ると radio バッファに4発積んで同一無線状態で
  送出 → まとめてロスしやすい。**beatGap 0→2ms** で各送出間に無線状態の変化余地を作りロスを分散。
  - 副作用: 送信は node_01 の出力フェーズなので delay(2)×3=6ms だけ loop が止まる。BEAT は1拍ごと
    （数百ms に1回）なので頻度は低く、IMU サンプルが1個遅れる程度。dt≤50ms ガード内なので積分は継続。
- **重複排除**: beatNo で実装済（連送のうち1発受かれば発音、後着は無視）。維持。
- CTRL 冗長化は不要（50ms 周期で流れ続け、BEAT 側でも time sync するため実害小）。要件超過を避ける。

## 3. 堅牢化（確実動作）

- **WiFi 再接続後の UDP 再 join（最重要）**: 現状 Sta 側は切断時に `WiFi.disconnect()+begin()` を
  叩くが、**再接続成功後に `udp_.beginMulticast()` を貼り直していない**。WiFi 再接続でマルチキャスト購読が
  無効化されると、リンクは復活しても受信できないままになる。down→up 遷移を検出して UDP を貼り直す。
  - リスク: WiFiS3 / ESP32-WiFi で `udp_.stop()→beginMulticast()` の挙動差。実機検証必須。
- マルチキャスト join 失敗時のフォールバック（`begin(port)`）は実際にはマルチキャスト宛を受けられないので
  気休め。コメントを実態に合わせる（通信方式変更＝要件外なのでロジックは触らない）。

## 4. 見送る案（費用対効果・要件超過のため）

- **micros() スピンで発火粒度を 2ms→μs**: audio 23ms / draw 16.7ms に対し 2ms は誤差。効果薄で複雑化。
- **audio バッファ 256**: 11.6→5.8ms だが アンダーラン（音切れ）リスク。「確実動作」優先で 512 止まり。
- **通信方式の変更（ブロードキャスト/ESP-NOW等）**: 要件外。UNO R4 は ESP-NOW 非対応。UDP のまま詰める。

## 5. 5台構成（保留・要確認）

かえるのうたは 1周24拍。輪唱は headRest 8拍刻みなので 0/8/16 で3声がちょうど一巡する。
**4声以上を等間隔で重ねると 24=0（node_02と同位相）/32=8（node_03と同位相）になり破綻**する。
5声化は不等間隔位相 or 楽曲の周期延長＝**編曲（音楽判断）**が必要。鉄則どおり勝手に作曲しないので、
node_05/06 雛形の追加は **master 確認後**に保留。現状の node_02–04（3声）は5台繋いでも壊れない
（5台目以降を繋がなければ3声のまま、繋ぐ場合の位相はチーム判断）。

## 6. 実装項目（このブランチで触る）

- [ ] **A. 指揮者 config**: `node_01` と `node_01_devkitc` の `ProjectConfig.h`
  - `beatLookaheadMs` 50→30、`beatGapMs` 0→2
- [ ] **B. 共通 OrcNetModule**: `common/lib/OrcNetModule/OrcNetModule.{h,cpp}`
  - Sta 側の down→up 遷移で UDP 再 join。`wasLinkUp_` メンバ追加。SoftAp 側は経路を通らず無影響。
- [ ] **C. Processing**: `orchestra_resynth.pde`
  - `getLineOut` バッファ 1024→512、`frameRate(90)` 明示
- [ ] **D. コンパイル確認**: `pio run -d firmware/test_v2/{node_01_devkitc,node_02,node_03,node_04}`
- [ ] **E. 報告**: 変更点・実機確認すべき点・残課題（5台構成・再join のWiFiS3挙動）を master へ

## 7. 触らないもの

- 楽器側 OrcReceiverModule / ProjectConfig（jitter で実機検証済み。loop 2ms・α は維持）
- 拍検出ロジック applyPattern（LPF α・path 閾値・発火タイミングは現設計を温存）
- NoteSenderModule（flush はバースト防止に必要）/ Processing の合成・Voice 本体
- OrcProtocol（パケット 20B 固定）/ 楽譜 score_data（かえるのうた）
