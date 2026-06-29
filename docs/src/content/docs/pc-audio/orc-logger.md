---
title: OrcLogger
description: productionのカテゴリ付き標準出力、ring buffer、画面ログpanelを解説する
sidebar:
  order: 11
---

実体: `pc_app/common/OrcLogger.pde`（85行）。

## ログ形式

```text
[HH:MM:SS.mmm] [node] [category] message
```

例:

```text
[00:01:24.381] [N02] [NOTE] C4 vel=96 dur=600ms instr=0(brass)
[00:01:24.512] [CTRL] [UI] state=Conducting mode=1 bpm=99.8 target=100 score=---
[00:01:26.700] [CTRL] [ERROR] マスターリセット検知: UIパケットタイムアウト (2000ms)
```

`println()`へ出すと同時に、画面表示用`logBuffer`へ追加します。

## カテゴリ

| 定数 | 用途 |
|---|---|
| `NOTE` | 発音packet |
| `UI` | state、mode、BPM、score |
| `SERIAL` | portイベント |
| `AUDIO` | 音声系 |
| `STATE` | 状態遷移 |
| `ERROR` | timeoutや異常 |
| `SYSTEM` | 起動、role、filter |
| `METRO` | メトロノーム |

定数は用意されていますが、現行mainですべてのcategoryを使うわけではありません。
文字列を統一することでログ収集側がfilterしやすくなります。

## timestamp

`millis()`を時・分・秒・ミリ秒へ分解します。

```text
ms   = millis % 1000
sec  = floor(millis / 1000) % 60
min  = floor(millis / 60000) % 60
hour = floor(millis / 3600000) % 24
```

これは実時刻ではなくアプリ起動後の経過時刻です。24時間で表示が0へ戻ります。
複数PCのログを壁時計で突き合わせる用途には向きません。必要なら
`java.time`のwall clockまたは共通master timestampを併記します。

## central function

```java
void orcLog(String nodeId, String category, String message){
  String line = ...;
  println(line);
  logBuffer.add(line);
  while (logBuffer.size() > LOG_BUFFER_MAX)
    logBuffer.remove(0);
}
```

最大200行の簡易ring bufferです。`ArrayList.remove(0)`は後続要素をshiftするためO(n)ですが、
200行では問題になりません。高頻度packetをすべて記録するなら`ArrayDeque`へ替えます。

ログ関数はdraw threadから呼ぶ前提です。複数threadから呼ぶと`ArrayList`の同期がありません。
Serial callbackではqueueへ積むだけにし、packetログはhandlePacketで出します。

## 専用helper

### system

```java
orcLogSystem(message)
```

nodeは`SYS`、categoryは`SYSTEM`です。起動、role判定、port filter変更に使います。

### note

`orcLogNote()`はpartIdを `N` + 2桁へし、note名、velocity、duration、
instrumentId、brass/drumを記録します。

partIdは10進の`nf(partId,2)`なので、`0x02`は`N02`です。16進表記ではありません。

### UI

`bpmQ8 / 8.0`でBPMへ戻し、`score=0xFF`を`---`へ変換します。
stateは`stateName()`を使うので未知値もログに残ります。

### serial / error

Serial helperはport名をmessage先頭へ付けます。Error helperは呼び出し側のnode IDを
そのまま使います。現行timeoutは`CTRL`をnode欄として使っています。

## 画面panel

`drawLogPanel(x,y,w,h,maxLines)`は:

1. 共通`drawPanel`
2. buffer総行数
3. contentを`clip`
4. 末尾`maxLines`件
5. category文字列で色分け
6. `noClip()`

色:

- ERROR: red
- NOTE: blue
- UI: green
- その他: gray

判定は構造化objectではなく、完成文字列の`"[ERROR]"`などを検索します。
message内に同じ文字列があると誤って色が変わる可能性があります。

現行productionの7画面は`drawLogPanel()`を常時表示していませんが、検証スケッチや
dashboardから利用できます。標準出力にはすべて残ります。

## AIデバッグで使う場合

コメントに「AIデバッグ対応」とあるのは、固定形式でstdoutへ出し、実行ログを
機械的に分類できるためです。

ログを渡すときは次を含めると原因を追いやすくなります。

- 起動から異常までを切らない
- SYSTEMのrole判定
- UIのstate/mode/target/score
- NOTEのpart/instrument/duration
- ERROR前後2秒
- 接続port名

一方、ログにはSerial packetの全20 B、seq、timestampは現在含みません。packet欠落や
offset問題を追うには、debug buildまたはhex dumpを一時追加します。

## 改善候補

- categoryとnodeを持つrecordを保存し、描画時に文字列検索しない
- fileへ非同期出力する
- wall clockと`millis()`を両方記録する
- packet seqとsource portをNOTE/UIに追加する
- level（debug/info/warn/error）を導入する
- 200行の`ArrayDeque`化

ログ出力中に音が途切れる場合は、NOTEごとの`println()`量を減らすか非同期化してください。
