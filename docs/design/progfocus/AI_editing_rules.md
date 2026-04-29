# AI向けMarkdown編集ルール（progFocus）

> **このドキュメントは、progFocusのエクスポートファイル（.md）をAIが解析・編集・生成するためのルール集です。**

---

## 出力形式（最優先ルール）

**生のJSON出力は禁止。** 必ず以下の構造を持つ完全なMarkdownファイルとして出力すること。

### 実際のファイル内容（これが `.md` ファイルとして保存される内容）

ファイルの中身は以下の3要素だけで構成される。`~~~markdown` は含めない。

1. **フロントマター**: `---` で開始し `---` で終了するYAMLブロック（ファイルの先頭）
2. **空行**: 1行
3. **JSONコードブロック**: 3つのバッククォート+`json` で開始し、3つのバッククォートのみの行で終了

```
---                          ← ファイルの先頭行
format: progfocus.markdown.v1
exportedAt: 2026-01-01T00:00:00.000Z
projectId: my-project
projectName: マイプロジェクト
mode: direct
nodeCount: 3
connectionCount: 2
---                          ← フロントマター終了
                             ← 空行（必須）
```json                      ← JSONブロック開始
{
  "project": { ... }
}
```                          ← JSONブロック終了（ファイルの最終行）
```

### チャットでの出力方法（表示用ラッパー）

チャットUIでは内側のバッククォートが誤解釈されるため、**外側を `~~~markdown` 〜 `~~~` で囲んで**出力する。これはチャット表示用のラッパーであり、ファイル内容の一部ではない。

````
~~~markdown                  ← チャット表示用（ファイルには含まれない）
---
format: progfocus.markdown.v1
exportedAt: 2026-01-01T00:00:00.000Z
projectId: my-project
projectName: マイプロジェクト
mode: direct
nodeCount: 3
connectionCount: 2
---

```json
{
  "project": { ... }
}
```
~~~                          ← チャット表示用（ファイルには含まれない）
````

- 言語タグ `markdown` を付けることで、チャットUIがコードブロックとして認識しコピーボタンを表示する
- 外側に `~~~` を使うことで、内側の ` ``` `（バッククォート）と干渉せずネストできる
- フロントマターとJSONを別々のブロックに分けない

### ⚠️ コピーボタンが表示されない場合の対処

一部のAI（Gemini等）ではコードブロックにコピーボタンが表示されないことがある。その場合：
- ユーザーが手動でコピーすると `~~~markdown` と `~~~` がファイル内容に混入する可能性がある
- **progFocusのパーサーは `~~~markdown` ラッパーを自動的に除去する**ので、混入してもインポートは正常に動作する
- ただしAIとしては、可能な限り `~~~markdown` ラッパーなしのファイル内容だけを出力する方が望ましい

### 出力完了前の必須チェック

- `nodeCount` と `connectionCount` がJSON内の実際の要素数と一致しているか
- チャット出力の場合: `~~~markdown` で始まり `~~~` で終わっているか
- 3つのバッククォート+`json` の開始行が存在するか
- JSONの閉じ `}` の次の行に閉じの3つのバッククォートがあるか
- JSONが有効な構文であるか

---

## アプリ概要

- progFocusは「目的→仕様→構成」へ段階的に焦点を絞る無限キャンバス型プランニングツール
- **データフロー図**として機能: 入力→処理→出力の流れを左から右へ配置
- ルート直下に大枠の機能（feature系）を置き、内部により具体的なノードを配置する
- 生成するMarkdownは「設計スナップショット」。追加要求が来たらノード・接続を追記して返す

---

## ノードタイプ

### アトミックノード（子階層なし）

| タイプ | 用途 | 例 |
|--------|------|-----|
| `input` | 外部入力・取得 | フォーム入力、API取得、センサー信号 |
| `process` | 処理・計算・変換 | バリデーション、PWM算出、データ変換 |
| `output` | 出力・保存・表示 | 画面表示、モーター駆動、通知 |

### コンテナノード（ダブルクリックで子階層へ）

| タイプ | 用途 | 例 |
|--------|------|-----|
| `feature` | 汎用機能の入れ物 | 認証機能、データ管理 |
| `feature_input` | 入力系機能のまとまり | コントローラー入力、センサー群 |
| `feature_process` | 処理系機能のまとまり | 移動情報処理、制御ロジック |
| `feature_output` | 出力系機能のまとまり | モータードライブ、アクチュエータ |

---

## 階層設計

### 基本パターン: 2層構造

1. **ルートレベル**: feature系ノードで大枠を左→右に配置し、**feature同士を接続**する
   - 例: `feature_input`(入力) → `feature_process`(処理) → `feature_output`(出力)
   - **ルートレベルの接続は必ず作成すること。featureが孤立している出力は不完全。**
2. **子レベル**: 各feature内部にinput→process→outputを配置し、**同じfeature内のノード同士だけを接続**

### ⚠️ 接続の親制約（絶対ルール）

**接続は同じ `parentId` を持つノード間のみ作成できる。異なる親の子ノード同士の接続は禁止。**

- ルートレベル: `parentId: null` 同士のみ接続可能
- 子レベル: 同じ `parentId` を持つノード同士のみ接続可能

❌ 禁止: `in-ir`(parentId: "feat-sensor") → `proc-wall`(parentId: "feat-brain") ← 親が違う
✅ 正しい: `feat-sensor`(parentId: null) → `feat-brain`(parentId: null) ← 同じ親(null)

### 複数ライン設計

- 独立した処理系統が複数ある場合、y座標を変えて平行に配置する
- 共通の入力源から分岐する場合、入力ノードの`bottom`から下のラインへ接続

### フィードバックループの表現

- センサーからの戻り信号やリミット検出は、逆方向の接続で表現
- 視認性のため、下側(`bottom`)を経由させて戻す

### 同種ノードの直列配置（縦並び）

同じタイプのノードが連続する場合は**縦に積む**:
- x座標を揃え、y座標を+220〜240pxずつ増加
- 接続は `bottom` → `top` で繋ぐ
- 最後のノードから次の種類へは `right` → `left` で右方向へ

```
[input]  →  [process1]  →  [output]
 x=200       x=620          x=1100
 y=60        y=60           y=60
                ↓ (bottom→top)
            [process2]
             x=620
             y=300
                ↓ (bottom→top)
            [process3] ─→ (right→left)
             x=620
             y=520
