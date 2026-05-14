---
title: タクトーン
description: IMU ジェスチャーで奏でる Arduino オーケストラ — チーム 23 の公式解説サイト
template: splash
hero:
  tagline: 「指揮を振る体験」を主役に、5 台のマイコンと PC でひとつの曲を作る。
  actions:
    - text: プロジェクト概要を読む
      link: /intro/overview/
      icon: right-arrow
      variant: primary
    - text: クイックスタート
      link: /intro/quickstart/
      icon: rocket
---

## このサイトについて

工学院大学 情報通信工学科 ハッカソン課題（チーム 23）の **タクトーン — IMU ジェスチャーで
奏でる Arduino オーケストラ** の公式解説サイトです。**Git や PlatformIO に初めて触れる読者**
でも単独で全体像を追えるよう、用語・図・コード解説を一通り揃えました。

- **聴衆 / 審査員の方** は、まず [プロジェクト概要](/intro/overview/) と
  [なぜ作るのか](/concept/why/) を読むと全体像が掴めます（プレゼン本番 2026-05-20）。
- **新メンバー / 後輩** は、[クイックスタート](/intro/quickstart/) からセットアップして
  [開発ガイド](/guide/setup/) を順に追ってください。
- **既存メンバー** は [アーキテクチャ](/architecture/overview/) と
  [コードを読む](/code/map/) が日常の参照先になります。

## このプロジェクトでできること

- **指揮者の腕を振るだけ** で 4 台の楽器マイコンが同期して演奏する
- **テンポを変えると演奏速度が追従** する（指揮の速さに応じてリアルタイム反映）
- 振り方の方向に依存せず、雑な振りでも拍を取る
- 楽譜を内蔵しているので **PC を曲の途中で起動しても「今の拍」から鳴る**
- 楽器番号付き NOTE で **PC 側の音色（金管・木管・弦など）を切り替え**

## システム構成（一目で）

```
[指揮者 XIAO ESP32-S3 + IMU] ── UDP ──→ [楽器 Arduino UNO R4 WiFi × 3]
                                              │
                                              ↓ USB Serial
                                         [PC: Processing 加算合成]
                                              │
                                              ↓
                                          🔊 スピーカ
```

詳しくは [全体図](/architecture/overview/) を参照。

## サイトの歩き方

| 目的 | おすすめの順路 |
|---|---|
| 何ができるか知りたい | [プロジェクト概要](/intro/overview/) → [シナリオと体験](/concept/scenario/) |
| 仕組みを理解したい | [全体図](/architecture/overview/) → [通信プロトコル](/architecture/protocol/) → [同期戦略](/architecture/sync/) |
| 自分の手で動かしたい | [クイックスタート](/intro/quickstart/) → [Arduino を書き換える](/guide/firmware/) |
| コードを読みたい | [リポジトリ・マップ](/code/map/) → [firmware の歩き方](/code/firmware/) |
| 設計判断の根拠を見たい | [意思決定の記録（ADR）](/decisions/0007-project-purpose-and-scope/) |

困ったら左サイドバーから戻ってきてください。
