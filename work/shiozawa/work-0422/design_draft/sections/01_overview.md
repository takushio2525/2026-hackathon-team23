# 1. 概要

## 1.1 プロジェクトテーマ

チーム23（6名）は、2026 年度前学期ハッカソン1 で **「Arduino UNO R4 WiFi × 5 台による
楽器間同期演奏システム（Arduino オーケストラ）」** を開発する。指揮者マイコン 1 台が
内蔵 IMU で指揮者の動きを捉え、楽器マイコン 4 台へ演奏制御コマンドを WiFi + UDP で配信
する。楽器マイコンは自分のパートを進行させて発音情報（NOTE）を PC（Processing）へ
送出し、PC 側で金管楽器の音色合成・スピーカ再生を行う。

システム全体像は [`docs/overview.md`](../../../../../docs/overview.md) および
[`docs/design/architecture.md`](../../../../../docs/design/architecture.md) を参照。
採用判断の経緯は [`docs/decisions/`](../../../../../docs/decisions/)（ADR-0002〜0005）に記録している。

## 1.2 本設計書のスコープ

本設計書がカバーするのは、**Arduino マイコン 5 台で動作するファームウェア全般**（リポジトリ
ルート配下 `firmware/` 全域）である。第2回ミーティング（2026-04-22）で担当範囲が拡大し、
指揮者ノードだけでなく楽器ノード 4 台の Arduino コードも塩澤が一括で設計することになった。

| 含む | 含まない |
|---|---|
| `firmware/common/lib/`（共通層: `IModule` / `ModuleTimer` / `SystemData` / `ProjectConfig` / 通信プロトコル） | Processing 側の音色合成コード（担当: 梅澤） |
| `firmware/node_01/`（指揮者ノード） | 楽譜データそのものの選定・編曲（チーム共同） |
| `firmware/node_02/`〜`firmware/node_05/`（楽器ノード） | PC ↔ Arduino 間の音響面の詰め（Processing 側） |
| 上記に関わる `ProjectConfig`・状態遷移・通信フォーマット | チーム全体のスケジュール・発表準備 |

なお、他メンバーの担当（齋藤: 音階生成、梅澤: Processing 他）は Arduino 側の基盤が
できてからすり合わせる方針である（[`docs/roles.md`](../../../../../docs/roles.md) の
担当拡大反映は本原案と同時並行で実施）。

## 1.3 採用アーキテクチャ（前提）

`firmware/` 配下は **Embedded-Module-Architecture（以下 EMA）** に全面準拠する
（[ADR-0005](../../../../../docs/decisions/0005-firmware-embedded-module-architecture.md)）。
EMA は塩澤本人が作成・公開している組み込み用設計パターンで、`IModule` インターフェース・
3 フェーズ実行モデル・`SystemData` 集約・`ProjectConfig` 集約を中核とする。

本設計書では EMA の概念・命名規則・ファイル構成を **既知のものとして** 参照する
（基本概念は §5.4 / §6、詳細 API は §10、各モジュールへの適用は §11 / §12）。

EMA の参照資料は同階層の [`../../architecture_reference/`](../../architecture_reference/) に
リポジトリ内取り込み済み。

| ファイル | 用途 |
|---|---|
| [`../../architecture_reference/README.md`](../../architecture_reference/README.md) | フォルダの目的と原典リンク |
| [`../../architecture_reference/ARCHITECTURE.md`](../../architecture_reference/ARCHITECTURE.md) | 構造ガイド（人間 + AI 向け） |
| [`../../architecture_reference/CLAUDE.md`](../../architecture_reference/CLAUDE.md) | AI 向け実装ルール詳細 |
| [`../../architecture_reference/pdf/01_教科書.pdf`](../../architecture_reference/pdf/01_教科書.pdf) | クラス基礎 → 3 フェーズモデルの段階学習 |
| [`../../architecture_reference/pdf/02_実装ガイド.pdf`](../../architecture_reference/pdf/02_実装ガイド.pdf) | sample/ コードを題材にした適用方法 |
| [`../../architecture_reference/pdf/03_設計仕様書.pdf`](../../architecture_reference/pdf/03_設計仕様書.pdf) | ルール集・API 仕様 |

採用元リポジトリ: <https://github.com/takushio2525/Embedded-Module-Architecture>

> 設計書本文と本フォルダ／上流リポジトリの記述が食い違った場合、**EMA 側を正** とする。
> 本設計書の章は EMA をハッカソン要件に当てはめた具体化であり、用語定義そのものを
> 上書きしない。

## 1.4 読者想定

- **主読者**: チーム23 のメンバー（他マイコン担当・Processing 担当・議事録担当）
- **副読者**: ハッカソン担当 TA・教員（評価者）
- 前提知識: Arduino プログラミング基礎、UDP 通信の概念、C++ クラスの基本
- EMA の予習: 未読でも本書だけで設計意図は追える構成にしているが、実装に入る前に
  少なくとも `../../architecture_reference/pdf/01_教科書.pdf` の第 2 章までは目を通すことを推奨

## 1.5 本原案が対応する事前課題

- **課題名**: ハッカソン1 事前課題「担当箇所の基本設計・詳細設計の原案作成」
- **締切**: 2026-04-29 09:00
- **提出形態**: PDF + TeX ソース（本原案は Markdown 版。TeX 化・PDF 化は内容合意後のフェーズで実施）
- **位置付け**: Week 3 の設計書原案。Week 4 でチームとして確定計画書に統合される予定