```

---

## 配置ガイドライン

### 基本原則

- **左→右フロー**: 入力(左) → 処理(中央) → 出力(右)
- **基準寸法**: `width=256`, `height=160`
- **グリッド**: 座標は20pxの倍数に揃える
- **推奨間隔**: 水平80px以上、垂直60px以上
- **高さは可変**: 長文タイトルや複数行メモの場合、上下に+40〜80pxの余白を確保

### x座標の配置

| 役割 | ルートレベル | 子レベル |
|------|-------------|---------|
| 入力 | x=100 | x=40〜140 |
| 処理 | x=520〜620 | x=440〜620 |
| 出力 | x=1000〜1100 | x=880〜1100 |

### y座標（複数ラインの場合）

| ライン | y座標 | 間隔 |
|--------|-------|------|
| 1行目 | y=140〜180 | - |
| 2行目 | y=400〜440 | 約260px |
| 3行目 | y=660〜700 | 約260px |

### 子ノード配置の目安

- 親feature内での配置も左→右の原則に従う
- 子ノード同士の間隔: 水平方向260〜520px、垂直方向200〜260px

---

## 接続（矢印）仕様

### 方向の原則

| パターン | fromSide | toSide | 用途 |
|----------|----------|--------|------|
| 順方向 | `right` | `left` | データの流れ（基本） |
| 分岐 | `bottom` | `left` | 下のラインへ接続 |
| 直列 | `bottom` | `top` | 同種ノードの縦接続 |
| フィードバック | `bottom` | `bottom` | 戻り接続 |

### ラベル

- 初期値は空文字 `""`
- 内容を入れる場合は先頭に `• ` を付ける（例: `"• データ"`, `"• PWM信号"`）
- `labelPosition` は省略可（デフォルト `{"x":0,"y":0}`）。混み合う場合のみ±20/±40で調整
- `labelHidden` は通常省略（消したいときだけ `true`）

---

## ファイルフォーマット詳細

- フォーマットID: `progfocus.markdown.v1`（変更禁止）
- フロントマター必須キー: `format`, `exportedAt`(ISO8601), `projectId`, `projectName`, `mode`(`direct`|`interactive`), `nodeCount`, `connectionCount`
- JSON構造: `{ "project": Project }`
  - `project`: `id`, `name`, `mode`, `createdAt`, `updatedAt`, `rootNodeIds`, `nodes`, `connections`, `definitionRegistry`
  - `nodes[<id>]`: `id`, `type`, `title`, `memo`, `x`, `y`, `width`, `height`, `parentId`, `programDef`(optional), `createdAt`, `updatedAt`
  - `connections[<id>]`: `id`, `fromNodeId`, `fromSide`, `toNodeId`, `toSide`, `label`, `labelPosition`, `labelHidden`

---

## programDef仕様

ノードに `programDef` フィールドでプログラム要素の定義を付与できる（省略可）。

### 種別一覧

| 種別 | elementType | 主要フィールド |
|------|-------------|---------------|
| クラス | `class` | className, methods, properties, description |
| メソッド | `method` | className, methodName, args, returnValue, visibility |
| インターフェース | `interface` | interfaceName, methods, properties |
| 関数 | `function` | functionName, args, returnValue |
| 変数 | `variable` | variableName, variableType, initialValue |
| 構造体 | `struct` | structName, fields |
| 列挙型 | `enum` | enumName, values |
| モジュール | `module` | moduleName, exports |
| なし | `none` | （なし） |

全ての種別に `fileName` と `description` フィールドがある。

### 例

```json
"programDef": {
  "elementType": "class",
  "fileName": "auth.ts",
  "className": "AuthService",
  "methods": "login\nlogout\nverifyToken",
  "properties": "token: string\nuser: User",
  "description": "認証処理を担当"
}
```

### definitionRegistry

`project.definitionRegistry` にプロジェクト全体の名前一覧を保持する。

```json
"definitionRegistry": {
  "fileNames": ["auth.ts"],
  "classNames": ["AuthService"],
  "methodNames": ["login"],
  "interfaceNames": [],
  "functionNames": [],
  "variableNames": [],
  "structNames": [],
  "enumNames": [],
  "moduleNames": []
}
```

- ノードで使用している名前は必ずレジストリにも含めること
- 新規追加時はレジストリにも同時追加する

---

## 編集チェックリスト

1. `format` を変更しない
2. `nodeCount` と `connectionCount` を実際の要素数と一致させる
3. `parentId=null` のノードを `rootNodeIds` に全て含める
4. 座標は20pxグリッドに揃える。サイズは基本 `256×160`
5. `createdAt` は変更不要。`updatedAt` は編集した要素のみ更新
6. **接続の両端ノードが同じ `parentId` を持つか検証する**
7. **ルートレベルのfeature同士の接続を作成する（孤立featureは不完全）**
8. **チャット出力時は `~~~markdown` 〜 `~~~` で囲む（ファイル保存時は不要。パーサーが自動除去する）**

---

## 完全な出力例

以下は「ユーザー認証機能」の例。チャットUIのコピーボタンで一括コピーし、`.md` ファイルとして保存できる。

````
~~~markdown
---
format: progfocus.markdown.v1
exportedAt: 2026-01-17T00:00:00.000Z
projectId: auth-sample
projectName: ユーザー認証機能
mode: direct
nodeCount: 7
connectionCount: 6
---

```json
{
  "project": {
    "id": "auth-sample",
    "name": "ユーザー認証機能",
    "mode": "direct",
    "createdAt": 1705017600000,
    "updatedAt": 1705017600000,
    "rootNodeIds": ["input-form", "process-validate", "process-auth", "process-session", "output-result", "input-db", "output-log"],
    "nodes": {
      "input-form": {
        "id": "input-form",
        "type": "input",
        "title": "ログインフォーム",
        "memo": "メールアドレス\nパスワード",
        "x": 100, "y": 60, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      },
      "process-validate": {
        "id": "process-validate",
        "type": "process",
        "title": "入力バリデーション",
        "memo": "形式チェック\n空欄チェック",
        "x": 520, "y": 60, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      },
      "process-auth": {
        "id": "process-auth",
        "type": "process",
        "title": "認証処理",
        "memo": "DB照合\nパスワード検証",
        "x": 520, "y": 280, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      },
      "process-session": {
        "id": "process-session",
        "type": "process",
        "title": "セッション生成",
        "memo": "トークン発行\nCookie設定",
        "x": 520, "y": 500, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      },
      "output-result": {
        "id": "output-result",
        "type": "output",
        "title": "認証結果",
        "memo": "成功: ダッシュボードへ\n失敗: エラー表示",
        "x": 1000, "y": 60, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      },
      "input-db": {
        "id": "input-db",
        "type": "input",
        "title": "ユーザーDB",
        "memo": "",
        "x": 100, "y": 280, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      },
      "output-log": {
        "id": "output-log",
        "type": "output",
        "title": "認証ログ",
        "memo": "成功/失敗を記録",
        "x": 1000, "y": 280, "width": 256, "height": 160,
        "parentId": null,
        "createdAt": 1705017600000, "updatedAt": 1705017600000
      }
    },
    "connections": {
      "conn-1": {
        "id": "conn-1",
        "fromNodeId": "input-form", "fromSide": "right",
        "toNodeId": "process-validate", "toSide": "left",
        "label": "• 入力データ"
      },
      "conn-2": {
        "id": "conn-2",
        "fromNodeId": "process-validate", "fromSide": "bottom",
        "toNodeId": "process-auth", "toSide": "top",
        "label": ""
      },
      "conn-3": {
        "id": "conn-3",
        "fromNodeId": "process-auth", "fromSide": "bottom",
        "toNodeId": "process-session", "toSide": "top",
        "label": ""
      },
      "conn-4": {
        "id": "conn-4",
        "fromNodeId": "process-session", "fromSide": "right",
        "toNodeId": "output-result", "toSide": "left",
        "label": "• 認証トークン"
      },
      "conn-5": {
        "id": "conn-5",
        "fromNodeId": "input-db", "fromSide": "right",
        "toNodeId": "process-auth", "toSide": "left",
        "label": "• ユーザー情報"
      },
      "conn-6": {
        "id": "conn-6",
        "fromNodeId": "process-auth", "fromSide": "right",
        "toNodeId": "output-log", "toSide": "left",
        "label": "• ログ出力"
      }
    },
    "definitionRegistry": {
      "fileNames": [], "classNames": [], "methodNames": [],
      "interfaceNames": [], "functionNames": [], "variableNames": [],
      "structNames": [], "enumNames": [], "moduleNames": []
    }
  }
}
```
~~~
````

### 構造解説

```
[ログインフォーム]  →  [入力バリデーション]  →  [認証結果]
     (input)              (process)              (output)
     x=100                 x=520                  x=1000
     y=60                  y=60                   y=60
                              ↓ (bottom→top)
