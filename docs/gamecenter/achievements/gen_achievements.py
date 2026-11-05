#!/usr/bin/env python3
"""Generate 8 Game Center achievement images — 1024x1024 PNG, RGB, flat dark style."""
from PIL import Image, ImageDraw
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))
SIZE = 1024

# ── palette ───────────────────────────────────────────────────────────────────
BG       = (26,  26,  46)   # #1a1a2e deep blue-black
WHITE    = (232, 232, 232)
ORANGE   = (255, 107,  53)  # #FF6B35
PURPLE   = (155,  89, 182)  # #9B59B6
GOLD     = (241, 196,  15)  # #F1C40F
CYAN     = (  0, 210, 255)  # #00D2FF
GREEN    = ( 46, 204, 113)  # #2ECC71
RED      = (231,  76,  60)  # #E74C3C
FIRE     = (243, 156,  18)  # #F39C12
BLUE     = ( 52, 152, 219)  # #3498DB
GREY     = (136, 136, 136)
DARK2    = ( 40,  40,  72)
DARK3    = ( 55,  55, 100)

def new() -> tuple[Image.Image, ImageDraw.Draw]:
    img = Image.new("RGB", (SIZE, SIZE), BG)
    return img, ImageDraw.Draw(img)

def save(img: Image.Image, name: str):
    path = os.path.join(OUT, name)
    img.save(path, "PNG", dpi=(144, 144))
    print(f"✓ {path}")

def circle(d: ImageDraw.Draw, cx, cy, r, fill, outline=None, ow=0):
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=fill,
              outline=outline, width=ow)

def rect(d: ImageDraw.Draw, x, y, w, h, fill, outline=None, ow=0, radius=0):
    if radius:
        d.rounded_rectangle([x, y, x+w, y+h], radius=radius,
                             fill=fill, outline=outline, width=ow)
    else:
        d.rectangle([x, y, x+w, y+h], fill=fill,
                    outline=outline, width=ow)

def poly(d: ImageDraw.Draw, pts, fill, outline=None, ow=0):
    d.polygon(pts, fill=fill, outline=outline, width=ow)

