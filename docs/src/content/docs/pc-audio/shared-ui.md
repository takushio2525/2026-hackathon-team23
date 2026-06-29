---
title: SharedUI
description: 日本語font選択、背景、panel、waveform、titleを共通化する描画関数の契約
sidebar:
  order: 10
---

実体: `pc_app/common/SharedUI.pde`（71行）。

## 位置づけ

SharedUIは画面遷移を持ちません。production mainや検証スケッチが使う、状態を持たない
描画部品を集めています。

| 関数 | 役割 |
|---|---|
| `loadJapaneseFont()` | OSで使える日本語fontを探す |
| `drawBackground()` | 背景色、装飾円、50 px grid |
| `drawPanel()` | shadow付き白panel |
| `mouseOver()` | 矩形hit test |
| `lighten()` | RGBを明るくする |
| `drawScope()` | `out.left`のwaveform |
| `drawPageTitle()` | titleとsubtitle |

## 日本語font

候補順:

1. Hiragino Sans系
2. Yu Gothic
3. Meiryo
4. Noto Sans CJK JP / Noto Sans JP
5. Arial Unicode MS

`PFont.list()`を走査し、大文字小文字を無視して完全一致した最初のfontを
`createFont(name, size, true)`で返します。見つからなければnullです。

mainはnull時に `SansSerif` へfallbackします。SansSerifが日本語glyphを持つ保証はないため、
文字化けする環境ではNoto Sans JPをOSへ入れるか、font fileをdataへ同梱する必要があります。

font検索は起動時だけです。draw内で呼ぶと全font一覧の走査と生成が毎frame発生します。

## 背景

```java
background(238, 247, 255);
```

その上にyellow、blue、green、redの半透明ellipseを四隅へ置き、50 px間隔のgridを引きます。
固定1000×560画面に最適化されていますが、`width`と`height`を使う部分はresizeにも追従します。

描画関数はProcessingのfill、stroke、textAlignなどのglobal drawing stateを変更します。
呼び出し側は必要なstyleを毎回明示する設計で、`pushStyle()/popStyle()`による隔離は
使っていません。

## panel

`drawPanel(x,y,w,h)`は:

1. 右8 px、下10 pxに半透明shadow
2. 白い角丸矩形
3. 青い3 px border
4. strokeWeightを1へ戻しnoStroke

を描きます。contentのpaddingは関数で強制せず、呼び出し側が通常14〜22 px空けます。

## hit testとlighten

```java
boolean mouseOver(float x, float y, float w, float h){
  return mouseX >= x && mouseX <= x+w
      && mouseY >= y && mouseY <= y+h;
}
```

境界を含みます。Port Selectではclip viewportのhit testと行のhit testを両方行い、
見えない行をクリックしないようにします。

`lighten(color, amount)`は各RGB channelへamountを足して255でclampします。
alphaは保持せず、返り値は不透明色です。

## waveform

`drawScope()`はpanel内に `out.left` の現在bufferを折れ線で描きます。

```text
x_i = x + 20 + (w - 40) × i / (bufferSize - 1)
y_i = centerY - out.left[i] × 0.35h
```

表示は左channelだけです。金管とクリックは両channel同値なので通常は十分ですが、
今後panningを追加するなら右channelまたはL/R両方を描きます。

このscopeは観測用で、clip検出を数値化していません。振幅がpanel上下へ張り付く場合は
master volumeを下げます。厳密なclip警告が必要ならbufferの`abs(max)`を測り、
1.0以上を記録します。

## title

`drawPageTitle(title, subtitle)`は固定位置:

```text
title    x=168, y=52, 34 px
subtitle x=170, y=78, 15 px
```

Port Selectを含む全画面で同じheader位置を保ちます。left側168 pxはロゴや余白を
想定した値で、現在は関数内にロゴ描画を持ちません。

## main側に残るUI

次はproduction固有なのでSharedUIにありません。

- Port Selectのscroll/filter
- Waitingの状態文言
- Menuの2カード
- Free Playのpart一覧
- Gameの56 dot、guide、score
- Resultのscore色
- Analyzerの直近event
- help panelとrole表示

共通化するなら、値をglobalから直接読む関数ではなく、引数として渡す方が
検証スケッチで再利用しやすくなります。

## 変更時の確認

- font fallbackで日本語が出るか
- `textAlign`や`strokeWeight`が次の描画へ漏れていないか
- 512 sample scopeが画面幅へ正しくmapされるか
- panel borderとclipが重ならないか
- color contrastがMenuのselected/unselectedで十分か

画面遷移は [メイン構造](/pc-audio/resynth-main/)、
ログpanelは [OrcLogger](/pc-audio/orc-logger/) を参照してください。
