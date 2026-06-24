"""齋藤担当の発表用スライドPDFを生成する。"""

from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


OUT_DIR = Path(__file__).parent
OUT_PDF = OUT_DIR / "saito_presentation_summary.pdf"
PAGE_W, PAGE_H = 13.333 * inch, 7.5 * inch  # 16:9

FONT = "AppleGothic"
FONT_BOLD = "AppleGothic"
FONT_PATH = "/System/Library/Fonts/Supplemental/AppleGothic.ttf"

NAVY = HexColor("#111827")
NAVY_2 = HexColor("#1E293B")
WHITE = HexColor("#F8FAFC")
MUTED = HexColor("#CBD5E1")
TEAL = HexColor("#5EEAD4")
SKY = HexColor("#7DD3FC")
VIOLET = HexColor("#C4B5FD")
AMBER = HexColor("#FCD34D")
CORAL = HexColor("#FDA4AF")
SLATE = HexColor("#334155")
SLATE_LIGHT = HexColor("#475569")


def register_fonts():
    # PDF単体でCJK文字を表示できるよう、macOSのTrueTypeフォントを埋め込む。
    pdfmetrics.registerFont(TTFont(FONT, FONT_PATH))


def text_width(text, size):
    return pdfmetrics.stringWidth(text, FONT, size)


def split_text(text, size, max_width):
    """日本語を含む文字列を、幅に収まる行へ分割する。"""
    lines = []
    current = ""
    for char in text:
        if char == "\n":
            lines.append(current)
            current = ""
            continue
        candidate = current + char
        if current and text_width(candidate, size) > max_width:
            lines.append(current)
            current = char
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def draw_wrap(c, text, x, y, max_width, size=18, color=WHITE, leading=None):
    leading = leading or size * 1.45
    c.setFillColor(color)
    c.setFont(FONT, size)
    for line in split_text(text, size, max_width):
        c.drawString(x, y, line)
        y -= leading
    return y


def rounded(c, x, y, w, h, fill, radius=14, stroke=None):
    c.setFillColor(fill)
    if stroke:
        c.setStrokeColor(stroke)
        c.setLineWidth(1)
    else:
        c.setStrokeColor(fill)
    c.roundRect(x, y, w, h, radius, fill=1, stroke=1 if stroke else 0)


def section(c, number, label, title, subtitle=None):
    c.setFillColor(NAVY)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    c.setFillColor(TEAL)
    c.rect(42, PAGE_H - 48, 88, 4, fill=1, stroke=0)
    c.setFillColor(MUTED)
    c.setFont(FONT, 12)
    c.drawString(42, PAGE_H - 37, label.upper())
    c.setFillColor(WHITE)
    c.setFont(FONT_BOLD, 30)
    c.drawString(42, PAGE_H - 86, title)
    if subtitle:
        c.setFillColor(MUTED)
        c.setFont(FONT, 14)
        c.drawString(42, PAGE_H - 110, subtitle)
    c.setStrokeColor(SLATE_LIGHT)
    c.setLineWidth(0.6)
    c.line(42, 28, PAGE_W - 42, 28)
    c.setFillColor(MUTED)
    c.setFont(FONT, 11)
    c.drawString(42, 12, "Arduino Orchestra / Team 23 / 齋藤翔太")
    c.drawRightString(PAGE_W - 42, 12, f"{number:02d}")


def bullet(c, x, y, text, width, accent=TEAL, size=17):
    c.setFillColor(accent)
    c.circle(x + 5, y + 3, 4, fill=1, stroke=0)
    return draw_wrap(c, text, x + 20, y, width - 20, size=size, color=WHITE)


def card(c, x, y, w, h, title, body, accent=TEAL, body_size=15):
    rounded(c, x, y, w, h, NAVY_2)
    c.setFillColor(accent)
    c.rect(x, y + h - 6, w, 6, fill=1, stroke=0)
    c.setFillColor(WHITE)
    c.setFont(FONT_BOLD, 18)
    c.drawString(x + 18, y + h - 34, title)
    draw_wrap(c, body, x + 18, y + h - 62, w - 36, size=body_size, color=MUTED, leading=body_size * 1.42)


