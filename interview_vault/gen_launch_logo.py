"""生成与 logo_mark.svg（立体版品牌标志）同构的原生启动 logo PNG。
日间（drawable/）纸白底投影轻，夜间（drawable-night/）墨绿底投影重。"""
from PIL import Image, ImageDraw
import math

SS = 4
SIZE = 512
BIG = SIZE * SS  # 2048

GOLD_HI = (250, 226, 148)
GOLD_MID = (233, 188, 78)
GOLD_LO = (202, 148, 40)
GREEN_Q = (24, 58, 44)
BRONZE = (168, 124, 42)
SPARK = (249, 222, 138)

# logo_mark.svg viewBox 48：内容 bbox x 9.06-39.9, y 5.1-38.5
S = BIG * 0.86 / 33.4
OX = BIG / 2 - 24.48 * S
OY = BIG / 2 - 21.8 * S


def P(u, v):
    return (OX + u * S, OY + v * S)


def rounded_gradient_card(w, h, radius_frac=0.16):
    card = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    grad = Image.new('RGBA', (1, h))
    px = grad.load()
    for y in range(h):
        t = y / (h - 1)
        a, b = (GOLD_HI, GOLD_MID) if t < 0.5 else (GOLD_MID, GOLD_LO)
        k = t / 0.5 if t < 0.5 else (t - 0.5) / 0.5
        px[0, y] = (*[round(p + (q - p) * k) for p, q in zip(a, b)], 255)
    grad = grad.resize((w, h))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, w - 1, h - 1], radius=int(w * radius_frac), fill=255)
    card.paste(grad, (0, 0), mask)
    hl = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    hp = hl.load()
    m = mask.load()
    for y in range(int(h * 0.16)):
        a = int(80 * (1 - y / (h * 0.16)))
        for x in range(w):
            if m[x, y]:
                hp[x, y] = (255, 250, 230, a)
    return Image.alpha_composite(card, hl)


def rot_paste(canvas, img, deg, center):
    rot = img.rotate(deg, expand=True, resample=Image.BICUBIC)
    canvas.alpha_composite(rot, (int(center[0] - rot.width / 2),
                                 int(center[1] - rot.height / 2)))


def build(shadow_alpha):
    img = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))

    # 后卡组：rotate 9°，中心 (30,17.5)
    half_b = int(12 * S)
    back = Image.new('RGBA', (2 * half_b, 2 * half_b), (0, 0, 0, 0))
    bd = ImageDraw.Draw(back)

    def gb(u, v):
        return ((u - 30) * S + half_b, (v - 17.5) * S + half_b)

    bd.rounded_rectangle([*gb(21.5, 9.75), *gb(38.5, 25.25)],
                         radius=int(3 * S), fill=(*BRONZE, 255))
    bd.rounded_rectangle([*gb(22.3, 10.55), *gb(37.7, 24.45)],
                         radius=int(2.5 * S), outline=(231, 190, 98, 205),
                         width=max(2, int(0.35 * S)))
    rot_paste(img, back, 9, P(30, 17.5))

    # 前卡组：rotate -7°，中心 (22.5,26.5)：投影+渐变卡+高光+问号
    half_f = int(17 * S)
    front = Image.new('RGBA', (2 * half_f, 2 * half_f), (0, 0, 0, 0))

    def gf(u, v):
        return ((u - 22.5) * S + half_f, (v - 26.5) * S + half_f)

    fd = ImageDraw.Draw(front)
    fd.rounded_rectangle([*gf(10.85, 16.9), *gf(35.35, 38.1)],
                         radius=int(3.9 * S), fill=(5, 18, 12, shadow_alpha))
    card = rounded_gradient_card(int(24.5 * S), int(21.2 * S))
    front.alpha_composite(card, (int(gf(10.25, 15.9)[0]),
                                 int(gf(10.25, 15.9)[1])))

    # Q：translate(6.62,3.22) scale(0.836) 作用于单位坐标
    W = max(2, int(2.0 * S))

    def QP(u, v):
        base = gf(0, 0)
        return (base[0] + (6.62 + u * 0.836) * S,
                base[1] + (3.22 + v * 0.836) * S)

    qd = ImageDraw.Draw(front)
    qd.arc([*QP(15.5, 20), *QP(23.5, 28)], start=180, end=360,
           fill=(*GREEN_Q, 255), width=W)
    qd.arc([*QP(14.5, 19.5), *QP(23.5, 28.5)], start=0, end=90,
           fill=(*GREEN_Q, 255), width=W)
    cu, cv = QP(19, 33.5)
    r = 1.42 * 0.836 * S
    qd.ellipse([cu - r, cv - r, cu + r, cv + r], fill=(*GREEN_Q, 255))
    for (u, v) in [(15.5, 24), (23.5, 24), (19, 28.5)]:
        cu, cv = QP(u, v)
        r = W / 2
        qd.ellipse([cu - r, cv - r, cu + r, cv + r], fill=(*GREEN_Q, 255))

    rot_paste(img, front, -7, P(22.5, 26.5))

    # 星花
    dd = ImageDraw.Draw(img)
    cu, cv = P(37.5, 7.5)
    R, ri = 2.4 * S, 0.92 * S
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = R if i % 2 == 0 else ri
        pts.append((cu + rr * math.cos(ang), cv + rr * math.sin(ang)))
    dd.polygon(pts, fill=(*SPARK, 255))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


res = 'android/app/src/main/res'
build(85).save(f'{res}/drawable/launch_logo.png')        # 日间：纸白底，投影轻
build(130).save(f'{res}/drawable-night/launch_logo.png') # 夜间：墨绿底，投影重
print('launch logos regenerated (bold motif, day/night shadow)')
