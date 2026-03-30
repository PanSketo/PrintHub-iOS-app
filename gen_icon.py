"""
Generate elegant PrintHub app icons using Pillow.
Design: minimal 3D printer on a deep gradient background.
"""
from PIL import Image, ImageDraw, ImageFilter
import os

# ─── helpers ──────────────────────────────────────────────────────────────────

def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def lerp_color(c1, c2, t):
    r1, g1, b1 = hex2rgb(c1)
    r2, g2, b2 = hex2rgb(c2)
    return (int(r1 + (r2 - r1) * t),
            int(g1 + (g2 - g1) * t),
            int(b1 + (b2 - b1) * t))

# ─── icon renderer at 1024×1024 ───────────────────────────────────────────────

def make_base_icon():
    SIZE = 1024
    img = Image.new('RGB', (SIZE, SIZE))
    draw = ImageDraw.Draw(img)

    # -- gradient background: deep navy to dark teal-slate
    for y in range(SIZE):
        t = y / (SIZE - 1)
        c = lerp_color('#0B1420', '#112035', t)
        draw.line([(0, y), (SIZE - 1, y)], fill=c)

    def p(v):
        return int(round(v))

    # color palette
    FRAME  = (194, 210, 224)   # cool blue-white
    SHADE  = (155, 172, 188)   # slightly darker frame edge
    ACCENT = (249, 115,  22)   # orange-500
    WARM   = (253, 186, 116)   # light orange highlight
    BED    = (110, 130, 150)   # cool mid-gray
    SHADOW = ( 10,  18,  30)   # near-black for depth lines

    # ── glow layer (blurred soft orange under nozzle) ────────────────────────
    glow_img = Image.new('RGB', (SIZE, SIZE), (0, 0, 0))
    gd = ImageDraw.Draw(glow_img)
    # paint a big soft blob where the nozzle will be
    gd.ellipse([p(412), p(430), p(612), p(590)], fill=(200, 80, 0))
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=80))
    # blend glow into main image at low opacity
    img = Image.blend(img, glow_img, alpha=0.25)
    draw = ImageDraw.Draw(img)

    # ── left pillar ───────────────────────────────────────────────────────────
    draw.rectangle([p(218), p(178), p(278), p(796)], fill=FRAME)
    draw.rectangle([p(248), p(186), p(278), p(788)], fill=SHADE)   # right-edge shadow

    # ── right pillar ──────────────────────────────────────────────────────────
    draw.rectangle([p(746), p(178), p(806), p(796)], fill=FRAME)
    draw.rectangle([p(746), p(186), p(776), p(788)], fill=SHADE)

    # ── top crossbeam ─────────────────────────────────────────────────────────
    draw.rectangle([p(218), p(178), p(806), p(240)], fill=FRAME)
    draw.rectangle([p(218), p(214), p(806), p(240)], fill=SHADE)   # bottom edge shadow

    # ── base platform (slightly wider than pillars) ───────────────────────────
    draw.rectangle([p(188), p(796), p(836), p(856)], fill=FRAME)
    # feet
    draw.rectangle([p(188), p(848), p(264), p(880)], fill=SHADE)
    draw.rectangle([p(760), p(848), p(836), p(880)], fill=SHADE)

    # ── X-axis rail ───────────────────────────────────────────────────────────
    draw.rectangle([p(278), p(404), p(746), p(426)], fill=BED)

    # ── print head body ───────────────────────────────────────────────────────
    draw.rectangle([p(455), p(374), p(569), p(462)], fill=ACCENT)
    # highlight on top face
    draw.rectangle([p(460), p(378), p(564), p(394)], fill=WARM)
    # side edge
    draw.rectangle([p(548), p(382), p(569), p(462)], fill=(210, 90, 10))

    # ── nozzle / heat-break ───────────────────────────────────────────────────
    # tapered block
    draw.polygon([
        (p(478), p(462)),
        (p(546), p(462)),
        (p(536), p(492)),
        (p(488), p(492)),
    ], fill=ACCENT)
    # hot-end tip triangle
    draw.polygon([
        (p(488), p(492)),
        (p(536), p(492)),
        (p(512), p(514)),
    ], fill=(220, 90, 10))

    # ── nozzle glow dot ───────────────────────────────────────────────────────
    nr = p(13)
    ncx, ncy = p(512), p(524)
    draw.ellipse([ncx - nr, ncy - nr, ncx + nr, ncy + nr], fill=(254, 240, 138))  # bright yellow

    # ── print bed ─────────────────────────────────────────────────────────────
    draw.rectangle([p(278), p(702), p(746), p(744)], fill=BED)
    # bed surface highlight
    draw.rectangle([p(278), p(702), p(746), p(712)], fill=(140, 160, 180))

    # ── object being printed (three stacked layers) ───────────────────────────
    layers = [
        (p(420), p(652), p(604), p(702)),  # base — full width
        (p(442), p(610), p(582), p(652)),  # mid
        (p(462), p(576), p(562), p(610)),  # top
    ]
    layer_fill  = (251, 146, 60)   # orange-400
    layer_top   = (253, 186, 116)  # lighter top edge
    layer_side  = (220, 100, 20)   # darker side/bottom edge

    for i, (x1, y1, x2, y2) in enumerate(layers):
        draw.rectangle([x1, y1, x2, y2], fill=layer_fill)
        draw.rectangle([x1, y1, x2, y1 + p(5)], fill=layer_top)    # top highlight
        draw.rectangle([x1, y2 - p(4), x2, y2], fill=layer_side)   # bottom shadow

    # ── rail segments either side of print head ───────────────────────────────
    draw.rectangle([p(278), p(412), p(455), p(416)], fill=SHADOW)
    draw.rectangle([p(569), p(412), p(746), p(416)], fill=SHADOW)

    return img

# ─── output sizes ─────────────────────────────────────────────────────────────

SIZES = [
    ('Icon-1024.png',    1024),
    ('Icon-20@2x.png',    40),
    ('Icon-20@3x.png',    60),
    ('Icon-29@2x.png',    58),
    ('Icon-29@3x.png',    87),
    ('Icon-40@2x.png',    80),
    ('Icon-40@3x.png',   120),
    ('Icon-60@2x.png',   120),
    ('Icon-60@3x.png',   180),
    ('Icon-76@1x.png',    76),
    ('Icon-76@2x.png',   152),
    ('Icon-83.5@2x.png', 167),
    # also regenerate the old AppIcon-* names so nothing breaks
    ('AppIcon-1024.png', 1024),
    ('AppIcon-180.png',   180),
    ('AppIcon-167.png',   167),
    ('AppIcon-152.png',   152),
    ('AppIcon-120.png',   120),
    ('AppIcon-87.png',     87),
    ('AppIcon-80.png',     80),
    ('AppIcon-76.png',     76),
    ('AppIcon-60.png',     60),
    ('AppIcon-58.png',     58),
    ('AppIcon-40.png',     40),
    ('AppIcon-29.png',     29),
    ('AppIcon-20.png',     20),
]

OUT = 'iOS/FilamentInventory/Assets.xcassets/AppIcon.appiconset'
os.makedirs(OUT, exist_ok=True)

base = make_base_icon()
for name, sz in SIZES:
    icon = base.resize((sz, sz), Image.LANCZOS)
    icon.save(os.path.join(OUT, name), 'PNG')
    print(f'  ✓ {name:30s} {sz}×{sz}')

print('\nAll icons generated.')