def title_slide(c):
    c.setFillColor(NAVY)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    c.setFillColor(NAVY_2)
    c.circle(PAGE_W - 68, PAGE_H - 62, 178, fill=1, stroke=0)
    c.setFillColor(SLATE)
    c.circle(PAGE_W - 110, 62, 108, fill=1, stroke=0)
    c.setFillColor(TEAL)
    c.rect(52, PAGE_H - 104, 106, 7, fill=1, stroke=0)
    c.setFillColor(MUTED)
    c.setFont(FONT, 16)
    c.drawString(52, PAGE_H - 78, "発表用 個人担当まとめ")
    c.setFillColor(WHITE)
    c.setFont(FONT_BOLD, 43)
    c.drawString(52, PAGE_H - 170, "楽譜データから")
    c.drawString(52, PAGE_H - 224, "4声輪唱をつくる")
    c.setFillColor(SKY)
    c.setFont(FONT, 21)
    c.drawString(54, PAGE_H - 274, "共通譜・音域設計・ドラム伴奏の調整")

    rounded(c, 52, 88, 620, 94, NAVY_2)
    c.setFillColor(TEAL)
    c.setFont(FONT, 15)
    c.drawString(76, 148, "担当")
    c.setFillColor(WHITE)
    c.setFont(FONT_BOLD, 18)
    c.drawString(76, 116, "楽譜データ / 音階・音域の設計 / 確認用スケッチ")
    c.setFillColor(MUTED)
    c.setFont(FONT, 14)
    c.drawString(52, 50, "チーム23  齋藤翔太  |  2026年6月")
    c.showPage()


def scope_slide(c):
    section(c, 2, "ROLE", "担当範囲：演奏の設計を、再生できるデータにする", "Arduino実装担当と連携し、楽譜とパート差分を整理")
    x0, y, w, h, gap = 48, 230, 190, 180, 20
    cards = [
        ("1. 共通譜", "曲の音高・音価・休符を1つの楽譜データとして設計", TEAL),
        ("2. パート設定", "開始拍・オクターブ・振幅だけをパートごとに分離", SKY),
        ("3. 音色データ", "金管4種とドラム4種のJSONを配置・確認", VIOLET),
        ("4. 確認", "Processing確認用スケッチで輪唱と伴奏を再生", AMBER),
    ]
    for i, (title, body, accent) in enumerate(cards):
        x = x0 + i * (w + gap)
        card(c, x, y, w, h, title, body, accent=accent, body_size=14)
        if i < len(cards) - 1:
            c.setStrokeColor(MUTED)
            c.setLineWidth(2)
            c.line(x + w + 5, y + h / 2, x + w + gap - 5, y + h / 2)
            c.setFillColor(MUTED)
            c.circle(x + w + gap - 7, y + h / 2, 3, fill=1, stroke=0)
    c.setFillColor(MUTED)
    c.setFont(FONT, 15)
    c.drawString(52, 166, "狙い：個別の楽譜を増やさず、設定差で輪唱・音域・バランスを作る")
    c.showPage()


def canon_slide(c):
    section(c, 3, "SCORE DESIGN", "1つの主旋律を、4つの金管パートで輪唱させる", "week9 確認用スケッチ：MELODY_SCORE を全パートで共用")
    c.setFillColor(MUTED)
    c.setFont(FONT, 15)
    c.drawString(52, 398, "同じ楽譜に「開始拍」「オクターブ」「振幅」を与えることで、4声の入りを作る")
    tracks = [
        ("トランペット", "C5", "0拍", "0.20", TEAL, 0),
        ("ホルン", "C4", "8拍", "0.17", SKY, 8),
        ("トロンボーン", "C3", "16拍", "0.18", VIOLET, 16),
        ("チューバ", "C2", "24拍", "0.15", CORAL, 24),
    ]
    start_x, row_y, row_h, beat_w = 260, 344, 54, 14
    for beat in range(0, 33, 4):
        x = start_x + beat * beat_w
        c.setStrokeColor(SLATE_LIGHT)
        c.setLineWidth(0.7)
        c.line(x, 118, x, 386)
        c.setFillColor(MUTED)
        c.setFont(FONT, 10)
        c.drawCentredString(x, 96, str(beat))
    c.setFillColor(MUTED)
    c.setFont(FONT, 11)
    c.drawString(start_x, 76, "拍数")
    for index, (name, register, start, amp, color, offset) in enumerate(tracks):
        y = row_y - index * row_h
        c.setFillColor(WHITE)
        c.setFont(FONT_BOLD, 16)
        c.drawString(52, y + 12, name)
        c.setFillColor(MUTED)
        c.setFont(FONT, 12)
        c.drawString(160, y + 12, f"{register} / 振幅 {amp}")
        rounded(c, start_x + offset * beat_w, y, (32 - offset) * beat_w, 28, color, radius=8)
        c.setFillColor(NAVY)
        c.setFont(FONT_BOLD, 11)
        c.drawString(start_x + offset * beat_w + 10, y + 9, f"開始 {start}")
    rounded(c, 52, 45, 170, 66, NAVY_2)
    c.setFillColor(AMBER)
    c.setFont(FONT_BOLD, 15)
    c.drawString(68, 82, "設計のポイント")
    c.setFillColor(MUTED)
    c.setFont(FONT, 13)
    c.drawString(68, 60, "譜面を重複管理しない")
    c.showPage()


