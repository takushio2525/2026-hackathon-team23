# architecture_reference — Embedded-Module-Architecture 参照資料

本フォルダは、本ハッカソンの Arduino 系ファームウェア（`firmware/` 配下、塩澤担当）が
**全面採用** している組み込み向け設計パターン
**Embedded-Module-Architecture（以下 EMA）** の参照資料を、リポジトリ内に取り込んだものです。

design_draft（基本設計・詳細設計の原案）は **EMA を前提として記述** されているため、
レビュー・実装・AI（Claude Code 等）による補助コーディングのいずれでも、本フォルダの
資料を「正本」として参照してください。

## 採用元リポジトリ

- **GitHub**: <https://github.com/takushio2525/Embedded-Module-Architecture>
- **作成者**: 塩澤匠生（本人作成のリファレンス実装）
- **採用判断**: ADR-0005（[`docs/decisions/0005-firmware-embedded-module-architecture.md`](../../../../docs/decisions/0005-firmware-embedded-module-architecture.md)）
- **取り込み日**: 2026-04-24（取り込み時点の上流コミットに基づくスナップショット）

> 上流が更新された場合は、本フォルダの内容も追従させること。
> 設計書（`design_draft/` および後続の `report/` の TeX）と本フォルダの記述が
> 食い違ったら **本フォルダ（= EMA リポジトリ）の側が正** とする。

## ファイル一覧

| パス | 用途 | 上流での原本 |
|---|---|---|
| `ARCHITECTURE.md` | アーキテクチャの構造ガイド（人間 + AI 向け） | [`Embedded-Module-Architecture/ARCHITECTURE.md`](https://github.com/takushio2525/Embedded-Module-Architecture/blob/main/ARCHITECTURE.md) |
| `CLAUDE.md` | AI（Claude Code）向けの実装ルール詳細指示 | [`Embedded-Module-Architecture/CLAUDE.md`](https://github.com/takushio2525/Embedded-Module-Architecture/blob/main/CLAUDE.md) |
| `pdf/01_教科書.pdf` | クラス基礎から 3 フェーズモデルまでの段階的学習資料 | `docs/01_教科書.pdf` |
| `pdf/02_実装ガイド.pdf` | sample/ コードを題材にした適用方法の解説 | `docs/02_実装ガイド.pdf` |
| `pdf/03_設計仕様書.pdf` | ルール集・API 仕様（リファレンス） | `docs/03_設計仕様書.pdf` |

## EMA の核となる 4 つの取り決め（要点だけ）

詳細は `ARCHITECTURE.md` / `CLAUDE.md` / `pdf/03_設計仕様書.pdf` を参照。
本ハッカソンの設計書ではこの 4 点を **無条件の前提** として扱う。

1. **`IModule` インターフェース** — `init()` / `updateInput(SystemData&)` /
   `updateOutput(SystemData&)` / `deinit()` の 4 メソッドで全ハードウェアモジュールを統一。
   `init()` のみ純粋仮想、残り 3 つはデフォルト空実装。
2. **3 フェーズ実行モデル** — `loop()` で「入力配列の `updateInput` → ロジック関数
   `applyPattern(systemData)` → 出力配列の `updateOutput`」を必ずこの順で回す。
3. **`SystemData` 集約パターン** — モジュール間の状態共有は `SystemData` 構造体に
   `{Module}Data` フィールドを並べる方式で行い、モジュール同士の直接呼び出しを禁止。
4. **`ProjectConfig` 集約パターン** — 各モジュールの設定は `{Module}Config {MODULE}_CONFIG`
   インスタンスとして `include/ProjectConfig.h` に集約。共有バスピン（SPI/I2C）のみ
   `constexpr` で別途定義。

## design_draft との対応

| design_draft の章 | 対応する EMA 資料 |
|---|---|
| §5.4 ファームウェア設計方針 | `ARCHITECTURE.md` 全体 |
| §6 共通インターフェース方針 | `ARCHITECTURE.md`「IModule」「3 フェーズ実行モデル」「モジュールの構造」 |
| §8 ファイル構成 | `ARCHITECTURE.md`「レイヤー構成」「新規モジュール追加チェックリスト」 |
| §10 共通層 API 仕様（`IModule` / `ModuleTimer`） | `ARCHITECTURE.md`「IModule インターフェース」、`pdf/03_設計仕様書.pdf` |
| §11 / §12 各ノード詳細設計 | `pdf/02_実装ガイド.pdf`（sample/ の各モジュール解説） |

## 不要になったら

事前課題提出後、design_draft 全体が `report/` 配下の TeX に統合される。
TeX 化が完了し、上流 EMA リポジトリへの直接リンクで十分になった時点で本フォルダごと
削除してよい（その場合は design_draft / report 側のリンクも EMA リポジトリ直リンクへ
張り替えること）。
