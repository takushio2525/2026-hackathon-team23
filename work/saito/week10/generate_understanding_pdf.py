"""内容理解ノートPDFを生成する。"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Flowable,
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


OUTPUT = Path(__file__).with_name("内容理解ノート_25G1053.pdf")
FONT_CANDIDATES = (
    Path("/usr/local/texlive/2025/texmf-dist/fonts/truetype/public/ipaex/ipag.ttf"),
    Path("/System/Library/Fonts/Supplemental/AppleGothic.ttf"),
)
PAGE_WIDTH, PAGE_HEIGHT = A4
MARGIN_X = 19 * mm
CONTENT_WIDTH = PAGE_WIDTH - MARGIN_X * 2


def register_japanese_font() -> str:
    for path in FONT_CANDIDATES:
        if path.exists():
            pdfmetrics.registerFont(TTFont("Japanese", str(path)))
            return "Japanese"
    raise RuntimeError("日本語フォントが見つかりません。IPAex GothicまたはAppleGothicを用意してください。")


FONT = register_japanese_font()


class LineBox(Flowable):
    """文章の流れを目立たせない枠で示す。"""

    def __init__(self, text: str, width: float):
        super().__init__()
        self.text = text
        self.width = width
        self.height = 18 * mm

    def draw(self):
        self.canv.setStrokeColor(colors.HexColor("#7E8B96"))
        self.canv.setFillColor(colors.HexColor("#F6F8FA"))
        self.canv.roundRect(0, 0, self.width, self.height, 2 * mm, fill=1, stroke=1)
        self.canv.setFillColor(colors.HexColor("#24313B"))
        self.canv.setFont(FONT, 10.5)
        self.canv.drawCentredString(self.width / 2, 7 * mm, self.text)


def page_number(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#CCD3D9"))
    canvas.line(MARGIN_X, 13 * mm, PAGE_WIDTH - MARGIN_X, 13 * mm)
    canvas.setFillColor(colors.HexColor("#56616A"))
    canvas.setFont(FONT, 8.5)
    canvas.drawString(MARGIN_X, 7.5 * mm, "内容理解ノート | 齋藤 翔太")
    canvas.drawRightString(PAGE_WIDTH - MARGIN_X, 7.5 * mm, f"{doc.page}")
    canvas.restoreState()


def paragraph(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(text, style)


def make_table(rows, widths, header=True, font_size=8.8):
    converted = []
    for row_index, row in enumerate(rows):
        converted.append(
            [paragraph(str(cell), STYLES["table_header"] if header and row_index == 0 else STYLES["table" ]) for cell in row]
        )
    table = Table(converted, colWidths=widths, repeatRows=1 if header else 0, hAlign="LEFT")
    style = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#C7CFD5")),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EAF0F4")),
    ]
    if not header:
        style = style[1:]
    table.setStyle(TableStyle(style))
    return table


base = getSampleStyleSheet()
STYLES = {
    "title": ParagraphStyle(
        "title", parent=base["Normal"], fontName=FONT, fontSize=21, leading=27,
        textColor=colors.HexColor("#1C2E3A"), alignment=TA_LEFT, spaceAfter=3,
    ),
    "subtitle": ParagraphStyle(
        "subtitle", parent=base["Normal"], fontName=FONT, fontSize=12, leading=17,
        textColor=colors.HexColor("#4B5B65"), spaceAfter=10,
    ),
    "h1": ParagraphStyle(
        "h1", parent=base["Heading1"], fontName=FONT, fontSize=14, leading=20,
        textColor=colors.HexColor("#1C2E3A"), spaceBefore=10, spaceAfter=5,
        borderWidth=0, borderPadding=0,
    ),
    "h2": ParagraphStyle(
        "h2", parent=base["Heading2"], fontName=FONT, fontSize=11.5, leading=17,
        textColor=colors.HexColor("#27485B"), spaceBefore=7, spaceAfter=3,
    ),
    "body": ParagraphStyle(
        "body", parent=base["BodyText"], fontName=FONT, fontSize=9.6, leading=15,
        textColor=colors.HexColor("#202A30"), wordWrap="CJK", spaceAfter=5,
    ),
    "bullet": ParagraphStyle(
        "bullet", parent=base["BodyText"], fontName=FONT, fontSize=9.5, leading=14,
        leftIndent=13, firstLineIndent=-10, bulletIndent=1, textColor=colors.HexColor("#202A30"),
        wordWrap="CJK", spaceAfter=2,
    ),
    "note": ParagraphStyle(
        "note", parent=base["BodyText"], fontName=FONT, fontSize=8.8, leading=13,
        textColor=colors.HexColor("#43525D"), wordWrap="CJK", spaceAfter=4,
    ),
    "table": ParagraphStyle(
        "table", parent=base["BodyText"], fontName=FONT, fontSize=8.4, leading=11.5,
        textColor=colors.HexColor("#202A30"), wordWrap="CJK",
    ),
    "table_header": ParagraphStyle(
        "table_header", parent=base["BodyText"], fontName=FONT, fontSize=8.4, leading=11.5,
        textColor=colors.HexColor("#1C2E3A"), wordWrap="CJK", alignment=TA_CENTER,
    ),
}


def build_story():
    story = []
    story += [
        paragraph("内容理解ノート", STYLES["title"]),
        paragraph("楽譜データ・4声輪唱・ドラム伴奏・音色再現", STYLES["subtitle"]),
        paragraph("作成者：齋藤 翔太　　作成日：2026年6月24日　　更新日：2026年7月7日", STYLES["note"]),
        Spacer(1, 3 * mm),
        paragraph("1. この資料の目的", STYLES["h1"]),
        paragraph(
            "これは発表用のスライドではなく、担当したプログラムがどのように音を鳴らしているかを事前に理解するための資料です。"
            "当初はweek9の「かえるのうた」4声輪唱確認用Processingスケッチを対象に作成しました。"
            "現在は、week10で作成した修正版スケッチと、week11で整理したフルート・オルガン追加後の構成も反映しています。",
            STYLES["body"],
        ),
        paragraph("理解する順番", STYLES["h2"]),
        paragraph("• 楽譜をどの形式で保持しているか", STYLES["bullet"]),
        paragraph("• 同じ楽譜を4つの金管パートでどう使い分けているか", STYLES["bullet"]),
        paragraph("• ドラムがどの拍で、どのように鳴るか", STYLES["bullet"]),
        paragraph("• 旋律楽器とドラムの音色を、どのパラメータから再現しているか", STYLES["bullet"]),
        paragraph("• week9版からweek10調整版へ、どこが変わったか", STYLES["bullet"]),
        Spacer(1, 2 * mm),
        paragraph("2. 全体の流れ", STYLES["h1"]),
        paragraph(
            "スケッチは、楽譜データを読み、各イベントを再生時刻に並べ、最後に音色定義を使って音を作ります。"
            "旋律4声とドラムでは、同じ再生スケジュールの仕組みを使いますが、音程の扱いと音色の選び方が異なります。",
            STYLES["body"],
        ),
        LineBox("楽譜データ　→　パートごとの開始拍・音域設定　→　再生予約　→　音色JSONを使った発音", CONTENT_WIDTH),
        Spacer(1, 3 * mm),
        make_table([
            ["データ", "役割"],
            ["ScoreEvent", "いつ、どの音を、どのくらいの強さ・長さで鳴らすかを表す。"],
            ["PartDefinition", "楽器名、音色JSON、開始拍、オクターブ移調量、基本音量を表す。"],
        ], [36 * mm, CONTENT_WIDTH - 36 * mm]),
        Spacer(1, 3 * mm),
        paragraph("3. 楽譜データの読み方", STYLES["h1"]),
        paragraph(
            "durationQ8は拍を256分割した値です。256なら1拍、128なら0.5拍です。subNote以降は、"
            "同じ拍の途中に追加で鳴らす音を表し、ドラムの裏拍ハイハットなどに使います。",
            STYLES["body"],
        ),
        make_table([
            ["項目", "意味"],
            ["beatAt", "曲の先頭から数えた開始拍"],
            ["noteNumber", "MIDIノート番号。休符は0"],
            ["velocity", "音の強さ。0から127の範囲"],
            ["durationQ8", "音の長さ。256で1拍"],
            ["subNote / subOffsetQ8", "1つ目の音に重ねる音と、その開始位置"],
        ], [45 * mm, CONTENT_WIDTH - 45 * mm]),
        paragraph(
            "主旋律はMELODY_SCOREに1回だけ記述します。4パートで別々の譜面を持たないため、"
            "旋律を直すときはこの共通譜を修正すれば十分です。",
            STYLES["note"],
        ),
        PageBreak(),
        paragraph("4. week9版の4声輪唱の仕組み", STYLES["h1"]),
        paragraph(
            "トランペットから順に8拍ずつ遅らせて入ります。チューバは低音伴奏ではなく、"
            "24拍遅れて入る4声目の主旋律として扱っています。",
            STYLES["body"],
        ),
        make_table([
            ["パート", "開始拍", "移調量", "基本音量", "主な音域"],
            ["トランペット", "0", "+12半音", "0.20", "C5からA5"],
            ["ホルン", "8", "0半音", "0.17", "C4からA4"],
            ["トロンボーン", "16", "-12半音", "0.18", "C3からA3"],
            ["チューバ", "24", "-24半音", "0.15", "C2からA2"],
        ], [35 * mm, 18 * mm, 28 * mm, 25 * mm, CONTENT_WIDTH - 106 * mm]),
        Spacer(1, 3 * mm),
        paragraph("再生時には、各イベントの開始時刻にパートの開始拍を足します。金管の音程は、"
                  "「共通譜のnoteNumber + octaveShift」で決まります。これを周波数に変換して、"
                  "金管の合成音を作るため、同じ旋律を高音から低音まで自然に配置できます。", STYLES["body"]),
        paragraph("5. 最新版の4声構成", STYLES["h1"]),
        paragraph(
            "week10の修正版では、発表前確認で聞き分けやすいように4声の担当楽器を変更しました。"
            "ホルンとチューバを外し、フルート、トランペット、トロンボーン、オルガンの構成にしています。",
            STYLES["body"],
        ),
        make_table([
            ["パート", "開始拍", "移調量", "基本音量", "主な音域"],
            ["フルート", "0", "+12半音", "0.28", "C5からA5"],
            ["トランペット", "8", "+12半音", "0.22", "C5からA5"],
            ["トロンボーン", "16", "-12半音", "0.22", "C3からA3"],
            ["オルガン", "24", "-12半音", "0.25", "C3からA3"],
        ], [35 * mm, 18 * mm, 28 * mm, 25 * mm, CONTENT_WIDTH - 106 * mm]),
        Spacer(1, 3 * mm),
        paragraph(
            "フルートは倍音合成だけでは質感が弱くなりやすいため、音色JSON内のtone_sampleを使う原音サンプル主導の再生に変更しました。"
            "フルート用の補正値はFLUTE_SAMPLE_GAIN = 1.32です。全体音量はMASTER_GAIN = 1.35、"
            "ドラム音量はDRUM_AMPLITUDE = 0.095に調整しています。",
            STYLES["body"],
        ),
        paragraph(
            "この最新版でも、共通譜MELODY_SCOREを4パートで使い回す考え方は変えていません。"
            "変わったのは、PartDefinitionで指定する音色JSON、音域、音量です。",
            STYLES["note"],
        ),
        paragraph("6. ドラム伴奏の仕組み", STYLES["h1"]),
        paragraph(
            "ドラム譜はcreateDrumScore()で生成し、曲の最後まで支えられるように56拍分を用意しています。"
            "最新版では4分の4拍子として、1・3拍目をキック、2・4拍目をスネアに整理しています。",
            STYLES["body"],
        ),
        make_table([
            ["拍", "主音", "追加音"],
            ["1拍目", "キック。小節の頭を示す。", "裏拍にハイハット"],
            ["2拍目", "スネア。拍の区切りを示す。", "裏拍にハイハット"],
            ["3拍目", "キック。低音の支えを作る。", "裏拍にハイハット"],
            ["4拍目", "スネア。次の小節へつなぐ。", "裏拍にハイハット"],
        ], [18 * mm, 72 * mm, CONTENT_WIDTH - 90 * mm]),
        Spacer(1, 2 * mm),
        KeepTogether(
            [
                paragraph("特別な処理", STYLES["h2"]),
                paragraph("• 0、8、16、24拍目：新しい声部が入る位置で、控えめなクラッシュとキックを同時に鳴らす。", STYLES["bullet"]),
                paragraph("• 最後の拍：クラッシュとキックで終止感を出す。", STYLES["bullet"]),
                paragraph(
                    "最新版のドラム基本音量はDRUM_AMPLITUDE = 0.095です。各音では、さらにvelocity / 127を掛けます。"
                    "旋律より目立ちすぎず、拍を感じられる音量にする意図です。",
                    STYLES["note"],
                ),
            ]
        ),
        paragraph("7. 音を再現するパラメータ", STYLES["h1"]),
        paragraph(
            "金管もドラムも、音色JSONにある倍音、ノイズ、ADSRエンベロープを読み取ります。"
            "最新版では、フルートのtone_sampleも読み取ります。ADSRは、音の立ち上がりから消えるまでの形を表します。",
            STYLES["body"],
        ),
        make_table([
            ["パラメータ", "音への影響"],
            ["fundamental_hz", "基準となる周波数。ドラムでは音の中心的な高さを決める。"],
            ["harmonics", "倍音の周波数比と振幅。音の明るさや厚みを決める。"],
            ["noise.level", "ノイズ成分の量。スネアやシンバルのざらつきに関係する。"],
            ["attack_sec", "音が立ち上がるまでの時間。"],
            ["decay_sec / sustain_level", "立ち上がった後の減衰と、保持される音量。"],
            ["release_sec", "音を止めた後に消えるまでの時間。"],
            ["tone_sample", "フルートなどの原音本体サンプル。倍音合成より自然な質感を優先したい場合に使う。"],
            ["drum_sample", "解析済みの1打分の波形。ある場合は、合成音より優先して再生する。"],
        ], [50 * mm, CONTENT_WIDTH - 50 * mm]),
        Spacer(1, 3 * mm),
        paragraph("week9で使用しているドラム音色の主な設定値", STYLES["h2"]),
        make_table([
            ["音色", "基準Hz", "倍音数", "Attack", "Decay", "Release", "Noise"],
            ["キック", "39.029", "40", "0.008", "0.190", "0.560", "0.0139"],
            ["スネア", "180.341", "40", "0.005", "0.320", "0.260", "0.0252"],
            ["ハイハット", "263.782", "36", "0.005", "0.900", "0.500", "0"],
            ["クラッシュ", "429.318", "32", "0.012", "0.900", "1.500", "0.0479"],
        ], [25 * mm, 22 * mm, 19 * mm, 22 * mm, 22 * mm, 25 * mm, CONTENT_WIDTH - 135 * mm]),
        paragraph(
            "上の値は「どの楽器らしく聞こえるか」を決める値です。譜面のvelocityは、"
            "演奏中の音の強さを決める値であり、役割が異なります。",
            STYLES["note"],
        ),
        paragraph("8. ドラムは旋律楽器と同じ方法か", STYLES["h1"]),
        paragraph(
            "土台となる処理は共通です。どちらも再生時刻を予約し、音色JSONを読み、音量と音の長さを反映して発音します。"
            "ただし、ドラムには専用の扱いがあります。",
            STYLES["body"],
        ),
        make_table([
            ["観点", "旋律楽器", "ドラム"],
            ["音程", "共通譜のノートをパートごとにオクターブ移調する。", "キック等のノート番号から、対応する音色JSONを選ぶ。"],
            ["音色", "倍音を重ね、ADSRで形を作る。フルートはtone_sampleを優先する。", "drum_sampleがあれば優先再生し、なければ倍音・ノイズ・ADSRで合成する。"],
            ["停止処理", "譜面上の長さでノートオフする。", "原音波形を使う場合は、自然な減衰を残すため途中で止めない。"],
        ], [26 * mm, (CONTENT_WIDTH - 26 * mm) / 2, (CONTENT_WIDTH - 26 * mm) / 2]),
        PageBreak(),
        paragraph("9. week9版から最新版への変更点", STYLES["h1"]),
        make_table([
            ["観点", "week9版", "最新版"],
            ["旋律4声", "トランペット、ホルン、トロンボーン、チューバ", "フルート、トランペット、トロンボーン、オルガン"],
            ["フルート", "未使用", "tone_sampleを使い、FLUTE_SAMPLE_GAIN = 1.32で再生"],
            ["全体音量", "控えめな確認用", "MASTER_GAIN = 1.35で発表前確認向けに調整"],
            ["ドラム音量", "DRUM_AMPLITUDE = 0.075", "DRUM_AMPLITUDE = 0.095"],
            ["ドラムパターン", "4拍パターンと終止前フィルを含む", "4分の4拍子として整理し、最後の拍をクラッシュ + キックで強調"],
            ["音色ファイル", "金管4種類とドラム4種類", "フルート、トランペット、トロンボーン、オルガン、ドラム4種類"],
        ], [30 * mm, (CONTENT_WIDTH - 30 * mm) / 2, (CONTENT_WIDTH - 30 * mm) / 2]),
        Spacer(1, 3 * mm),
        paragraph(
            "最新版は、Arduino実機用の最終ファームウェアそのものではなく、発表前に旋律・音色・バランスを確認するためのProcessingスケッチです。"
            "そのため、音色JSONをスケッチ内のdataフォルダに同梱し、外部フォルダ参照なしで再生できるようにしています。",
            STYLES["note"],
        ),
        paragraph("10. 確認済みのことと、事前に見ておくこと", STYLES["h1"]),
        paragraph("確認済み", STYLES["h2"]),
        paragraph("• 最新版の4声の開始拍が0、8、16、24拍であること。", STYLES["bullet"]),
        paragraph("• フルート、トランペット、トロンボーン、オルガンの4声構成になっていること。", STYLES["bullet"]),
        paragraph("• フルート音色JSONにtone_sampleがあり、スケッチ側でToneSampleUGenを使うこと。", STYLES["bullet"]),
        paragraph("• ドラム譜が56拍あり、声部の入りと最後の拍にクラッシュを含むこと。", STYLES["bullet"]),
        paragraph("• 旋律4種類とドラム4種類、合計8個の音色JSONを読み込むこと。", STYLES["bullet"]),
        paragraph("• Processingスケッチが起動時に例外を出さないこと。", STYLES["bullet"]),
        paragraph("本番前に確認すること", STYLES["h2"]),
        paragraph("• 実際に全パートを鳴らし、フルートとオルガンが他の旋律に埋もれていないかを聴く。", STYLES["bullet"]),
        paragraph("• クラッシュ、ハイハット、最後の拍の強調が主旋律を邪魔していないかを聴く。", STYLES["bullet"]),
        paragraph("• 必要ならMASTER_GAIN、PartDefinitionのamplitude、FLUTE_SAMPLE_GAIN、DRUM_AMPLITUDEを調整する。", STYLES["bullet"]),
        Spacer(1, 3 * mm),
        paragraph("11. ソースの対応箇所", STYLES["h1"]),
        paragraph("実装を読み返すときは、次の順番が分かりやすいです。", STYLES["body"]),
        make_table([
            ["順番", "確認する箇所", "何が分かるか"],
            ["1", "MELODY_PARTS と MELODY_SCORE", "共通譜と、各旋律パートの時間差・音域"],
            ["2", "createDrumScore() と schedulePart()", "ドラム譜の作り方と再生時刻の決め方"],
            ["3", "TimbreData、ToneSampleUGen、BrassNote、DrumNote、RecordedDrumNote", "音色JSONと原音サンプルをどう使って音を作るか"],
            ["4", "data/ の *.tweaked.instrument.json", "各楽器の具体的な音色パラメータ"],
        ], [14 * mm, 73 * mm, CONTENT_WIDTH - 87 * mm]),
    ]
    return story


def main():
    document = SimpleDocTemplate(
        str(OUTPUT), pagesize=A4, leftMargin=MARGIN_X, rightMargin=MARGIN_X,
        topMargin=18 * mm, bottomMargin=20 * mm, title="内容理解ノート",
        author="齋藤 翔太",
    )
    document.build(build_story(), onFirstPage=page_number, onLaterPages=page_number)
    print(f"generated: {OUTPUT}")


if __name__ == "__main__":
    main()
