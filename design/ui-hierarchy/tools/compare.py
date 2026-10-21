"""Build comparison sheets for the Today-page hierarchy comps (Pillow only)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

here = Path(__file__).resolve().parent
screens = here.parent / "screens"

FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
FONT_SMALL = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
FONT_TITLE = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)

base = Image.open(screens / "today-base-light.png")
a = Image.open(screens / "today-a-depth-light.png")
b = Image.open(screens / "today-b-balanced-light.png")
c = Image.open(screens / "today-c-brand-light.png")

# ---- 1. 4-up grid -----------------------------------------------------------
scale = 0.5
w, h = int(1366 * scale), int(780 * scale)
pad, label_h = 16, 30
grid = Image.new("RGB", (pad * 3 + w * 2, pad * 3 + (h + label_h) * 2), "#E9EDF2")
draw = ImageDraw.Draw(grid)
for index, (img, label) in enumerate([
    (base, "现状复刻（Mist Ink 1.0）"),
    (a, "方案 A · 纵深优先"),
    (b, "方案 B · 均衡（推荐）"),
    (c, "方案 C · 品牌优先"),
]):
    col, row = index % 2, index // 2
    x = pad + col * (w + pad)
    y = pad + row * (h + label_h + pad)
    draw.text((x + 2, y), label, font=FONT, fill="#1C2530")
    grid.paste(img.resize((w, h), Image.LANCZOS), (x, y + label_h))
grid.save(screens / "compare-grid.png")

# ---- 2. component detail comparison (base vs B), crops at 2x ----------------
regions = [
    ("分区标题 + 计数", (266, 14, 560, 56)),
    ("标签筛选行", (250, 198, 900, 258)),
    ("事项行右侧：进度 / 标签 / 图标", (1100, 262, 1340, 430)),
    ("侧栏导航 + 品牌区", (0, 8, 240, 232)),
]
zoom = 2
col_gap, row_gap, head_h, label_h2 = 24, 18, 34, 26
crops = []
maxw = 0
for label, box in regions:
    left = base.crop(box)
    right = b.crop(box)
    lw, lh = int(left.width * zoom), int(left.height * zoom)
    rw, rh = int(right.width * zoom), int(right.height * zoom)
    crops.append((label, left.resize((lw, lh), Image.LANCZOS), right.resize((rw, rh), Image.LANCZOS)))
    maxw = max(maxw, lw, rw)

sheet_w = 150 + maxw * 2 + col_gap + 40
sheet_h = 40 + head_h + sum(max(l.height, r.height) + label_h2 + row_gap for _, l, r in crops) + 20
sheet = Image.new("RGB", (sheet_w, sheet_h), "#F4F6F9")
d = ImageDraw.Draw(sheet)
d.text((20, 14), "组件细节对比（2×）", font=FONT_TITLE, fill="#1C2530")
col1 = 150
col2 = col1 + maxw + col_gap
d.text((col1, 44), "现状", font=FONT, fill="#5A6675")
d.text((col2, 44), "方案 B · 均衡", font=FONT, fill="#244A70")
y = 44 + head_h
for label, left, right in crops:
    d.text((20, y + 4), label, font=FONT_SMALL, fill="#5A6675")
    yy = y + label_h2
    sheet.paste(left, (col1, yy))
    sheet.paste(right, (col2, yy))
    y = yy + max(left.height, right.height) + row_gap
sheet.save(screens / "compare-details.png")

print("saved compare-grid.png, compare-details.png")