[ユーザーDB]  →  [認証処理]  →  [認証ログ]
   (input)        (process)       (output)
   x=100          x=520           x=1000
   y=280          y=280           y=280
                      ↓ (bottom→top)
                 [セッション生成] ─→ (right→left で output-result へ)
                    (process)
                    x=520, y=500
```

- **processの直列は縦に積む**: validate → auth → session を y=60, 280, 500 で縦並び
- **複数の入力源は左側に並べる**: form と DB を x=100 で揃え、y で分離
- **副出力は横に出す**: 認証ログを process-auth から右へ分岐

---

## 設計例: ロボット操縦システム

### ルートレベル構成

```
[コントローラー入力]  →  [足回り移動情報処理]  →  [モータードライブ]
  (feature_input)         (feature_process)         (feature_output)
      x=100                   x=620                    x=1080
      y=180                   y=180                    y=180
         │
         └──────→  [取得機構制御]  →  [取得アーム]
                   (feature_process)   (feature_output)
                       x=620              x=1080
                       y=440              y=440
                         ↑____フィードバック____│
```

### feature内部の構成例

**「足回り移動情報処理」内部:**
```
[スティック入力情報]  →  [PWM算出]  →  [PWM信号出力]
     (input)            (process)       (output)
     x=40               x=560           x=1000