def drum_slide(c):
    section(c, 4, "SOUND DATA", "ドラムは控えめに支え、音色データは単体で完結させる", "8つのJSONを week9/data に同梱し、確認スケッチだけで再生可能に")
    card(c, 52, 214, 256, 190, "伴奏の調整", "・ドラム全体の振幅を 0.075 に抑制\n・裏拍にハイハットを追加\n・声部が入る拍にクラッシュ\n・終止前4拍に短いフィル", accent=AMBER, body_size=15)
    card(c, 332, 214, 256, 190, "音色の構成", "金管：トランペット / ホルン / トロンボーン / チューバ\n\nドラム：キック / スネア / ハイハット / クラッシュ", accent=VIOLET, body_size=15)
    card(c, 612, 214, 306, 190, "再生の分岐", "drum_sample があるJSONは、解析済みの原音1打を優先再生。\n\nサンプル未設定の場合は、倍音・ノイズ・ADSRによる合成へ自動で戻す。", accent=TEAL, body_size=15)
    c.setFillColor(MUTED)
    c.setFont(FONT, 14)
    c.drawString(52, 154, "ねらい：主旋律を隠さず、輪唱の入りと終止を聞き取りやすくする")
    c.showPage()


def implementation_slide(c):
    section(c, 5, "IMPLEMENTATION", "作業の流れ：楽譜案から、4声の確認用スケッチへ", "週ごとの成果を積み上げ、曲の構造と音の聞こえ方を具体化")
    steps = [
        ("week5", "楽譜案", "ScoreEvent形式と\nかえるのうたの試作", TEAL),
        ("week6", "音色整理", "金管・ドラムの\nJSONと試聴素材", SKY),
        ("week7", "ドラム改善", "再解析データと\n伴奏の調整", VIOLET),
        ("week9", "4声輪唱", "共通譜 + 開始拍 +\n音域設定を統合", CORAL),
        ("現在", "発表準備", "成果・検証結果を\n共有できる形へ", AMBER),
    ]
    y, x0, w, gap = 250, 56, 160, 25
    c.setStrokeColor(SLATE_LIGHT)
    c.setLineWidth(3)
    c.line(x0 + 70, y + 70, x0 + 4 * (w + gap) + 90, y + 70)
    for i, (week, title, body, accent) in enumerate(steps):
        x = x0 + i * (w + gap)
        c.setFillColor(accent)
        c.circle(x + 72, y + 70, 18, fill=1, stroke=0)
        rounded(c, x, y - 95, w, 128, NAVY_2)
        c.setFillColor(accent)
        c.setFont(FONT_BOLD, 14)
        c.drawCentredString(x + w / 2, y + 4, week)
        c.setFillColor(WHITE)
        c.setFont(FONT_BOLD, 17)
        c.drawCentredString(x + w / 2, y - 28, title)
        c.setFillColor(MUTED)
        c.setFont(FONT, 13)
        lines = body.split("\n")
        for j, line in enumerate(lines):
            c.drawCentredString(x + w / 2, y - 56 - j * 19, line)
    c.setFillColor(MUTED)
    c.setFont(FONT, 15)
    c.drawString(56, 110, "確認用スケッチは、楽曲・パート設定・音色データを同じフォルダに置き、再現しやすくした。")
    c.showPage()


def result_slide(c):
    section(c, 6, "RESULT", "成果と、発表で伝えたいこと", "実装済みのことと、実機で確認すべきことを分けて説明する")
    card(c, 52, 236, 270, 168, "できたこと", "共通譜を軸に、4つの金管パートを開始拍・音域・振幅の差だけで構成した。", accent=TEAL, body_size=16)
    card(c, 344, 236, 270, 168, "確認したこと", "Processingのビルドと起動時例外なしを確認。4声の開始拍、56拍のドラム、JSON 8件も照合した。", accent=SKY, body_size=16)
    card(c, 636, 236, 270, 168, "次に確認すること", "Arduinoを含む実機で、金管4声とドラムの音量バランスを聴感で最終調整する。", accent=AMBER, body_size=16)
    rounded(c, 52, 128, 854, 60, NAVY_2)
    c.setFillColor(WHITE)
    c.setFont(FONT_BOLD, 20)
    c.drawCentredString(PAGE_W / 2, 151, "同じ譜面を使い、設定差で「輪唱らしさ」と「聴きやすさ」を両立させた")
    c.setFillColor(MUTED)
    c.setFont(FONT, 11)
    c.drawString(52, 76, "根拠：docs/roles.md、work/saito/week5 - week9、work/saito/week9/作業ログ/、kaeru_score_debug/")
    c.showPage()


def build_pdf():
    register_fonts()
    c = canvas.Canvas(str(OUT_PDF), pagesize=(PAGE_W, PAGE_H), pageCompression=1)
    c.setTitle("齋藤翔太 発表用個人担当まとめ")
    c.setAuthor("齋藤翔太 / Team 23")
    c.setSubject("楽譜データと4声輪唱の設計")
    title_slide(c)
    scope_slide(c)
    canon_slide(c)
    drum_slide(c)
    implementation_slide(c)
    result_slide(c)
    c.save()
    print(OUT_PDF)


if __name__ == "__main__":
    build_pdf()