def glow(img: Image.Image, cx, cy, r_max, color, steps=8):
    """Add a soft radial glow by drawing concentric circles with decreasing alpha."""
    overlay = Image.new("RGBA", img.size, (0,0,0,0))
    od = ImageDraw.Draw(overlay)
    for i in range(steps, 0, -1):
        r = int(r_max * i / steps)
        alpha = int(60 * (steps - i + 1) / steps)
        od.ellipse([cx-r, cy-r, cx+r, cy+r],
                   fill=(*color, alpha))
    img.paste(Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB"))

def stars(d: ImageDraw.Draw, positions, color, size=6):
    for x, y in positions:
        for angle in range(0, 360, 72):
            a = math.radians(angle)
            x2 = x + size * math.cos(a)
            y2 = y + size * math.sin(a)
            d.line([x, y, x2, y2], fill=color, width=2)

# ══════════════════════════════════════════════════════════════════════════════
# 1. import_success — 骷髅学长 + 课表
# ══════════════════════════════════════════════════════════════════════════════
def make_import_success():
    img, d = new()
    cx, cy = 512, 480

    # --- papers (staggered) ---
    for i, (dx, dy, ang) in enumerate([(-60, 80, -12), (0, 90, 3), (60, 80, 15)]):
        paper_img = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
        pd = ImageDraw.Draw(paper_img)
        pw, ph = 160, 210
        x0, y0 = cx + dx - pw//2, cy + dy
        col = (255, 240, 220) if i == 1 else (220, 210, 195)
        pd.rounded_rectangle([x0, y0, x0+pw, y0+ph], radius=8, fill=col)
        for row in range(5):
            lx = x0 + 18
            pd.line([lx, y0+40+row*28, lx+pw-36, y0+40+row*28],
                    fill=(180,160,140), width=5)
        rotated = paper_img.rotate(-ang, center=(cx+dx, cy+dy+ph//2),
                                   resample=Image.BICUBIC)
        img = Image.alpha_composite(img.convert("RGBA"), rotated).convert("RGB")
    d = ImageDraw.Draw(img)

    # --- skull head ---
    glow(img, cx, cy-60, 200, ORANGE)
    circle(d, cx, cy-60, 150, WHITE)
    circle(d, cx, cy-60, 145, (230, 225, 215))

    # jaw
    poly(d, [(cx-90, cy+40), (cx+90, cy+40),
             (cx+75, cy+120), (cx-75, cy+120)], WHITE)

    # teeth
    for i in range(-2, 3):
        tx = cx + i * 30
        rect(d, tx-10, cy+50, 18, 55, BG, radius=4)

    # eyes
    for ex in [cx-50, cx+50]:
        circle(d, ex, cy-70, 38, BG)
        circle(d, ex, cy-70, 26, ORANGE)
        circle(d, ex, cy-70, 12, BG)

    # nose
    poly(d, [(cx, cy-10), (cx-18, cy+18), (cx+18, cy+18)], BG)

    # cheekbones
    for ex in [cx-85, cx+85]:
        circle(d, ex, cy-10, 22, (200, 195, 185))

    # crack on forehead
    pts = [(cx+10, cy-180), (cx+5, cy-140), (cx+20, cy-120),
           (cx+15, cy-100), (cx+30, cy-80)]
    d.line(pts, fill=BG, width=4)

    # --- mortarboard ---
    brim_w = 200
    rect(d, cx-brim_w//2, cy-220, brim_w, 20, DARK3, radius=4)
    poly(d, [(cx-brim_w//2, cy-220), (cx+brim_w//2, cy-220),
             (cx+100, cy-260), (cx-100, cy-260)], DARK3)
    rect(d, cx-30, cy-270, 60, 20, DARK3, radius=3)
    # tassel
    d.line([(cx+80, cy-255), (cx+100, cy-195)], fill=ORANGE, width=6)
    circle(d, cx+100, cy-185, 12, ORANGE)

    # small stars
    stars(d, [(150,150),(880,200),(800,820),(200,750),(900,600)], ORANGE)

    save(img, "import_success.png")


# ══════════════════════════════════════════════════════════════════════════════
# 2. notification_on — 全知之眼 + 提醒铃
# ══════════════════════════════════════════════════════════════════════════════
def make_notification_on():
    img, d = new()
    cx, cy = 512, 512

    # --- gold rays ---
    for angle in range(0, 360, 20):
        a = math.radians(angle)
        r1, r2 = 200, 370
        x1 = cx + r1 * math.cos(a)
        y1 = cy + r1 * math.sin(a)
        x2 = cx + r2 * math.cos(a)
        y2 = cy + r2 * math.sin(a)
        d.line([x1, y1, x2, y2], fill=(*GOLD, )[:3], width=2)

    # --- all-seeing eye ---
    glow(img, cx, cy-60, 230, GOLD)
    d = ImageDraw.Draw(img)

    # eye whites (almond shape via polygon)
    eye_pts = []
    for i in range(32):
        t = i / 32 * 2 * math.pi
        ex = cx + 220 * math.cos(t)
        ey = (cy - 60) + 90 * math.sin(t) * (1 - 0.3 * math.cos(t)**2)
        eye_pts.append((ex, ey))
    poly(d, eye_pts, (255, 248, 220))

    # iris
    circle(d, cx, cy-60, 90, PURPLE)
    circle(d, cx, cy-60, 65, (*GOLD,)[:3] + (255,))
    circle(d, cx, cy-60, 40, BG)

    # pupil glint
    circle(d, cx+15, cy-80, 12, WHITE)
    circle(d, cx+15, cy-80, 6, (200, 200, 255))

    # eyelashes
    for i in range(-4, 5):
        angle = math.radians(i * 10)
        lx = cx + 220 * math.cos(math.pi + angle)
        ly = (cy-60) + 25 * math.sin(math.pi + angle)
        lx2 = lx - 18 * math.cos(angle + 0.2)
        ly2 = ly - 25
        d.line([(lx, ly), (lx2, ly2)], fill=DARK3, width=5)

    # --- notification bell ---
    bx, by = cx, cy + 200
    # bell dome
    poly(d, [
        (bx, by - 130),
        (bx - 90, by - 60),
        (bx - 100, by),
        (bx + 100, by),
        (bx + 90, by - 60),
    ], ORANGE)
    rect(d, bx-100, by, 200, 22, ORANGE, radius=4)
    circle(d, bx, by+35, 28, ORANGE)
    circle(d, bx, by+35, 18, BG)
    # small line at top of bell
    rect(d, bx-8, by-148, 16, 30, DARK2, radius=4)

    # --- notification dot ---
    circle(d, bx+75, by-90, 30, RED)
    circle(d, bx+75, cy-90, 12, WHITE)

    save(img, "notification_on.png")


# ══════════════════════════════════════════════════════════════════════════════
# 3. widget_add_success — 主屏幕网格，Widget高兴 App哭泣
# ══════════════════════════════════════════════════════════════════════════════
def make_widget_add():
    img, d = new()

    # phone frame
    pw, ph = 400, 600
    px, py = 512 - pw//2, 512 - ph//2 - 20
    rect(d, px, py, pw, ph, DARK3, radius=55, outline=(80,80,120), ow=6)
    rect(d, px+8, py+8, pw-16, ph-16, DARK2, radius=48)
    # notch
    rect(d, 512-50, py+5, 100, 28, DARK3, radius=12)

    # --- app grid 3x3 ---
    gap = 18
    cell = 90
    gx0 = px + 35
    gy0 = py + 55
    configs = [
        # col, row, color, mood
        (0, 0, (80,80,150), "neutral"),
        (1, 0, (80,80,150), "neutral"),
        (2, 0, (80,80,150), "neutral"),
        (0, 1, (80,80,150), "cry"),    # sad app
        (1, 1, CYAN,        "shine"),  # widget star
        (2, 1, (80,80,150), "neutral"),
        (0, 2, (80,80,150), "neutral"),
        (1, 2, (80,80,150), "neutral"),
        (2, 2, (80,80,150), "neutral"),
    ]
    for col, row, color, mood in configs:
        cx_ = gx0 + col * (cell + gap)
        cy_ = gy0 + row * (cell + gap)
        rect(d, cx_, cy_, cell, cell, color, radius=18)

        if mood == "shine":
            glow(img, cx_ + cell//2, cy_ + cell//2, 80, CYAN)
            d = ImageDraw.Draw(img)
            rect(d, cx_, cy_, cell, cell, CYAN, radius=18,
                 outline=WHITE, ow=3)
            # star shape
            sc = cx_ + cell//2
            sr = cy_ + cell//2
            for sa in range(0, 360, 72):
                a = math.radians(sa)
                d.line([sc, sr,
                        sc + 28*math.cos(a), sr + 28*math.sin(a)],
                       fill=WHITE, width=4)
            circle(d, sc, sr, 14, WHITE)

        elif mood == "cry":
            fc = cx_ + cell//2
            fr = cy_ + cell//2
            # face
            circle(d, fc, fr, 28, (100, 100, 170))
            # sad mouth
            d.arc([fc-14, fr+5, fc+14, fr+23], 0, 180, fill=BG, width=4)
            # tears
            for tx in [fc-10, fc+10]:
                d.ellipse([tx-4, fr+14, tx+4, fr+30],
                          fill=(130, 180, 255))

    # widget label arrow
    wx = gx0 + 1*(cell+gap) + cell//2
    wy = gy0 + 1*(cell+gap) - 30
    d.line([(wx, wy), (wx, wy-15)], fill=CYAN, width=4)
    d.polygon([(wx, wy-22), (wx-8, wy-12), (wx+8, wy-12)],
              fill=CYAN)

    save(img, "widget_add_success.png")


# ══════════════════════════════════════════════════════════════════════════════
# 4. share_success — 长翅膀的课表飞向多个设备
# ══════════════════════════════════════════════════════════════════════════════
def make_share_success():
    img, d = new()
    cx, cy = 512, 430

    # --- receiver phones (left & right) ---
    for side in [-1, 1]:
        mx = cx + side * 310
        my = cy + 50
        rect(d, mx-35, my-65, 70, 130, DARK3, radius=14, outline=(80,80,120), ow=3)
        rect(d, mx-28, my-55, 56, 105, DARK2, radius=10)
        # check mark inside
        d.line([(mx-12, my+2), (mx-2, my+14), (mx+16, my-10)],
               fill=GREEN, width=6)

    # --- dashed arrows ---
    for side in [-1, 1]:
        for t in range(6):
            pct = t / 6
            ax = cx + side * (80 + 160 * pct)
            ay = cy + 30 * math.sin(math.pi * pct) * side * 0.3 + 10
            circle(d, ax, ay, 5, GREEN)

    # --- main document with wings ---
    dw, dh = 200, 260
    dx, dy = cx - dw//2, cy - dh//2

    glow(img, cx, cy, 180, GREEN)
    d = ImageDraw.Draw(img)

    # folded corner
    fold = 40
    poly(d, [
        (dx, dy),
        (dx + dw - fold, dy),
        (dx + dw, dy + fold),
        (dx + dw, dy + dh),
        (dx, dy + dh),
    ], (230, 255, 230))
    poly(d, [
        (dx + dw - fold, dy),
        (dx + dw, dy + fold),
        (dx + dw - fold, dy + fold),
    ], (180, 220, 180))

    # lines on doc
    for row in range(5):
        d.line([(dx+18, dy+60+row*32), (dx+dw-18, dy+60+row*32)],
               fill=(120, 180, 120), width=6)

    # wings (left)
    wing_l = [
        (dx - 10, cy),
        (dx - 130, cy - 80),
        (dx - 160, cy - 20),
        (dx - 120, cy + 30),
        (dx - 80, cy + 60),
        (dx - 20, cy + 40),
    ]
    poly(d, wing_l, GREEN)
    # wing feather lines
    for i in range(3):
        d.line([(dx-20-i*30, cy-20+i*15),
                (dx-90-i*20, cy-50+i*20)],
               fill=(30,160,80), width=3)

    # wings (right)
    wing_r = [(2*cx - x, y) for x, y in wing_l]
    poly(d, wing_r, GREEN)
    for i in range(3):
        d.line([(dx+dw+20+i*30, cy-20+i*15),
                (dx+dw+90+i*20, cy-50+i*20)],
               fill=(30,160,80), width=3)

    stars(d, [(160,160),(870,180),(820,780),(180,820)], GREEN)
    save(img, "share_success.png")


# ══════════════════════════════════════════════════════════════════════════════
# 5. export_backup — 完好的保险箱 + 手机灰烬
# ══════════════════════════════════════════════════════════════════════════════
def make_export_backup():
    img, d = new()

    # --- ash pile (burnt phone) ---
    ax, ay = 680, 760
    # ash mound
    poly(d, [(ax-120, ay), (ax+100, ay),
             (ax+80, ay-45), (ax+20, ay-35),
             (ax-40, ay-55), (ax-100, ay-30)], GREY)
    # ash particles
    for px_, py_ in [(ax-80, ay-60), (ax+40, ay-70),
                     (ax-20, ay-80), (ax+80, ay-55),
                     (ax-60, ay-90)]:
        d.line([(px_, py_), (px_+12, py_-20)], fill=GREY, width=3)
    # tiny phone outline in ash
    rect(d, ax-25, ay-52, 50, 40, (80,80,80), radius=5, outline=GREY, ow=2)

    # --- glowing vault ---
    vx, vy = 390, 490
    glow(img, vx, vy, 280, GOLD)
    d = ImageDraw.Draw(img)

    # vault body
    circle(d, vx, vy, 200, DARK3, outline=GOLD, ow=10)
    circle(d, vx, vy, 185, DARK2)

    # vault door bolts
    for ba in [0, 90, 180, 270]:
        brd = math.radians(ba)
        bx_ = vx + 145 * math.cos(brd)
        by_ = vy + 145 * math.sin(brd)
        circle(d, int(bx_), int(by_), 22, DARK3, outline=GOLD, ow=5)

    # vault handle (wheel)
    circle(d, vx, vy, 80, DARK3, outline=GOLD, ow=8)
    for ha in range(0, 360, 45):
        hrd = math.radians(ha)
        hx1 = vx + 30 * math.cos(hrd)
        hy1 = vy + 30 * math.sin(hrd)
        hx2 = vx + 72 * math.cos(hrd)
        hy2 = vy + 72 * math.sin(hrd)
        d.line([(hx1, hy1), (hx2, hy2)], fill=GOLD, width=7)
    circle(d, vx, vy, 22, GOLD)

    # lock hole
    circle(d, vx, vy+55, 12, BG)
    rect(d, vx-7, vy+55, 14, 20, BG, radius=3)

    # gold rays from vault
    for ra in range(0, 360, 30):
        rrd = math.radians(ra)
        r1, r2 = 205, 240
        d.line([vx + r1*math.cos(rrd), vy + r1*math.sin(rrd),
                vx + r2*math.cos(rrd), vy + r2*math.sin(rrd)],
               fill=GOLD, width=4)

    # shield icon (top right of vault)
    sx, sy = vx + 120, vy - 140
    poly(d, [(sx, sy-30), (sx-28, sy-15), (sx-28, sy+10),
             (sx, sy+30), (sx+28, sy+10), (sx+28, sy-15)], GREEN)
    # checkmark in shield
    d.line([(sx-12, sy+5), (sx-3, sy+16), (sx+14, sy-8)],
           fill=WHITE, width=5)

    save(img, "export_backup.png")


# ══════════════════════════════════════════════════════════════════════════════
# 6. import_twice — 手机戴学位帽翻厚书 + 专家徽章
# ══════════════════════════════════════════════════════════════════════════════
def make_import_twice():
    img, d = new()
    cx, cy = 512, 470

    # --- thick book (right side, open) ---
    bx, by = cx + 140, cy + 40
    bw, bh = 220, 280
    # pages (many thin rects)
    for i in range(8):
        rect(d, bx + i*2, by - i, bw, bh, (230, 225, 210), radius=2)
    # cover back
    rect(d, bx, by, bw, bh, BLUE, radius=8)
    # spine
    rect(d, bx-18, by, 18, bh, (40, 100, 180), radius=4)
    # lines on open page
    for row in range(8):
        d.line([(bx+20, by+35+row*26), (bx+bw-20, by+35+row*26)],
               fill=(180, 175, 165), width=4)

    # --- phone body ---
    pw, ph = 200, 310
    px, py = cx - pw//2 - 80, cy - ph//2
    rect(d, px, py, pw, ph, DARK3, radius=35, outline=ORANGE, ow=6)
    rect(d, px+8, py+8, pw-16, ph-16, DARK2, radius=28)

    # phone screen - course table grid
    for row in range(4):
        for col in range(3):
            rx = px + 18 + col * 53
            ry = py + 40 + row * 55
            rect(d, rx, ry, 46, 48, ORANGE if (row+col)%3==0 else DARK3, radius=6)

    # --- mortarboard on phone ---
    mx, my = px + pw//2, py - 10
    brim = 120
    rect(d, mx - brim//2, my - 15, brim, 18, (50, 50, 80), radius=4)
    poly(d, [(mx - 70, my - 15), (mx + 70, my - 15),
             (mx + 55, my - 55), (mx - 55, my - 55)], (50, 50, 80))
    rect(d, mx-18, my-65, 36, 16, (50, 50, 80), radius=3)
    # tassel
    d.line([(mx+45, my-52), (mx+60, my+5)], fill=ORANGE, width=5)
    circle(d, mx+60, my+12, 9, ORANGE)

    # --- expert star badge ---
    badx, bady = px + pw - 20, py + ph - 20
    for i in range(5):
        ba = math.radians(i * 72 - 90)
        bbo = math.radians(i * 72 - 90 + 36)
        ox = badx + 38 * math.cos(ba)
        oy = bady + 38 * math.sin(ba)
        ix = badx + 18 * math.cos(bbo)
        iy = bady + 18 * math.sin(bbo)
        if i == 0:
            pts_star = [(ox, oy), (ix, iy)]
        else:
            pts_star += [(ox, oy), (ix, iy)]
    poly(d, pts_star, GOLD)
    circle(d, badx, bady, 16, ORANGE)

    # pencil drawing line from phone to book
    d.line([(px+pw+5, cy+60), (bx+5, by+90)],
           fill=ORANGE, width=4)

    glow(img, px+pw//2, py+ph//2, 180, ORANGE)
    save(img, "import_twice.png")


# ══════════════════════════════════════════════════════════════════════════════
# 7. delete_once — 微笑的课表被火焰吞噬
# ══════════════════════════════════════════════════════════════════════════════
def make_delete_once():
    img, d = new()
    cx, cy = 512, 430

    # --- flame glow ---
    glow(img, cx, cy + 180, 320, FIRE)
    glow(img, cx, cy + 80,  200, RED)
    d = ImageDraw.Draw(img)

    # --- flames (back layer) ---
    def flame(d, x, y, w, h, col1, col2):
        # simple flame shape
        poly(d, [
            (x, y),
            (x - w//3, y - h*2//3),
            (x - w//6, y - h//3),
            (x - w//2, y - h),
            (x,        y - h*3//4),
            (x + w//2, y - h),
            (x + w//6, y - h//3),
            (x + w//3, y - h*2//3),
            (x + w, y),
        ], col1)
        poly(d, [
            (x + w//4, y),
            (x,        y - h//2),
            (x + w//4, y - h*3//4),
            (x + w//2, y - h//2),
            (x + 3*w//4, y),
        ], col2)

    flame(d, cx - 130, cy + 280, 90,  220, RED,  FIRE)
    flame(d, cx + 50,  cy + 280, 90,  250, RED,  FIRE)
    flame(d, cx - 30,  cy + 280, 120, 290, FIRE, GOLD)
    flame(d, cx + 140, cy + 280, 80,  200, RED,  FIRE)
    flame(d, cx - 180, cy + 280, 80,  180, RED,  FIRE)

    # --- document ---
    dw, dh = 260, 320
    dx, dy = cx - dw//2, cy - dh//2
    fold = 50
    poly(d, [
        (dx, dy),
        (dx + dw - fold, dy),
        (dx + dw, dy + fold),
        (dx + dw, dy + dh),
        (dx, dy + dh),
    ], (255, 252, 240))
    poly(d, [
        (dx + dw - fold, dy),
        (dx + dw, dy + fold),
        (dx + dw - fold, dy + fold),
    ], (220, 215, 200))

    # text lines on doc
    for row in range(6):
        y_ = dy + 70 + row * 34
        w_ = dw - 40 - (row % 2) * 30
        d.line([(dx+20, y_), (dx+20+w_, y_)], fill=(180,170,150), width=6)

    # burn/char effect at bottom (dark gradient)
    for i in range(8):
        alpha = int(255 * i / 8)
        y_burn = dy + dh - 20 - i * 15
        overlay = Image.new("RGBA", img.size, (0,0,0,0))
        od = ImageDraw.Draw(overlay)
        od.rectangle([dx - 5, y_burn, dx + dw + 5, dy + dh + 5],
                     fill=(20, 5, 0, alpha))
        img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    d = ImageDraw.Draw(img)

    # --- smiley face on document ---
    fx, fy = cx, cy - 20
    circle(d, fx, fy, 55, GOLD)
    circle(d, fx, fy, 50, (255, 230, 50))
    # eyes (^^)
    for ex in [fx - 17, fx + 17]:
        d.arc([ex-10, fy-24, ex+10, fy-4], 200, 340, fill=BG, width=6)
    # big smile
    d.arc([fx-28, fy+5, fx+28, fy+40], 0, 180, fill=BG, width=7)

    # ash/ember particles
    for px_, py_ in [(cx-160, cy-50), (cx+170, cy-80),
                     (cx-90, cy-140), (cx+100, cy-120),
                     (cx+200, cy+20), (cx-200, cy+30)]:
        circle(d, px_, py_, 5, FIRE)
        d.line([(px_, py_), (px_+8, py_-18)],
               fill=GOLD, width=2)

    save(img, "delete_once.png")


# ══════════════════════════════════════════════════════════════════════════════
# 8. import_backup — 裂开的旧软盘 + 崭新课表破壳而出
# ══════════════════════════════════════════════════════════════════════════════
def make_import_backup():
    img, d = new()
    cx, cy = 512, 520

    # --- glow ---
    glow(img, cx, cy - 80, 280, CYAN)
    glow(img, cx, cy - 80, 140, GOLD)
    d = ImageDraw.Draw(img)

    # --- old floppy disk (bottom, cracking) ---
    fw, fh = 300, 300
    fx, fy = cx - fw//2, cy - fh//2 + 80

    # floppy body (two halves with crack)
    poly(d, [
        (fx, fy),
        (fx + fw//2 - 8, fy),
        (fx + fw//2 - 22, fy + fh//2),
        (fx + fw//2 - 8, fy + fh),
        (fx, fy + fh),
    ], (60, 70, 100))
    poly(d, [
        (fx + fw//2 + 8, fy),
        (fx + fw, fy),
        (fx + fw, fy + fh),
        (fx + fw//2 + 8, fy + fh),
        (fx + fw//2 + 22, fy + fh//2),
    ], (50, 60, 90))

    # crack line (jagged)
    crack = [
        (cx - 8, fy - 10),
        (cx + 5, fy + 60),
        (cx - 12, fy + 120),
        (cx + 8, fy + 180),
        (cx - 5, fy + fh + 10),
    ]
    d.line(crack, fill=CYAN, width=5)

    # floppy metal shutter
    rect(d, fx + 30, fy + 30, fw - 60, 65, (100, 110, 140), radius=5)
    rect(d, fx + 50, fy + 35, fw - 100, 55, DARK2, radius=4)

    # floppy label area
    rect(d, fx + 18, fy + 115, fw - 36, 130, (200, 195, 210), radius=4)
    # faded old lines on label
    for row in range(4):
        d.line([(fx+30, fy+135+row*26), (fx+fw-30, fy+135+row*26)],
               fill=(155,150,165), width=4)

    # floppy disk hole
    circle(d, fx + fw - 42, fy + fh - 42, 22, DARK2)
    circle(d, fx + fw - 42, fy + fh - 42, 10, (90, 95, 130))

    # --- new digital document emerging (top, glowing) ---
    nw, nh = 210, 260
    nx, ny = cx - nw//2, cy - nh - 90
    fold2 = 42

    # glow around new doc
    glow(img, cx, ny + nh//2, 160, CYAN)
    d = ImageDraw.Draw(img)

    poly(d, [
        (nx, ny),
        (nx + nw - fold2, ny),
        (nx + nw, ny + fold2),
        (nx + nw, ny + nh),
        (nx, ny + nh),
    ], (220, 250, 255))
    poly(d, [
        (nx + nw - fold2, ny),
        (nx + nw, ny + fold2),
        (nx + nw - fold2, ny + fold2),
    ], (160, 210, 240))

    # lines on new doc
    for row in range(5):
        d.line([(nx+16, ny+55+row*32), (nx+nw-16, ny+55+row*32)],
               fill=(100, 170, 210), width=6)

    # shine sparkles on new doc
    for sp in [(nx+20, ny+20), (nx+nw-25, ny+15), (nx+nw-15, ny+nh-20)]:
        for sa in range(0, 360, 90):
            a = math.radians(sa)
            d.line([sp[0], sp[1],
                    sp[0]+12*math.cos(a), sp[1]+12*math.sin(a)],
                   fill=GOLD, width=3)
        circle(d, sp[0], sp[1], 4, GOLD)

    # speed lines (old→new transformation)
    for i in range(5):
        lx = cx - 100 + i * 50
        d.line([(lx, fy - 10), (lx, ny + nh + 10)],
               fill=(*CYAN,)[:3], width=2)

    save(img, "import_backup.png")


# ── run all ───────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    make_import_success()
    make_notification_on()
    make_widget_add()
    make_share_success()
    make_export_backup()
    make_import_twice()
    make_delete_once()
    make_import_backup()
    print("\nAll 8 achievement images generated.")