```

**「取得アーム」内部:**
```
[PWM/GPIO信号]  →  [サーボモーター駆動]  →  [サーボモーター]
   (input)            (process)              (output)
                          ↑
                   [リミットセンサー]（フィードバック用input）
```

### 設計のポイント

1. **ルートは機能単位で分割**: 「何をするか」でfeature系に分ける
2. **子は処理ステップで分割**: 「どう処理するか」でinput/process/outputに分ける
3. **複数系統は上下に分離**: メイン系統(y=180)とサブ系統(y=440)
4. **フィードバックは下経由**: `bottom`→`bottom`で視覚的に区別

---

## 最終確認（出力前に必ず読むこと）

1. 出力形式: `~~~markdown` → フロントマター(`---`〜`---`) → 空行 → JSONブロック(` ``` `+`json` 〜 ` ``` `) → `~~~`
2. 出力全体を `~~~markdown` 〜 `~~~` で囲み、チャットUI上で1つのコードブロックにする
3. JSONブロックの閉じの3つのバッククォートを**絶対に省略しない**
4. `~~~` の閉じ行が**出力の最終行**（その後に何も追加しない）
5. 接続は同じ `parentId` のノード間のみ
6. `nodeCount`/`connectionCount` が実際の数と一致
7. `rootNodeIds` に `parentId=null` の全ノードを含める
